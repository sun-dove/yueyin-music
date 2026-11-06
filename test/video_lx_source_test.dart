import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:mconnect/video_app/lx_source/lx_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/custom_source/custom_source_models.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/lx_source/lx_runtime.dart';
import 'package:mconnect/video_app/lx_source/lx_http.dart';

const script = '''/*!\n * @name 验收音源\n * @version 1.0\n */
lx.on(lx.EVENT_NAMES.request, () => Promise.resolve('https://media.example/song.mp3'));
lx.send(lx.EVENT_NAMES.inited, {status:true, sources:{tx:{type:'music', actions:['musicUrl'], qualitys:['128k','320k']}}});''';

void main() {
  test('脚本网络禁止本机、内网、链路本地与 IPv6 映射地址', () {
    for (final ip in [
      '127.0.0.1',
      '10.0.0.1',
      '172.16.0.1',
      '192.168.1.1',
      '169.254.169.254',
      '100.64.0.1',
      '::1',
      'fe80::1',
      'fc00::1',
      '::ffff:127.0.0.1',
    ]) {
      expect(lxPublicAddress(InternetAddress(ip)), isFalse, reason: ip);
    }
    expect(lxPublicAddress(InternetAddress('8.8.8.8')), isTrue);
    expect(lxPublicAddress(InternetAddress('2606:4700:4700::1111')), isTrue);
  });
  test('GitHub 文件链接转 raw，仓库首页和带凭据链接明确拒绝', () {
    expect(
      lxImportUri('https://github.com/a/b/blob/main/source.js').toString(),
      'https://raw.githubusercontent.com/a/b/main/source.js',
    );
    for (final value in [
      'https://github.com/a/b',
      'http://source.example/a.js',
      'https://a:b@source.example/a.js',
      'not-a-url',
    ]) {
      expect(() => lxImportUri(value), throwsA(isA<LxSourceException>()));
    }
  });

  test('链接导入下载后初始化，保存元数据和摘要但默认关闭', () async {
    final engine = FakeEngine();
    final dio = Dio()
      ..httpClientAdapter = Adapter((o) {
        expect(o.followRedirects, isFalse);
        expect(o.headers.containsKey('Cookie'), isFalse);
        return ResponseBody.fromString(script, 200);
      });
    addTearDown(() => dio.close(force: true));
    final value = await LxSourceImporter(
      dio: dio,
      engine: engine,
    ).importLink('https://source.example/source.js');
    expect(value.name, '验收音源');
    expect(value.version, '1.0');
    expect(value.script, script);
    expect(value.sha256, hasLength(64));
    expect(value.enabled, isFalse);
    expect(value.allowForDownloads, isFalse);
    expect(value.sources['tx'], ['128k', '320k']);
    expect(engine.inspections, 1);
    final restored = LxSourceConfig.fromJson(value.toJson());
    expect(restored.script, script);
    expect(restored.origin, value.origin);
    expect(restored.enabled, isFalse);
  });

  test('GitHub Raw 直连失败时自动尝试同文件备用线路并保留原链接', () async {
    final requests = <Uri>[];
    final engine = FakeEngine();
    final dio = Dio()
      ..httpClientAdapter = Adapter((options) {
        requests.add(options.uri);
        if (options.uri.host == 'raw.githubusercontent.com') {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: const SocketException('连接被重置'),
          );
        }
        return ResponseBody.fromString(script, 200);
      });
    addTearDown(() => dio.close(force: true));
    final original = Uri.parse(
      'https://raw.githubusercontent.com/pdone/lx-music-source/main/lx/latest.js',
    );

    final value = await LxSourceImporter(
      dio: dio,
      engine: engine,
    ).importLink(original.toString());

    expect(requests, [
      original,
      Uri.parse(
        'https://fastly.jsdelivr.net/gh/pdone/lx-music-source@main/lx/latest.js',
      ),
    ]);
    expect(value.origin, original);
    expect(value.name, '验收音源');
    expect(engine.inspections, 1);
  });

  test('HTML、空文件、无声明脚本不能提示导入成功', () async {
    for (final body in [
      '',
      '<!DOCTYPE html><html>404</html>',
      'console.log("hello")',
    ]) {
      final engine = FakeEngine();
      final dio = Dio()
        ..httpClientAdapter = Adapter(
          (_) => ResponseBody.fromString(body, 200),
        );
      addTearDown(() => dio.close(force: true));
      await expectLater(
        LxSourceImporter(
          dio: dio,
          engine: engine,
        ).importLink('https://source.example/a.js'),
        throwsA(isA<LxSourceException>()),
      );
      expect(engine.inspections, 0);
    }
  });

  test('导入下载超过 1 MiB 立即停止，不交给脚本引擎', () async {
    var emitted = 0;
    final engine = FakeEngine();
    final dio = Dio()
      ..httpClientAdapter = Adapter(
        (_) => ResponseBody(() async* {
          for (var i = 0; i < 4096; i++) {
            emitted++;
            yield Uint8List(4096);
          }
        }(), 200),
      );
    addTearDown(() => dio.close(force: true));
    await expectLater(
      LxSourceImporter(
        dio: dio,
        engine: engine,
      ).importLink('https://source.example/a.js'),
      throwsA(isA<LxSourceException>()),
    );
    expect(emitted, lessThan(4096));
    expect(engine.inspections, 0);
  });

  test('非成功状态和重定向不会执行响应体', () async {
    for (final status in [301, 401, 403, 404, 429, 500]) {
      final engine = FakeEngine();
      final dio = Dio()
        ..httpClientAdapter = Adapter(
          (_) => ResponseBody.fromString(script, status),
        );
      addTearDown(() => dio.close(force: true));
      await expectLater(
        LxSourceImporter(
          dio: dio,
          engine: engine,
        ).importLink('https://source.example/a.js'),
        throwsA(isA<LxSourceException>()),
      );
      expect(engine.inspections, 0);
    }
  });

  test('初始化失败或没有 QQ/网易云能力时导入失败', () async {
    for (final engine in [
      FakeEngine(fail: true),
      FakeEngine(sources: {'tx': []}),
      FakeEngine(
        sources: {
          'kw': ['128k'],
        },
      ),
    ]) {
      final dio = Dio()
        ..httpClientAdapter = Adapter(
          (_) => ResponseBody.fromString(script, 200),
        );
      addTearDown(() => dio.close(force: true));
      await expectLater(
        LxSourceImporter(
          dio: dio,
          engine: engine,
        ).importLink('https://source.example/a.js'),
        throwsA(isA<LxSourceException>()),
      );
    }
  });

  test('QQ 与网易云档位明确映射，不支持的空间音频拒绝', () {
    expect(lxPlatform(PlatformType.qq), 'tx');
    expect(lxPlatform(PlatformType.netease), 'wy');
    expect(lxQuality(AudioLevel.low), '128k');
    expect(lxQuality(AudioLevel.high), '320k');
    expect(lxQuality(AudioLevel.lossless), 'flac');
    expect(lxQuality(AudioLevel.hires), 'flac24bit');
    expect(
      () => lxQuality(AudioLevel.spatial),
      throwsA(isA<LxSourceException>()),
    );
  });

  test('沙箱初始化读取声明，成功或异常均关闭独立实例', () async {
    final sandbox = FakeSandbox();
    final runtime = LxSourceRuntime(sandbox: sandbox);
    final sources = await runtime.inspect(script);
    expect(sources['tx'], ['128k', '320k']);
    expect(sandbox.closed, 1);
    sandbox.fail = true;
    await expectLater(
      runtime.inspect(script),
      throwsA(isA<LxSourceException>()),
    );
    expect(sandbox.closed, 2);
  });

  test('沙箱超时或取消终止，不能停留在等待状态', () async {
    final sandbox = FakeSandbox()..hang = true;
    final runtime = LxSourceRuntime(
      sandbox: sandbox,
      timeout: const Duration(milliseconds: 40),
    );
    await expectLater(
      runtime.inspect(script),
      throwsA(isA<LxSourceException>()),
    );
    expect(sandbox.closed, 1);
    final cancel = CancelToken();
    final operation = runtime.inspect(script, cancelToken: cancel);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    cancel.cancel();
    await expectLater(operation, throwsA(isA<LxSourceException>()));
    expect(sandbox.closed, 2);
  });

  test('解析把歌曲字段映射到洛雪请求且不包含会话', () async {
    final sandbox = FakeSandbox();
    final runtime = LxSourceRuntime(sandbox: sandbox);
    final config = fixtureConfig();
    final result = await runtime.resolve(config, request());
    expect(result, 'https://media.example/song.mp3');
    final code = sandbox.codes.join('\n');
    expect(code, contains('songmid'));
    expect(code, contains('song-123'));
    expect(code, contains('musicUrl'));
    expect(sandbox.closed, 1);
  });

  test('缺少洛雪接口时返回明确接口名并关闭沙箱', () async {
    final sandbox = FakeSandbox()
      ..initialError = 'unsupported: utils.crypto.md5';
    final runtime = LxSourceRuntime(sandbox: sandbox);
    await expectLater(
      runtime.inspect(script),
      throwsA(
        isA<LxSourceException>().having(
          (e) => e.message,
          'message',
          '此脚本需要尚不支持的接口：utils.crypto.md5',
        ),
      ),
    );
    expect(sandbox.closed, 1);
  });

  test('沙箱提供 UTF8、Base64 与洛雪 buffer 纯计算兼容层', () {
    expect(lxBootstrap, contains("globalThis.btoa"));
    expect(lxBootstrap, contains("globalThis.atob"));
    expect(lxBootstrap, contains("globalThis.TextEncoder"));
    expect(lxBootstrap, contains("buffer: Object.freeze"));
    expect(lxBootstrap, contains("bufToString"));
  });

  test('网络回调第三参数与洛雪桌面契约一致，使用解析后的 body', () {
    expect(
      lxBootstrap,
      contains(
        'callback(response.error ? Error(response.error) : null, response.error ? null : response, response.body)',
      ),
    );
    expect(lxBootstrap, isNot(contains('response.raw);} catch')));
  });

  test('脚本同步异常通过 loadError 进入可读错误状态', () {
    expect(lxBootstrap, contains('loadError(value) { fail(value); }'));
  });
}

LxSourceConfig fixtureConfig() => LxSourceConfig(
  name: '验收音源',
  version: '1.0',
  origin: Uri.parse('https://source.example/a.js'),
  script: script,
  sha256: 'fixture',
  sources: const {
    'tx': ['128k', '320k'],
  },
);
CustomSourceRequest request() => const CustomSourceRequest(
  requestId: 'play-1',
  platform: PlatformType.qq,
  song: Song(
    id: 'song-123',
    name: '歌曲',
    platform: PlatformType.qq,
    artists: [],
  ),
  quality: AudioLevel.high,
  purpose: CustomSourcePurpose.play,
);

class FakeEngine implements LxSourceEngine {
  FakeEngine({
    this.fail = false,
    this.sources = const {
      'tx': ['128k', '320k'],
    },
  });
  final bool fail;
  final Map<String, List<String>> sources;
  int inspections = 0;
  @override
  Future<Map<String, List<String>>> inspect(
    String script, {
    CancelToken? cancelToken,
  }) async {
    inspections++;
    if (fail) throw const LxSourceException('runtime', '初始化失败');
    return sources;
  }

  @override
  Future<String> resolve(
    LxSourceConfig config,
    CustomSourceRequest request, {
    CancelToken? cancelToken,
  }) async => 'https://media.example/song.mp3';
}

class FakeSandbox implements LxSandbox {
  String? initialError;
  bool fail = false;
  bool hang = false;
  int closed = 0;
  final codes = <String>[];
  @override
  Future<void> create(String id) async {}
  @override
  Future<String> evaluate(String id, String code) async {
    codes.add(code);
    if (hang) return Completer<String>().future;
    if (fail) throw StateError('script error');
    if (code.contains('__lxHost.drain')) {
      return jsonEncode({
        if (initialError != null) 'error': initialError,
        'ready': true,
        'sources': {
          'tx': {
            'type': 'music',
            'actions': ['musicUrl'],
            'qualitys': ['128k', '320k'],
          },
        },
        'queue': [],
        'done': true,
        'result': 'https://media.example/song.mp3',
      });
    }
    return '';
  }

  @override
  Future<void> close(String id) async => closed++;
}

class Adapter implements HttpClientAdapter {
  Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);
  @override
  void close({bool force = false}) {}
}
