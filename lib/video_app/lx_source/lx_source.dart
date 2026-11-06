import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as hashes;
import 'package:dio/dio.dart';

import '../../l10n/video_strings.dart';
import '../../models/audio_quality.dart';
import '../../models/platform_type.dart';
import '../custom_source/custom_source_models.dart';

class LxSourceException implements Exception {
  const LxSourceException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

class LxSourceConfig {
  const LxSourceConfig({
    required this.name,
    required this.version,
    required this.origin,
    required this.script,
    required this.sha256,
    required this.sources,
    this.enabled = false,
    this.allowForDownloads = false,
  });
  final String name, version, script, sha256;
  final Uri origin;
  final Map<String, List<String>> sources;
  final bool enabled, allowForDownloads;

  LxSourceConfig copyWith({bool? enabled, bool? allowForDownloads}) =>
      LxSourceConfig(
        name: name,
        version: version,
        origin: origin,
        script: script,
        sha256: sha256,
        sources: sources,
        enabled: enabled ?? this.enabled,
        allowForDownloads: allowForDownloads ?? this.allowForDownloads,
      );
  Map<String, dynamic> toJson() => {
    'name': name,
    'version': version,
    'origin': origin.toString(),
    'script': script,
    'sha256': sha256,
    'sources': sources,
    'enabled': enabled,
    'allowForDownloads': allowForDownloads,
  };
  factory LxSourceConfig.fromJson(Map<String, dynamic> json) => LxSourceConfig(
    name: json['name'] as String,
    version: json['version'] as String,
    origin: Uri.parse(json['origin'] as String),
    script: json['script'] as String,
    sha256: json['sha256'] as String,
    sources: (json['sources'] as Map).map(
      (k, v) => MapEntry(k as String, List<String>.from(v as List)),
    ),
    enabled: json['enabled'] == true,
    allowForDownloads: json['allowForDownloads'] == true,
  );

  CustomSourceConfig get fallbackConfig => CustomSourceConfig(
    id: 'lx',
    name: name,
    endpoint: origin,
    enabled: enabled,
    allowForDownloads: allowForDownloads,
    platforms: {
      if (sources.containsKey('tx')) PlatformType.qq,
      if (sources.containsKey('wy')) PlatformType.netease,
    },
  );
}

abstract interface class LxSourceEngine {
  Future<Map<String, List<String>>> inspect(
    String script, {
    CancelToken? cancelToken,
  });
  Future<String> resolve(
    LxSourceConfig config,
    CustomSourceRequest request, {
    CancelToken? cancelToken,
  });
}

Uri lxImportUri(String value) {
  var uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw const LxSourceException('link', VideoStrings.lxInvalidLink);
  }
  if (uri.host == 'github.com') {
    final p = uri.pathSegments;
    if (p.length < 5 || p[2] != 'blob') {
      throw const LxSourceException('link', VideoStrings.lxFileLinkRequired);
    }
    uri = Uri.https(
      'raw.githubusercontent.com',
      [p[0], p[1], ...p.skip(3)].join('/'),
    );
  }
  return uri;
}

List<Uri> lxDownloadUris(Uri origin) {
  if (origin.host != 'raw.githubusercontent.com') return [origin];
  final parts = origin.pathSegments;
  if (parts.length < 4) return [origin];
  return [
    origin,
    Uri.https(
      'fastly.jsdelivr.net',
      '/gh/${parts[0]}/${parts[1]}@${parts[2]}/${parts.skip(3).join('/')}',
    ),
  ];
}

String lxPlatform(PlatformType platform) => switch (platform) {
  PlatformType.qq => 'tx',
  PlatformType.netease => 'wy',
  _ => throw const LxSourceException(
    'platform',
    VideoStrings.lxUnsupportedPlatform,
  ),
};

String lxQuality(AudioLevel quality) => switch (quality) {
  AudioLevel.low => '128k',
  AudioLevel.medium || AudioLevel.high => '320k',
  AudioLevel.lossless => 'flac',
  AudioLevel.hires => 'flac24bit',
  _ => throw const LxSourceException(
    'quality',
    VideoStrings.customSourceQualityUnsupported,
  ),
};

Future<String> lxReadBody(
  ResponseBody response,
  int maxBytes, {
  CancelToken? cancelToken,
}) async {
  final bytes = <int>[];
  await for (final chunk in response.stream) {
    if (cancelToken?.isCancelled == true) {
      throw const LxSourceException(
        'cancelled',
        VideoStrings.customSourceRequestCancelled,
      );
    }
    if (bytes.length + chunk.length > maxBytes) {
      throw const LxSourceException('size', VideoStrings.lxTooLarge);
    }
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

class LxSourceImporter {
  LxSourceImporter({required this.dio, required this.engine});
  final Dio dio;
  final LxSourceEngine engine;

  Future<LxSourceConfig> importLink(
    String link, {
    CancelToken? cancelToken,
  }) async {
    final uri = lxImportUri(link);
    final downloadCancel = CancelToken();
    var oversized = false;
    var timedOut = false;
    if (cancelToken?.isCancelled == true) {
      throw const LxSourceException(
        'cancelled',
        VideoStrings.customSourceRequestCancelled,
      );
    }
    unawaited(cancelToken?.whenCancel.then((_) => downloadCancel.cancel()));
    final deadline = Timer(const Duration(seconds: 30), () {
      timedOut = true;
      downloadCancel.cancel();
    });
    try {
      Response<ResponseBody>? response;
      final candidates = lxDownloadUris(uri);
      for (var index = 0; index < candidates.length; index++) {
        try {
          response = await dio.getUri<ResponseBody>(
            candidates[index],
            cancelToken: downloadCancel,
            onReceiveProgress: (count, _) {
              if (count > 1024 * 1024) {
                oversized = true;
                downloadCancel.cancel();
              }
            },
            options: Options(
              responseType: ResponseType.stream,
              followRedirects: false,
              maxRedirects: 0,
              validateStatus: (_) => true,
              receiveTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 15),
            ),
          );
          break;
        } on DioException catch (error) {
          final canRetry =
              index + 1 < candidates.length &&
              !timedOut &&
              !oversized &&
              !downloadCancel.isCancelled &&
              error.type != DioExceptionType.cancel;
          if (!canRetry) rethrow;
        }
      }
      if (response == null ||
          response.statusCode != 200 ||
          response.data == null) {
        throw const LxSourceException(
          'download',
          VideoStrings.lxDownloadFailed,
        );
      }
      final script = await lxReadBody(
        response.data!,
        1024 * 1024,
        cancelToken: downloadCancel,
      );
      final name = RegExp(
        r'^\s*\*?\s*@name\s+([^\r\n]+)',
        multiLine: true,
      ).firstMatch(script)?.group(1)?.trim();
      if (script.trimLeft().startsWith('<') ||
          name == null ||
          name.isEmpty ||
          name.length > 160) {
        throw const LxSourceException('script', VideoStrings.lxInvalidScript);
      }
      final version =
          RegExp(
            r'^\s*\*?\s*@version\s+([^\r\n]+)',
            multiLine: true,
          ).firstMatch(script)?.group(1)?.trim() ??
          '';
      final sources = await engine.inspect(script, cancelToken: downloadCancel);
      if (!sources.keys.any(
        (key) => (key == 'tx' || key == 'wy') && sources[key]!.isNotEmpty,
      )) {
        throw const LxSourceException(
          'platform',
          VideoStrings.lxUnsupportedPlatform,
        );
      }
      return LxSourceConfig(
        name: name,
        version: version,
        origin: uri,
        script: script,
        sha256: hashes.sha256.convert(utf8.encode(script)).toString(),
        sources: sources,
      );
    } on LxSourceException {
      if (timedOut) {
        throw const LxSourceException('timeout', VideoStrings.lxTimedOut);
      }
      rethrow;
    } on DioException catch (error) {
      if (timedOut) {
        throw const LxSourceException('timeout', VideoStrings.lxTimedOut);
      }
      if (oversized) {
        throw const LxSourceException('size', VideoStrings.lxTooLarge);
      }
      throw LxSourceException(
        error.type == DioExceptionType.cancel ? 'cancelled' : 'download',
        error.type == DioExceptionType.cancel
            ? VideoStrings.customSourceRequestCancelled
            : VideoStrings.lxDownloadFailed,
      );
    } catch (_) {
      throw const LxSourceException('script', VideoStrings.lxInvalidScript);
    } finally {
      deadline.cancel();
      downloadCancel.cancel();
    }
  }
}

class LxCustomSourceResolver implements CustomSourceResolver {
  LxCustomSourceResolver({required this.config, required this.engine});
  final LxSourceConfig config;
  final LxSourceEngine engine;
  @override
  Future<CustomSourceResult> resolve(
    CustomSourceRequest request, {
    CancelToken? cancelToken,
  }) async {
    try {
      final url = Uri.tryParse(
        await engine.resolve(config, request, cancelToken: cancelToken),
      );
      if (url == null ||
          url.scheme != 'https' ||
          url.host.isEmpty ||
          url.userInfo.isNotEmpty) {
        throw const LxSourceException(
          'url',
          VideoStrings.customSourceInvalidUrl,
        );
      }
      return CustomSourceResult(
        url: url,
        actualQuality: request.quality,
        sourceId: 'lx',
        sourceName: VideoStrings.lxUnverifiedSource(config.name),
      );
    } on LxSourceException catch (error) {
      throw CustomSourceException(
        code: switch (error.code) {
          'cancelled' => CustomSourceFailureCode.cancelled,
          'timeout' => CustomSourceFailureCode.timeout,
          'quality' || 'platform' => CustomSourceFailureCode.qualityUnavailable,
          'url' || 'script' => CustomSourceFailureCode.invalidResponse,
          _ => CustomSourceFailureCode.sourceUnavailable,
        },
        message: error.message,
        retryable: error.code == 'timeout' || error.code == 'network',
      );
    }
  }
}
