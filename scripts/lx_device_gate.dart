// 正式设备验收入口；只有显式 --target 本文件时构建，不进入正式应用入口。
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/custom_source/custom_source_models.dart';
import 'package:mconnect/video_app/lx_source/lx_runtime.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/lx_source/lx_http.dart';

const fixture = '''/*!\n * @name Device Fixture\n * @version 1.0\n */
lx.on(lx.EVENT_NAMES.request, ({info}) => new Promise((resolve,reject) => {
  lx.request('https://fixture.example/audio', {method:'GET'}, (error,response) => {
    if(error) reject(error); else resolve(response.body.url + '?song=' + info.musicInfo.songmid);
  });
}));
setTimeout(() => lx.send(lx.EVENT_NAMES.inited, {status:true,sources:{tx:{type:'music',actions:['musicUrl'],qualitys:['128k','320k']}}}), 10);
''';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: GatePage()));
}

class GatePage extends StatefulWidget {
  const GatePage({super.key});
  @override
  State<GatePage> createState() => _GatePageState();
}

class _GatePageState extends State<GatePage> {
  final lines = <String>[];
  void record(String message) {
    // 只输出自造验收状态；不输出脚本正文、响应体或令牌。
    debugPrint('LX_GATE $message');
    if (mounted) setState(() => lines.add(message));
  }

  @override
  void initState() {
    super.initState();
    unawaited(run());
  }

  Future<void> run() async {
    final dio = Dio()..httpClientAdapter = FixtureAdapter();
    final engine = LxSourceRuntime(
      dio: dio,
      timeout: const Duration(seconds: 5),
    );
    try {
      final sources = await engine.inspect(fixture);
      if (sources['tx']?.contains('320k') != true) throw StateError('init');
      record('PASS 初始化与定时器');
      final config = LxSourceConfig(
        name: 'fixture',
        version: '1',
        origin: Uri.parse('https://fixture.example/source.js'),
        script: fixture,
        sha256: 'fixture',
        sources: sources,
      );
      const request = CustomSourceRequest(
        requestId: 'device',
        platform: PlatformType.qq,
        song: Song(
          id: 'device-123',
          platform: PlatformType.qq,
          name: 'fixture',
          artists: [],
        ),
        quality: AudioLevel.high,
        purpose: CustomSourcePurpose.play,
      );
      final url = await engine.resolve(config, request);
      if (url != 'https://media.example/audio.mp3?song=device-123') {
        throw StateError('bridge');
      }
      record('PASS 异步请求桥与歌曲 ID');
      final timeoutEngine = LxSourceRuntime(
        dio: dio,
        timeout: const Duration(seconds: 1),
      );
      try {
        await timeoutEngine.inspect('while (true) {}');
        throw StateError('loop not terminated');
      } on LxSourceException catch (e) {
        if (e.code != 'timeout') rethrow;
      }
      record('PASS 死循环超时终止');
      await engine.inspect(fixture);
      record('PASS 超时后重新运行');
      final cancel = CancelToken();
      final pending = engine.inspect(
        'setTimeout(()=>{},10000);',
        cancelToken: cancel,
      );
      Timer(const Duration(milliseconds: 150), () => cancel.cancel());
      try {
        await pending;
        throw StateError('cancel failed');
      } on LxSourceException catch (e) {
        if (e.code != 'cancelled') {
          rethrow;
        }
      }
      record('PASS 取消独立任务');
      const sandbox = MethodChannelLxSandbox();
      await sandbox.create('privacy-gate');
      try {
        final environment = await sandbox.evaluate(
          'privacy-gate',
          'JSON.stringify([typeof require,typeof fetch,typeof Java,typeof process,typeof document])',
        );
        if (environment !=
            '["undefined","undefined","undefined","undefined","undefined"]') {
          throw StateError('environment');
        }
      } finally {
        await sandbox.close('privacy-gate');
      }
      record('PASS 无文件与原生网络入口');
      record('DETERMINISTIC_ALL_PASS 6');
      final liveDio = createLxDio();
      liveDio.interceptors.add(
        InterceptorsWrapper(
          onResponse: (response, handler) {
            record('LIVE_HTTP ${response.statusCode}');
            handler.next(response);
          },
          onError: (error, handler) {
            record(
              'LIVE_NETWORK ${error.type.name} ${error.error.runtimeType}',
            );
            handler.next(error);
          },
        ),
      );
      try {
        for (final source in [
          'changqing',
          'fish',
          'flower',
          'grass',
          'helloworld',
          'huanyin',
          'huibq',
          'hyw',
          'ikun',
          'jiexiang',
          'juhe',
          'lx',
          'qdy',
          'sixyin',
          'xinghai',
          'yuningxi',
        ]) {
          final link =
              'https://raw.githubusercontent.com/pdone/lx-music-source/main/$source/latest.js';
          try {
            final imported = await LxSourceImporter(
              dio: liveDio,
              engine: LxSourceRuntime(dio: liveDio),
            ).importLink(link);
            record(
              'LIVE_IMPORT_PASS ${Uri.parse(link).host} ${imported.name} ${imported.sha256}',
            );
          } on LxSourceException catch (e) {
            record('LIVE_IMPORT_FAILED $source ${e.code} ${e.message}');
          }
        }
      } finally {
        liveDio.close(force: true);
      }
    } catch (e) {
      record(
        'FAILED ${e is LxSourceException ? '${e.code}: ${e.message}' : e.runtimeType}',
      );
    } finally {
      dio.close(force: true);
      record('FINISHED');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('洛雪运行时设备验收')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Text(lines.join('\n\n')),
    ),
  );
}

class FixtureAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.headers.keys.any((key) => key.toLowerCase() == 'cookie')) {
      throw StateError('Cookie leaked');
    }
    return ResponseBody.fromString(
      '{"url":"https://media.example/audio.mp3"}',
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
