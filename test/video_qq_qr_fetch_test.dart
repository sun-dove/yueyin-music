import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/features/auth/presentation/pages/login_page.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/video_app/data/video_qq_api.dart';
import 'package:mconnect/video_app/playback/video_platforms.dart';

const _qrError = '暂时无法获取QQ登录二维码，请重试';

void main() {
  test('QQ图片请求被旧API折叠为null时，新API返回通用失败', () async {
    final api = VideoQqApi(dio: _client(_ImageAdapter(null)));
    await expectLater(api.getQrImage(), throwsA(_genericQrError));
  });

  test('QQ图片内容为空时，新API返回通用失败', () async {
    final api = VideoQqApi(dio: _client(_ImageAdapter(const [])));
    await expectLater(api.getQrImage(), throwsA(_genericQrError));
  });

  test('有效QQ二维码bytes及qrsig Cookie保持原样', () async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=',
    );
    final api = VideoQqApi(dio: _client(_ImageAdapter(bytes)))
      ..setCookie('fixture_existing=retained');

    expect(await api.getQrImage(), orderedEquals(bytes));
    expect(api.cookie, 'fixture_existing=retained; qrsig=fixture-qr');
  });

  testWidgets('QQ获取失败显示说明和重试，重复请求期间不启动扫码轮询', (tester) async {
    final adapter = _ImageAdapter(null);
    final api = VideoQqApi(dio: _client(adapter));
    final auth = _QrAuth(VideoQqPlatform(api: api));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith((ref) => auth)],
        child: const MaterialApp(home: LoginPage(platform: PlatformType.qq)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('获取二维码失败: $_qrError'), findsOneWidget);
    expect(find.textContaining('ApiException'), findsNothing);
    expect(find.textContaining('(null)'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, '重试'), findsOneWidget);
    expect(find.byIcon(Icons.qr_code), findsNothing);
    expect(find.text('请使用手机扫描二维码登录'), findsNothing);
    expect(adapter.requests, 1);
    expect(auth.polls, 0);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(adapter.requests, 2);
    expect(auth.polls, 0);
    expect(find.text('获取二维码失败: $_qrError'), findsOneWidget);
    expect(find.textContaining('ApiException'), findsNothing);
    expect(find.textContaining('(null)'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, '重试'), findsOneWidget);
  });
}

final _genericQrError = isA<ApiException>()
    .having((error) => error.message, '通用说明', _qrError)
    .having((error) => error.code, '不臆测网络分类', ApiErrorCode.unknown);

Dio _client(_ImageAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  addTearDown(() => dio.close(force: true));
  return dio;
}

class _ImageAdapter implements HttpClientAdapter {
  _ImageAdapter(this.bytes);
  final List<int>? bytes;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    final image = bytes;
    if (image == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: StateError('fixture unavailable'),
      );
    }
    return ResponseBody.fromBytes(
      image,
      200,
      headers: {
        Headers.contentTypeHeader: ['image/png'],
        'set-cookie': ['qrsig=fixture-qr; Path=/; HttpOnly'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _QrAuth extends AuthNotifier {
  _QrAuth(this.platform);
  final VideoQqPlatform platform;
  int polls = 0;

  @override
  Future<QrLoginResult> getQrCodeWithVariant(
    PlatformType type, {
    String? authVariant,
  }) => platform.getQrCode();

  @override
  Stream<QrLoginStatus> pollQrStatus(
    PlatformType type,
    String key, {
    String? authVariant,
  }) {
    polls++;
    return const Stream.empty();
  }
}
