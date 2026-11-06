import '../../l10n/video_strings.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/platform_http.dart';
import '../../core/storage/session_storage.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../models/platform_type.dart';
import '../../models/user.dart';
import '../../platform/base/music_platform.dart';
import '../../platform/base/platform_registry.dart';

/// 视频入口单独保护启动恢复，不改变原 AuthNotifier 的公开行为。
class VideoAuthNotifier extends AuthNotifier {
  VideoAuthNotifier({
    MusicPlatform Function(PlatformType)? platformResolver,
    SessionStorage? sessionStorage,
    this._platforms,
    this._restoreTimeout = const Duration(seconds: 8),
  }) : _platformResolver = platformResolver ?? PlatformRegistry.get,
       _sessionStorage = sessionStorage ?? SessionStorage();

  final MusicPlatform Function(PlatformType) _platformResolver;
  final SessionStorage _sessionStorage;
  final List<PlatformType>? _platforms;
  final Duration _restoreTimeout;
  final _epochs = <PlatformType, int>{};
  Future<void>? _initialization;

  int sessionEpoch(PlatformType platform) => _epochs[platform] ?? 0;

  bool _isCurrent(PlatformType platform, int epoch) =>
      mounted && sessionEpoch(platform) == epoch;

  void _advance(PlatformType platform) =>
      _epochs[platform] = sessionEpoch(platform) + 1;

  @override
  Future<void> init() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    final platforms = List<PlatformType>.of(
      _platforms ?? PlatformRegistry.supportedTypes,
    );
    state = state.copyWith(isLoading: true);
    final requests = [
      for (final platform in platforms)
        _restorePlatform(platform, sessionEpoch(platform)),
    ];
    try {
      await Future.wait(requests).timeout(_restoreTimeout);
    } on TimeoutException {
      // 超时不取消底层请求；每份迟到结果仍须通过对应平台的纪元检查。
      debugPrint(VideoStrings.restoreTimeout);
    } finally {
      if (mounted) state = state.copyWith(isLoading: false);
    }
  }

  Future<void> _restorePlatform(PlatformType platform, int epoch) async {
    try {
      final impl = _platformResolver(platform);
      await impl.restoreSession(_sessionStorage);
      if (!_isCurrent(platform, epoch)) return;
      final user = await impl.getUserInfo();
      _mergeRestoredUser(platform, epoch, user);
    } catch (error) {
      if (!_isCurrent(platform, epoch)) return;
      if (apiExceptionOf(error) is LoginExpiredException) {
        await _sessionStorage.deleteCookie(platform);
        if (!_isCurrent(platform, epoch)) return;
        await _sessionStorage.deleteUser(platform);
      }
      _mergeRestoredUser(platform, epoch, null);
    }
  }

  void _mergeRestoredUser(PlatformType platform, int epoch, User? user) {
    if (!_isCurrent(platform, epoch)) return;
    state = state.copyWith(loggedUsers: {...state.loggedUsers, platform: user});
  }

  @override
  Future<User?> onQrLoginSuccess(PlatformType platform) {
    _advance(platform);
    return super.onQrLoginSuccess(platform);
  }

  @override
  Future<void> logout(PlatformType platform) {
    _advance(platform);
    return super.logout(platform);
  }

  @override
  Future<void> handleSessionExpired(PlatformType platform) {
    _advance(platform);
    return super.handleSessionExpired(platform);
  }

  /// 调用方在发起请求时捕获纪元，才能拒绝旧会话的迟到 401。
  ///
  /// 旧全局 SessionExpiryReporter 只携带平台，无法判断请求属于哪次登录；
  /// 在收到错误时才读取当前纪元，不能补出这个丢失的信息。
  Future<void> handleSessionExpiredIfCurrent(
    PlatformType platform, {
    required int epoch,
  }) async {
    if (!_isCurrent(platform, epoch) || !state.isLoggedIn(platform)) return;
    await handleSessionExpired(platform);
  }
}
