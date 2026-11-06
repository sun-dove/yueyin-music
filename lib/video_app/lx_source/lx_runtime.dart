import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../../l10n/video_strings.dart';
import '../custom_source/custom_source_models.dart';
import 'lx_bootstrap.dart';
import 'lx_source.dart';
import 'lx_http.dart';

abstract interface class LxSandbox {
  Future<void> create(String id);
  Future<String> evaluate(String id, String code);
  Future<void> close(String id);
}

class MethodChannelLxSandbox implements LxSandbox {
  const MethodChannelLxSandbox();
  static const channel = MethodChannel('app.videomusic.player/lx_sandbox');
  @override
  Future<void> create(String id) =>
      channel.invokeMethod<void>('create', {'id': id});
  @override
  Future<String> evaluate(String id, String code) async =>
      await channel.invokeMethod<String>('evaluate', {
        'id': id,
        'code': code,
      }) ??
      '';
  @override
  Future<void> close(String id) =>
      channel.invokeMethod<void>('close', {'id': id});
}

class LxSourceRuntime implements LxSourceEngine {
  LxSourceRuntime({
    LxSandbox? sandbox,
    Dio? dio,
    this.timeout = const Duration(seconds: 15),
  }) : sandbox = sandbox ?? const MethodChannelLxSandbox(),
       dio = dio ?? createLxDio();
  final LxSandbox sandbox;
  final Dio dio;
  final Duration timeout;
  static int _serial = 0;

  @override
  Future<Map<String, List<String>>> inspect(
    String script, {
    CancelToken? cancelToken,
  }) async => _sources(await _run(script, cancelToken: cancelToken));

  @override
  Future<String> resolve(
    LxSourceConfig config,
    CustomSourceRequest request, {
    CancelToken? cancelToken,
  }) async {
    final platform = lxPlatform(request.platform),
        quality = lxQuality(request.quality);
    if (!(config.sources[platform]?.contains(quality) ?? false)) {
      throw const LxSourceException(
        'quality',
        VideoStrings.customSourceQualityUnsupported,
      );
    }
    final value = await _run(
      config.script,
      request: {
        'action': 'musicUrl',
        'source': platform,
        'info': {
          'type': quality,
          'musicInfo': {
            'songmid': request.song.id,
            'songId': request.song.id,
            'name': request.song.name,
            'singer': request.song.artists.map((e) => e.name).join('、'),
            'albumName': request.song.album?.name ?? '',
            'source': platform,
          },
        },
      },
      cancelToken: cancelToken,
    );
    final url = value['result'];
    if (url is! String || url.length > 8192) {
      throw const LxSourceException('url', VideoStrings.customSourceInvalidUrl);
    }
    return url;
  }

  Map<String, List<String>> _sources(Map<String, dynamic> state) {
    final sources = state['sources'];
    if (sources is! Map) {
      throw const LxSourceException('script', VideoStrings.lxInvalidScript);
    }
    return {
      for (final key in ['tx', 'wy'])
        if (sources[key] is Map &&
            sources[key]['type'] == 'music' &&
            sources[key]['actions'] is List &&
            (sources[key]['actions'] as List).contains('musicUrl') &&
            sources[key]['qualitys'] is List)
          key: (sources[key]['qualitys'] as List)
              .whereType<String>()
              .where(['128k', '320k', 'flac', 'flac24bit'].contains)
              .toList(),
    };
  }

  Future<Map<String, dynamic>> _run(
    String script, {
    Map<String, dynamic>? request,
    CancelToken? cancelToken,
  }) async {
    final id = 'lx-${DateTime.now().microsecondsSinceEpoch}-${++_serial}';
    final networkCancel = CancelToken();
    var finished = false;
    Future<Map<String, dynamic>> execute() async {
      await sandbox.create(id);
      if (finished) return {};
      await sandbox.evaluate(
        id,
        '$lxBootstrap\n;try {\n$script\n} catch (e) { __lxHost.loadError(e); }\n;"loaded";',
      );
      var requested = false;
      var requestCount = 0;
      while (!finished) {
        final state = jsonDecode(
          await sandbox.evaluate(id, '__lxHost.drain()'),
        ) as Map<String, dynamic>;
        if (state['error'] != null) {
          final missing = RegExp(r'^unsupported: ([a-zA-Z0-9_.]+)$')
              .firstMatch(state['error'].toString());
          if (missing != null) {
            throw LxSourceException(
              'script',
              VideoStrings.lxUnsupportedApi(missing.group(1)!),
            );
          }
          throw const LxSourceException('script', VideoStrings.lxScriptFailed);
        }
        if (state['ready'] == true) {
          if (request == null) return state;
          if (!requested) {
            final supported = _sources(state)[request['source']];
            if (!(supported?.contains((request['info'] as Map)['type']) ??
                false)) {
              throw const LxSourceException(
                'quality',
                VideoStrings.customSourceQualityUnsupported,
              );
            }
            await sandbox.evaluate(
              id,
              '__lxHost.resolve(${jsonEncode(request)});"requested";',
            );
            requested = true;
          } else if (state['done'] == true) {
            return state;
          }
        }
        final queue = state['queue'];
        if (queue is List && queue.isNotEmpty) {
          requestCount += queue.length;
          if (queue.length > 4 || requestCount > 32) {
            throw const LxSourceException(
              'script',
              VideoStrings.lxRequestLimit,
            );
          }
          await Future.wait(
            queue.map((item) async {
              if (item is! Map || item['cancel'] == true || finished) return;
              final response = await _http(
                Map<String, dynamic>.from(item),
                networkCancel,
              );
              if (!finished) {
                await sandbox.evaluate(
                  id,
                  '__lxHost.response(${jsonEncode(item['id'])},${jsonEncode(response)});"received";',
                );
              }
            }),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return {};
    }

    try {
      if (cancelToken?.isCancelled == true) {
        throw const LxSourceException(
          'cancelled',
          VideoStrings.customSourceRequestCancelled,
        );
      }
      return await Future.any<Map<String, dynamic>>([
        execute(),
        if (cancelToken != null)
          cancelToken.whenCancel.then(
            (_) => throw const LxSourceException(
              'cancelled',
              VideoStrings.customSourceRequestCancelled,
            ),
          ),
      ]).timeout(timeout);
    } on LxSourceException {
      rethrow;
    } on TimeoutException {
      throw const LxSourceException('timeout', VideoStrings.lxTimedOut);
    } on MissingPluginException {
      throw const LxSourceException(
        'unsupported',
        VideoStrings.lxDeviceUnsupported,
      );
    } on PlatformException catch (e) {
      throw LxSourceException(
        e.code == 'unsupported' ? 'unsupported' : 'script',
        e.code == 'unsupported'
            ? VideoStrings.lxDeviceUnsupported
            : VideoStrings.lxScriptFailed,
      );
    } catch (_) {
      throw const LxSourceException('script', VideoStrings.lxScriptFailed);
    } finally {
      finished = true;
      networkCancel.cancel();
      try {
        await sandbox.close(id);
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>> _http(
    Map<String, dynamic> job,
    CancelToken cancel,
  ) async {
    try {
      final uri = lxImportUri(job['url'] as String);
      final options = job['options'] is Map
          ? Map<String, dynamic>.from(job['options'] as Map)
          : <String, dynamic>{};
      final method = (options['method']?.toString() ?? 'GET').toUpperCase();
      if (!['GET', 'POST', 'HEAD'].contains(method) ||
          options.containsKey('formData')) {
        throw const LxSourceException(
          'network',
          VideoStrings.lxRequestUnsupported,
        );
      }
      final headers = options['headers'] is Map
          ? Map<String, dynamic>.from(options['headers'] as Map)
          : <String, dynamic>{};
      headers.removeWhere(
        (key, _) => [
          'host',
          'cookie',
          'connection',
          'content-length',
        ].contains(key.toLowerCase()),
      );
      final form = options['form'];
      final data = form is Map
          ? form.entries
                .map(
                  (e) =>
                      '${Uri.encodeQueryComponent(e.key.toString())}=${Uri.encodeQueryComponent(e.value.toString())}',
                )
                .join('&')
          : options['body'];
      if (jsonEncode(data).length > 65536) {
        throw const LxSourceException('size', VideoStrings.lxTooLarge);
      }
      final response = await dio.requestUri<ResponseBody>(
        uri,
        data: data,
        cancelToken: cancel,
        onReceiveProgress: (count, _) {
          if (count > 512 * 1024) cancel.cancel();
        },
        options: Options(
          method: method,
          headers: headers,
          contentType: form is Map ? Headers.formUrlEncodedContentType : null,
          responseType: ResponseType.stream,
          followRedirects: false,
          maxRedirects: 0,
          validateStatus: (_) => true,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final raw = await lxReadBody(
        response.data!,
        512 * 1024,
        cancelToken: cancel,
      );
      Object? body = raw;
      try {
        body = jsonDecode(raw);
      } catch (_) {}
      return {
        'statusCode': response.statusCode,
        'headers': response.headers.map.map(
          (key, value) => MapEntry(key, value.join(', ')),
        ),
        'body': body,
        'raw': raw,
      };
    } catch (_) {
      return {'error': 'request failed'};
    }
  }
}
