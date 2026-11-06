import 'package:dio/dio.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/platform_http.dart';
import '../../models/platform_type.dart';
import 'video_auth_notifier.dart';

/// 只给视频入口创建的客户端装配；旧客户端与全局处理器保持原行为。
void attachVideoSessionGuard(
  Dio dio,
  PlatformType platform,
  VideoAuthNotifier auth,
) {
  if (dio.interceptors.any(
    (interceptor) =>
        interceptor is _VideoSessionGuard &&
        interceptor.platform == platform &&
        identical(interceptor.auth, auth),
  )) {
    return;
  }
  for (var index = 0; index < dio.interceptors.length; index++) {
    final interceptor = dio.interceptors[index];
    if (interceptor is PlatformErrorInterceptor) {
      // 保留原错误翻译，只替换缺少请求纪元的全局失效广播。
      dio.interceptors[index] = PlatformErrorInterceptor(
        label: interceptor.label,
        platform: interceptor.platform,
        onSessionExpired: (_) {},
      );
    }
  }
  dio.interceptors.add(_VideoSessionGuard(platform, auth));
}

class _VideoSessionGuard extends Interceptor {
  _VideoSessionGuard(this.platform, this.auth);

  final PlatformType platform;
  final VideoAuthNotifier auth;
  String get _epochKey => 'video.sessionEpoch.${platform.name}';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Dio 重试会再次运行 onRequest，必须沿用最初那次发送所属的会话。
    options.extra.putIfAbsent(_epochKey, () => auth.sessionEpoch(platform));
    handler.next(options);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) async {
    final epoch = error.requestOptions.extra[_epochKey];
    if (epoch is int && apiExceptionOf(error) is LoginExpiredException) {
      await auth.handleSessionExpiredIfCurrent(platform, epoch: epoch);
    }
    handler.next(error);
  }
}
