import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/features/auth/presentation/pages/login_page.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/core/storage/session_storage.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/platform/base/platform_registry.dart';
import 'package:mconnect/video_app/data/video_auth_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('凭据确认之前不显示登录成功，空用户显示重试并留在登录页', (tester) async {
    final notifier = _LoginUiNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(home: LoginPage(platform: PlatformType.qq)),
      ),
    );
    await tester.pumpAndSettle();
    notifier.statuses.add(QrLoginStatus.success);
    await tester.pump();
    await tester.pump();
    expect(find.text('登录成功'), findsNothing);
    notifier.user.complete(null);
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('登录凭据不完整，请重新扫码'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('登录成功'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(notifier.qrRequests, 2);
  });

  test('启动恢复迟到时不能覆盖新扫码登录的账号', () async {
    final old = Completer<User?>();
    final platform = _AuthPlatform(PlatformType.qq, [
      old.future,
      Future.value(_user('new')),
    ]);
    PlatformRegistry.register(platform);
    final notifier = _notifier([platform]);
    addTearDown(notifier.dispose);
    final initializing = notifier.init();
    await platform.userReadStarted.future;

    await notifier.onQrLoginSuccess(PlatformType.qq);
    old.complete(_user('old'));
    await initializing;

    expect(notifier.state.userFor(PlatformType.qq)?.id, 'new');
    expect(platform.restoreCalls, 1);
  });

  test('退出后迟到的启动恢复不能重新登录', () async {
    final old = Completer<User?>();
    final platform = _AuthPlatform(PlatformType.qq, [old.future]);
    PlatformRegistry.register(platform);
    final notifier = _notifier([platform]);
    addTearDown(notifier.dispose);
    final initializing = notifier.init();
    await platform.userReadStarted.future;

    await notifier.logout(PlatformType.qq);
    old.complete(_user('old'));
    await initializing;

    expect(notifier.state.isLoggedIn(PlatformType.qq), isFalse);
    expect(platform.logoutCalls, 1);
  });

  test('过期处理后迟到的启动恢复不能恢复失效账号', () async {
    final old = Completer<User?>();
    final platform = _AuthPlatform(PlatformType.qq, [old.future]);
    PlatformRegistry.register(platform);
    final notifier = _notifier([platform]);
    addTearDown(notifier.dispose);
    final initializing = notifier.init();
    await platform.userReadStarted.future;

    await notifier.handleSessionExpired(PlatformType.qq);
    old.complete(_user('old'));
    await initializing;

    expect(notifier.state.isLoggedIn(PlatformType.qq), isFalse);
    expect(notifier.state.expiryNoticeId, 1);
  });

  test('不同平台的恢复独立合并，不覆盖另一平台的新账号', () async {
    final old = Completer<User?>();
    final qq = _AuthPlatform(PlatformType.qq, [
      old.future,
      Future.value(_user('new')),
    ]);
    final netease = _AuthPlatform(PlatformType.netease, [
      Future.value(_user('netease', PlatformType.netease)),
    ]);
    PlatformRegistry.register(qq);
    PlatformRegistry.register(netease);
    final notifier = _notifier([qq, netease]);
    addTearDown(notifier.dispose);
    final initializing = notifier.init();
    await qq.userReadStarted.future;
    await netease.userReadStarted.future;

    await notifier.onQrLoginSuccess(PlatformType.qq);
    old.complete(_user('old'));
    await initializing;

    expect(notifier.state.userFor(PlatformType.qq)?.id, 'new');
    expect(notifier.state.userFor(PlatformType.netease)?.id, 'netease');
  });

  test('恢复超时返回后，迟到结果仍不能覆盖新登录', () async {
    final old = Completer<User?>();
    final platform = _AuthPlatform(PlatformType.qq, [
      old.future,
      Future.value(_user('new')),
    ]);
    PlatformRegistry.register(platform);
    final notifier = _notifier([
      platform,
    ], timeout: const Duration(milliseconds: 2));
    addTearDown(notifier.dispose);
    final initializing = notifier.init();
    await platform.userReadStarted.future;
    await initializing;

    await notifier.onQrLoginSuccess(PlatformType.qq);
    old.complete(_user('old'));
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.userFor(PlatformType.qq)?.id, 'new');
  });

  test('旧恢复请求的失效错误不能删除新登录凭据', () async {
    final old = Completer<User?>();
    final storage = _MemorySessionStorage();
    final platform = _AuthPlatform(PlatformType.qq, [
      old.future,
      Future.value(_user('new')),
    ]);
    PlatformRegistry.register(platform);
    final notifier = _notifier([platform], storage: storage);
    addTearDown(notifier.dispose);
    final initializing = notifier.init();
    await platform.userReadStarted.future;

    await notifier.onQrLoginSuccess(PlatformType.qq);
    old.completeError(LoginExpiredException());
    await initializing;

    expect(notifier.state.userFor(PlatformType.qq)?.id, 'new');
    expect(storage.deletedPlatforms, isEmpty);
  });

  test('有请求纪元的旧401忽略，当前401可清理当前会话', () async {
    final platform = _AuthPlatform(PlatformType.qq, [
      Future.value(_user('new')),
    ]);
    PlatformRegistry.register(platform);
    final notifier = _notifier([platform]);
    addTearDown(notifier.dispose);
    final oldEpoch = notifier.sessionEpoch(PlatformType.qq);
    await notifier.onQrLoginSuccess(PlatformType.qq);
    await notifier.handleSessionExpiredIfCurrent(
      PlatformType.qq,
      epoch: oldEpoch,
    );
    expect(notifier.state.isLoggedIn(PlatformType.qq), isTrue);

    await notifier.handleSessionExpiredIfCurrent(
      PlatformType.qq,
      epoch: notifier.sessionEpoch(PlatformType.qq),
    );
    expect(notifier.state.isLoggedIn(PlatformType.qq), isFalse);
    expect(notifier.state.expiryNoticeId, 1);
  });

  test('销毁后恢复完成不会写入已销毁的状态', () async {
    final old = Completer<User?>();
    final platform = _AuthPlatform(PlatformType.qq, [old.future]);
    final notifier = _notifier([platform]);
    final initializing = notifier.init();
    await platform.userReadStarted.future;
    notifier.dispose();
    old.complete(_user('old'));
    await expectLater(initializing, completes);
  });

  test('重复初始化不会发起第二轮恢复', () async {
    final old = Completer<User?>();
    final platform = _AuthPlatform(PlatformType.qq, [old.future]);
    final notifier = _notifier([platform]);
    addTearDown(notifier.dispose);
    final first = notifier.init();
    final second = notifier.init();
    await platform.userReadStarted.future;
    old.complete(_user('old'));
    await Future.wait([first, second]);
    expect(platform.restoreCalls, 1);
  });
}

VideoAuthNotifier _notifier(
  List<_AuthPlatform> platforms, {
  _MemorySessionStorage? storage,
  Duration timeout = const Duration(seconds: 8),
}) {
  final byType = {
    for (final platform in platforms) platform.platformType: platform,
  };
  return VideoAuthNotifier(
    platformResolver: (type) => byType[type]!,
    sessionStorage: storage ?? _MemorySessionStorage(),
    platforms: byType.keys.toList(),
    restoreTimeout: timeout,
  );
}

User _user(String id, [PlatformType type = PlatformType.qq]) =>
    User(id: id, nickname: id, platform: type);

class _AuthPlatform extends MusicPlatform {
  _AuthPlatform(this.platformType, this.responses);
  @override
  final PlatformType platformType;
  final List<Future<User?>> responses;
  final userReadStarted = Completer<void>();
  int restoreCalls = 0;
  int logoutCalls = 0;
  int _userCalls = 0;
  User? _current;
  @override
  String get platformName => platformType.name;
  @override
  bool get isLoggedIn => _current != null;
  @override
  Future<User?> getUserInfo() async {
    if (!userReadStarted.isCompleted) userReadStarted.complete();
    return _current = await responses[_userCalls++];
  }

  @override
  Future<void> restoreSession(SessionStorage storage) async {
    restoreCalls++;
    await storage.loadCookie(platformType);
  }

  @override
  Future<void> saveSession(SessionStorage storage) async {
    await storage.saveCookie(platformType, 'fake-${_current?.id}');
    if (_current case final user?) await storage.saveUser(platformType, user);
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    _current = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemorySessionStorage extends SessionStorage {
  final deletedPlatforms = <PlatformType>[];
  @override
  Future<String?> loadCookie(PlatformType platform) async => null;
  @override
  Future<void> deleteCookie(PlatformType platform) async =>
      deletedPlatforms.add(platform);
  @override
  Future<void> deleteUser(PlatformType platform) async =>
      deletedPlatforms.add(platform);
}

class _LoginUiNotifier extends AuthNotifier {
  final statuses = StreamController<QrLoginStatus>.broadcast();
  final user = Completer<User?>();
  int qrRequests = 0;

  @override
  Future<QrLoginResult> getQrCodeWithVariant(
    PlatformType platform, {
    String? authVariant,
  }) async {
    qrRequests++;
    return const QrLoginResult(
      key: 'fixture',
      qrUrl: 'https://fixture.example/qr',
    );
  }

  @override
  Stream<QrLoginStatus> pollQrStatus(
    PlatformType platform,
    String key, {
    String? authVariant,
  }) => statuses.stream;

  @override
  Future<User?> onQrLoginSuccess(PlatformType platform) => user.future;

  @override
  void dispose() {
    unawaited(statuses.close());
    super.dispose();
  }
}
