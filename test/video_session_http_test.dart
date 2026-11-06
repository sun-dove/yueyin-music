import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/core/network/platform_http.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/platform/base/platform_registry.dart';
import 'package:mconnect/video_app/data/video_auth_notifier.dart';
import 'package:mconnect/video_app/data/video_session_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _AuthPlatform platform;
  late VideoAuthNotifier auth;
  late List<PlatformType> legacyNotices;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    platform = _AuthPlatform();
    PlatformRegistry.register(platform);
    auth = VideoAuthNotifier(platforms: const []);
    legacyNotices = [];
    SessionExpiryReporter.handler = legacyNotices.add;
  });
  tearDown(() {
    auth.dispose();
    SessionExpiryReporter.reset();
  });

  Future<void> login(String id) async {
    platform.id = id;
    await auth.onQrLoginSuccess(PlatformType.qq);
  }

  Dio client(_Adapter adapter, {int retries = 0}) {
    final dio = createPlatformDio(
      platform: PlatformType.qq,
      label: 'QQ音乐',
      baseUrl: 'https://example.invalid',
      maxRetries: retries,
      retryBaseDelay: Duration.zero,
      retryMaxDelay: Duration.zero,
    )..httpClientAdapter = adapter;
    attachVideoSessionGuard(dio, PlatformType.qq, auth);
    addTearDown(() => dio.close(force: true));
    return dio;
  }

  test('旧下载请求迟到401不能注销重新登录的新账号', () async {
    await login('old');
    final response = Completer<ResponseBody>();
    final adapter = _Adapter((_, _) => response.future);
    final dio = client(adapter);
    final result = _capture(dio.get('/download-url'));
    await adapter.started.future;
    await login('new');
    response.complete(_json(401));

    expect((await result).error, isA<LoginExpiredException>());
    expect(auth.state.userFor(PlatformType.qq)?.id, 'new');
    expect(auth.state.expiryNoticeId, 0);
    expect(legacyNotices, isEmpty);
  });

  test('当前会话401清理账号且只通知一次，保留类型化错误', () async {
    await login('current');
    final dio = client(_Adapter((_, _) => _json(401)));
    final error = await _capture(dio.get('/download-url'));

    expect(auth.state.isLoggedIn(PlatformType.qq), isFalse);
    expect(auth.state.expiredPlatform, PlatformType.qq);
    expect(auth.state.expiryNoticeId, 1);
    expect(error.error, isA<LoginExpiredException>());
    expect(error.type, DioExceptionType.badResponse);
    expect(error.response?.statusCode, 401);
    expect(legacyNotices, isEmpty);
  });

  test('匿名401不通知失效，也不调用旧全局处理器', () async {
    final dio = client(_Adapter((_, _) => _json(401)));
    expect(
      (await _capture(dio.get('/public'))).error,
      isA<LoginExpiredException>(),
    );
    expect(auth.state.expiryNoticeId, 0);
    expect(legacyNotices, isEmpty);
  });

  test('匿名请求在用户登录后才返回401也不能注销新会话', () async {
    final response = Completer<ResponseBody>();
    final adapter = _Adapter((_, _) => response.future);
    final dio = client(adapter);
    final result = _capture(dio.get('/public'));
    await adapter.started.future;
    await login('new');
    response.complete(_json(401));
    await result;
    expect(auth.state.userFor(PlatformType.qq)?.id, 'new');
    expect(auth.state.expiryNoticeId, 0);
  });

  test('403沿用平台原有失效语义', () async {
    await login('current');
    final dio = client(_Adapter((_, _) => _json(403)));
    expect(
      (await _capture(dio.get('/private'))).error,
      isA<LoginExpiredException>(),
    );
    expect(auth.state.expiryNoticeId, 1);
  });

  test('普通网络错误仍为NetworkException，不误判会话过期', () async {
    await login('current');
    final dio = client(
      _Adapter(
        (options, _) => throw DioException.connectionError(
          requestOptions: options,
          reason: 'scripted network failure',
        ),
      ),
    );
    expect((await _capture(dio.get('/x'))).error, isA<NetworkException>());
    expect(auth.state.isLoggedIn(PlatformType.qq), isTrue);
    expect(auth.state.expiryNoticeId, 0);
  });

  test('旧请求重试后401仍沿用首次请求纪元，不误用新登录纪元', () async {
    await login('old');
    final firstResponse = Completer<ResponseBody>();
    final adapter = _Adapter(
      (_, attempt) => attempt == 1 ? firstResponse.future : _json(401),
    );
    final dio = client(adapter, retries: 1);
    final result = _capture(dio.get('/download-url'));
    await adapter.started.future;
    await login('new');
    firstResponse.complete(_json(500));
    await result;

    expect(adapter.attempts, 2);
    expect(auth.state.userFor(PlatformType.qq)?.id, 'new');
    expect(auth.state.expiryNoticeId, 0);
    expect(legacyNotices, isEmpty);
  });

  test('保留原重试实例、自定义拦截器、标签与网络配置', () {
    final marker = InterceptorsWrapper();
    final dio = createPlatformDio(
      platform: PlatformType.qq,
      label: '自定义QQ标签',
      baseUrl: 'https://example.invalid',
      headers: {'X-Probe': 'preserved'},
      connectTimeout: const Duration(seconds: 4),
      interceptors: [marker],
    );
    addTearDown(() => dio.close(force: true));
    final retry = dio.interceptors.whereType<IdempotentRetryGuard>().single;
    attachVideoSessionGuard(dio, PlatformType.qq, auth);
    expect(dio.interceptors, contains(same(retry)));
    expect(dio.interceptors, contains(same(marker)));
    final translator = dio.interceptors
        .whereType<PlatformErrorInterceptor>()
        .single;
    expect(translator.label, '自定义QQ标签');
    expect(translator.platform, PlatformType.qq);
    expect(dio.options.baseUrl, 'https://example.invalid');
    expect(dio.options.connectTimeout, const Duration(seconds: 4));
    expect(dio.options.headers['X-Probe'], 'preserved');
  });

  test('新入口装配不会改变未装配的旧客户端行为', () async {
    final old = createPlatformDio(
      platform: PlatformType.qq,
      maxRetries: 0,
      baseUrl: 'https://example.invalid',
    )..httpClientAdapter = _Adapter((_, _) => _json(401));
    addTearDown(() => old.close(force: true));
    client(_Adapter((_, _) => _json(200)));
    await _capture(old.get('/legacy'));
    expect(legacyNotices, [PlatformType.qq]);
  });
}

Future<DioException> _capture(Future<Response<dynamic>> request) async {
  try {
    await request;
  } on DioException catch (error) {
    return error;
  }
  fail('应返回 DioException');
}

ResponseBody _json(int code) => ResponseBody.fromString(
  '{}',
  code,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions, int) respond;
  final started = Completer<void>();
  int attempts = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!started.isCompleted) started.complete();
    return respond(options, ++attempts);
  }

  @override
  void close({bool force = false}) {}
}

class _AuthPlatform extends MusicPlatform {
  String id = 'user';
  @override
  PlatformType get platformType => PlatformType.qq;
  @override
  String get platformName => 'QQ音乐';
  @override
  bool get isLoggedIn => true;
  @override
  Future<User?> getUserInfo() async =>
      User(id: id, nickname: id, platform: platformType);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
