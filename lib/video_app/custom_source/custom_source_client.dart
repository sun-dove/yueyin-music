import 'dart:convert';

import 'package:dio/dio.dart';

import '../../l10n/video_strings.dart';
import '../../models/audio_quality.dart';
import 'custom_source_models.dart';
import 'custom_source_storage.dart';

class HttpCustomSourceResolver implements CustomSourceResolver {
  HttpCustomSourceResolver({
    required this.config,
    required this.dio,
    required this.credentialStore,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final CustomSourceConfig config;
  final Dio dio;
  final CustomSourceCredentialStore credentialStore;
  final DateTime Function() _now;

  @override
  Future<CustomSourceResult> resolve(
    CustomSourceRequest request, {
    CancelToken? cancelToken,
  }) async {
    config.validate();
    final token = config.credentialRef == null
        ? null
        : await credentialStore.readToken(config.credentialRef!);
    try {
      final response = await dio.postUri<Object?>(
        _resolveUri(config.endpoint),
        data: {
          'requestId': request.requestId,
          'platform': request.platform.name,
          'song': {
            'id': request.song.id,
            'title': request.song.name,
            'artists': request.song.artists
                .map((artist) => artist.name)
                .toList(),
            'album': request.song.album?.name ?? '',
          },
          'quality': request.quality.name,
          'purpose': request.purpose.name,
        },
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          followRedirects: false,
          maxRedirects: 0,
          sendTimeout: Duration(seconds: config.timeoutSeconds),
          receiveTimeout: Duration(seconds: config.timeoutSeconds),
          headers: {
            Headers.contentTypeHeader: Headers.jsonContentType,
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
        ),
        cancelToken: cancelToken,
      );
      final status = response.statusCode ?? 0;
      final body = _decode(response.data);
      if (status < 200 || status >= 300) {
        throw _statusError(status, body);
      }
      return _parseResult(body, request.quality);
    } on CustomSourceException {
      rethrow;
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) {
        throw const CustomSourceException(
          code: CustomSourceFailureCode.cancelled,
          message: VideoStrings.customSourceRequestCancelled,
          retryable: false,
        );
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        throw const CustomSourceException(
          code: CustomSourceFailureCode.timeout,
          message: VideoStrings.customSourceTimedOut,
          retryable: true,
        );
      }
      throw const CustomSourceException(
        code: CustomSourceFailureCode.sourceUnavailable,
        message: VideoStrings.customSourceUnavailable,
        retryable: true,
      );
    } on Object {
      throw const CustomSourceException(
        code: CustomSourceFailureCode.invalidResponse,
        message: VideoStrings.customSourceIncompatible,
        retryable: false,
      );
    }
  }

  Uri _resolveUri(Uri endpoint) {
    final path = endpoint.path.endsWith('/')
        ? '${endpoint.path}v1/resolve'
        : '${endpoint.path}/v1/resolve';
    return endpoint.replace(path: path);
  }

  Map<String, dynamic> _decode(Object? value) {
    try {
      if (value is String && utf8.encode(value).length > 65536) {
        throw const CustomSourceException(
          code: CustomSourceFailureCode.invalidResponse,
          message: VideoStrings.customSourceIncompatible,
          retryable: false,
        );
      }
      final decoded = value is String ? jsonDecode(value) : value;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on CustomSourceException {
      rethrow;
    } catch (_) {}
    throw const CustomSourceException(
      code: CustomSourceFailureCode.invalidResponse,
      message: VideoStrings.customSourceIncompatible,
      retryable: false,
    );
  }

  CustomSourceException _statusError(int status, Map<String, dynamic> body) {
    final error = body['error'] is Map
        ? Map<String, dynamic>.from(body['error'] as Map)
        : const <String, dynamic>{};
    final serverCode = error['code']?.toString();
    final mapped = switch (status) {
      401 || 403 => CustomSourceFailureCode.unauthorized,
      404 => CustomSourceFailureCode.notFound,
      429 => CustomSourceFailureCode.rateLimited,
      >= 500 => CustomSourceFailureCode.sourceUnavailable,
      _ => switch (serverCode) {
        'not_found' => CustomSourceFailureCode.notFound,
        'quality_unavailable' => CustomSourceFailureCode.qualityUnavailable,
        'unauthorized' => CustomSourceFailureCode.unauthorized,
        'rate_limited' => CustomSourceFailureCode.rateLimited,
        'timeout' => CustomSourceFailureCode.timeout,
        'source_unavailable' => CustomSourceFailureCode.sourceUnavailable,
        _ => CustomSourceFailureCode.invalidResponse,
      },
    };
    return CustomSourceException(
      code: mapped,
      message: error['message']?.toString() ?? _message(mapped),
      retryable:
          error['retryable'] == true ||
          mapped == CustomSourceFailureCode.rateLimited ||
          mapped == CustomSourceFailureCode.timeout ||
          mapped == CustomSourceFailureCode.sourceUnavailable,
    );
  }

  CustomSourceResult _parseResult(
    Map<String, dynamic> body,
    AudioLevel requested,
  ) {
    final url = Uri.tryParse(body['url']?.toString() ?? '');
    if (url == null ||
        url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty) {
      throw const CustomSourceException(
        code: CustomSourceFailureCode.invalidResponse,
        message: VideoStrings.customSourceInvalidUrl,
        retryable: false,
      );
    }
    final qualityName = body['quality']?.toString() ?? '';
    final quality = AudioLevel.values
        .where((value) => value.name == qualityName)
        .firstOrNull;
    if (quality == null) {
      throw const CustomSourceException(
        code: CustomSourceFailureCode.invalidResponse,
        message: VideoStrings.customSourceUnknownQuality,
        retryable: false,
      );
    }
    if (quality.index < requested.index) {
      throw const CustomSourceException(
        code: CustomSourceFailureCode.qualityUnavailable,
        message: VideoStrings.customSourceQualityUnavailable,
        retryable: false,
      );
    }
    final expiresAt = body['expiresAt'] == null
        ? null
        : DateTime.tryParse(body['expiresAt'].toString())?.toUtc();
    if (body['expiresAt'] != null &&
        (expiresAt == null || !expiresAt.isAfter(_now().toUtc()))) {
      throw const CustomSourceException(
        code: CustomSourceFailureCode.invalidResponse,
        message: VideoStrings.customSourceExpired,
        retryable: false,
      );
    }
    return CustomSourceResult(
      url: url,
      actualQuality: quality,
      format: body['format']?.toString(),
      bitrate: (body['bitrate'] as num?)?.toInt(),
      expiresAt: expiresAt,
      sourceId: config.id,
      sourceName: config.name,
    );
  }

  String _message(CustomSourceFailureCode code) => switch (code) {
    CustomSourceFailureCode.notFound => VideoStrings.customSourceNotFound,
    CustomSourceFailureCode.qualityUnavailable =>
      VideoStrings.customSourceQualityUnsupported,
    CustomSourceFailureCode.unauthorized =>
      VideoStrings.customSourceUnauthorized,
    CustomSourceFailureCode.rateLimited => VideoStrings.customSourceRateLimited,
    CustomSourceFailureCode.timeout => VideoStrings.customSourceTimedOut,
    CustomSourceFailureCode.sourceUnavailable =>
      VideoStrings.customSourceUnavailable,
    CustomSourceFailureCode.invalidResponse =>
      VideoStrings.customSourceIncompatible,
    CustomSourceFailureCode.cancelled =>
      VideoStrings.customSourceRequestCancelled,
  };
}
