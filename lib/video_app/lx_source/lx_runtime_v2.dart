import '../../l10n/source_strings.dart';

import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../../models/platform_type.dart';
import '../custom_source/custom_source_models.dart';
import 'lx_bootstrap.dart';
import 'lx_bootstrap_v2.dart';
import 'lx_http.dart';
import 'lx_runtime.dart';
import 'lx_source.dart';

class LxSourceRuntimeV2 implements LxSourceEngine {
  LxSourceRuntimeV2({
    LxSandbox? sandbox,
    Dio? dio,
    this.vendors,
    this.qqInfo,
    this.qqInfoCancellable,
  }) : sandbox = sandbox ?? const MethodChannelLxSandbox(),
       dio = dio ?? createLxDio();
  final LxSandbox sandbox;
  final Dio dio;
  final String? vendors;
  final Future<Map<String, dynamic>> Function(String)? qqInfo;
  final Future<Map<String, dynamic>> Function(String, CancelToken)?
  qqInfoCancellable;
  static Future<String>? _vendorAssets;
  static final _secure = Random.secure();
  Future<String> _assets() => vendors != null
      ? Future.value(vendors!)
      : _vendorAssets ??= Future.wait([
          rootBundle.loadString('assets/lx-runtime/forge-1.3.1.min.js'),
          rootBundle.loadString('assets/lx-runtime/pako-2.1.0.min.js'),
        ]).then((values) => values.join('\n'));

  Future<LxSourceRuntime> _engine(
    String script, {
    Map<String, dynamic>? musicInfo,
    LxSourceConfig? config,
  }) async {
    final info = <String, dynamic>{
      'name': config?.name ?? 'custom',
      'version': config?.version ?? '',
      'description': '',
      'author': '',
      'homepage': '',
    };
    for (final match in RegExp(
      r'@([a-zA-Z]+)\s+([^\r\n]+)',
    ).allMatches(script)) {
      if (info.containsKey(match[1])) {
        info[match[1]!] = match[2]!
            .replaceFirst(RegExp(r'\s*\*/\s*$'), '')
            .trim();
      }
    }
    return LxSourceRuntime(
      dio: dio,
      sandbox: _VersionedSandbox(
        sandbox,
        await _assets(),
        List.generate(65536, (_) => _secure.nextInt(256)),
        info,
        script,
        musicInfo,
      ),
    );
  }

  @override
  Future<Map<String, List<String>>> inspect(
    String script, {
    CancelToken? cancelToken,
  }) async => (await _engine(script)).inspect(script, cancelToken: cancelToken);

  @override
  Future<String> resolve(
    LxSourceConfig config,
    CustomSourceRequest request, {
    CancelToken? cancelToken,
  }) async {
    Map<String, dynamic>? info;
    if (request.platform == PlatformType.qq) {
      info = {'songmid': request.song.id};
      if (qqInfoCancellable != null || qqInfo != null) {
        try {
          info.addAll(
            qqInfoCancellable != null
                ? await qqInfoCancellable!(
                    request.song.id,
                    cancelToken ?? CancelToken(),
                  )
                : await qqInfo!(request.song.id),
          );
        } catch (_) {}
      }
      if (cancelToken?.isCancelled == true) {
        throw const LxSourceException(
          'cancelled',
          SourceStrings.requestCancelled,
        );
      }
    }
    final engine = await _engine(
      config.script,
      musicInfo: info,
      config: config,
    );
    return engine.resolve(config, request, cancelToken: cancelToken);
  }
}

class _VersionedSandbox implements LxSandbox {
  _VersionedSandbox(
    this.delegate,
    this.vendors,
    this.seed,
    this.info,
    this.script,
    this.musicInfo,
  );
  final LxSandbox delegate;
  final String vendors, script;
  final List<int> seed;
  final Map<String, dynamic> info;
  final Map<String, dynamic>? musicInfo;
  bool _resolving = false;
  @override
  Future<void> create(String id) async {
    await delegate.create(id);
    await delegate.evaluate(id, '${lxV2Prelude(vendors, seed)}\n;"prepared";');
    await delegate.evaluate(
      id,
      'globalThis.__lxScriptInfo=${jsonEncode({...info, 'rawScript': ''})};"info";',
    );
    // 分次注入原始脚本信息，单次调用不超过Android插件的2MiB边界。
    for (var offset = 0; offset < script.length; offset += 100000) {
      final end = min(offset + 100000, script.length);
      await delegate.evaluate(
        id,
        '__lxScriptInfo.rawScript+=${jsonEncode(script.substring(offset, end))};"chunk";',
      );
    }
  }

  @override
  Future<String> evaluate(String id, String code) async {
    if (code.startsWith(lxBootstrap)) {
      code = code.replaceFirst(lxBootstrap, lxV2Bootstrap);
    }
    const prefix = '__lxHost.resolve(';
    if (code.startsWith(prefix)) _resolving = true;
    if (musicInfo != null && code.startsWith(prefix)) {
      final request = jsonDecode(
        code.substring(prefix.length, code.indexOf(');')),
      ) as Map<String, dynamic>;
      final info = request['info'] as Map;
      final music = Map<String, dynamic>.from(info['musicInfo'] as Map)
        ..remove('songId');
      music.addAll(musicInfo!);
      info['musicInfo'] = music;
      code = '$prefix${jsonEncode(request)});"requested";';
    }
    final result = await delegate.evaluate(id, code);
    if (code == '__lxHost.drain()') {
      final state = jsonDecode(result) as Map<String, dynamic>;
      final missing = RegExp(
        r'^(?:ReferenceError: )?([a-zA-Z_][a-zA-Z0-9_]*) is not defined$',
      ).firstMatch('${state['error']}');
      if (missing != null) {
        state['error'] = 'unsupported: ${missing[1]}';
        return jsonEncode(state);
      }
      if (_resolving &&
          state['error'] != null &&
          !'${state['error']}'.startsWith('unsupported: ')) {
        throw const LxSourceException('resolve', SourceStrings.resolveFailed);
      }
    }
    return result;
  }

  @override
  Future<void> close(String id) => delegate.close(id);
}
