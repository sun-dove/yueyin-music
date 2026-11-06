import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/platform/qq/qq_api.dart';
import 'package:mconnect/video_app/data/video_qq_api.dart';
import 'package:mconnect/video_app/playback/video_platforms.dart';

void main() {
  for (final entry in {
    '66': QrLoginStatus.waiting,
    '67': QrLoginStatus.scanned,
  }.entries) {
    test('真实协议${entry.key}经新平台和API后为${entry.value.name}', () async {
      final api = _api(_callback(entry.key));
      final platform = VideoQqPlatform(api: api);

      expect(await platform.pollQrStatus('fixture-qr').first, entry.value);
      expect(api.cookie, 'qrsig=fixture-qr');
      expect(api.oauthRedirect, isNull);
    });
  }

  test('成功0保留回调、重定向和Cookie，并沿原OAuth流程完成登录', () async {
    const redirect = 'https://example.invalid/check_sig?fixture=66';
    final raw = _callback('0', redirect: redirect);
    final api = _api(raw);
    final result = await api.checkQr();
    expect(result['raw'], raw);
    expect(result['cookies'], _pollCookies);

    final platform = VideoQqPlatform(api: api);
    expect(
      await platform.pollQrStatus('fixture-qr').first,
      QrLoginStatus.success,
    );
    expect(api.oauthRedirect, redirect);
    expect(api.cookiesBeforeOAuth, _pollCookies);
    expect(api.cookie, contains('qqmusic_uin=10001'));
    expect(api.cookie, contains('qm_keyst=music-key'));
    expect(api.cookie, contains('qqmusic_encrypt_uin=encrypted-uin'));
    expect(platform.isLoggedIn, isTrue);
    expect((await platform.getUserInfo())?.id, '10001');
  });

  for (final entry in {
    '65': QrLoginStatus.expired,
    '68': QrLoginStatus.waiting,
  }.entries) {
    test('${entry.key}及其Cookie保持不变，仍走原平台状态', () async {
      final raw = _callback(entry.key);
      final api = _api(raw);
      final result = await api.checkQr();
      expect(result['raw'], raw);
      expect(result['cookies'], _pollCookies);

      expect(
        await VideoQqPlatform(api: api).pollQrStatus('fixture-qr').first,
        entry.value,
      );
      expect(api.cookie, 'qrsig=fixture-qr');
      expect(api.oauthRedirect, isNull);
    });
  }

  for (final entry in {'66': '67', '67': '66'}.entries) {
    test('${entry.key}只翻译首个状态码，回调其他字段及Cookie原样保留', () async {
      final raw =
          "ptuiCB('${entry.key}','66','https://example.invalid/67','67','66/67','')";
      final result = await _api(raw).checkQr();
      expect(
        result['raw'],
        "ptuiCB('${entry.value}','66','https://example.invalid/67','67','66/67','')",
      );
      expect(result['cookies'], _pollCookies);
    });
  }

  test('本次凭据兑换失败时不能沿用旧账号令牌报告成功', () async {
    final api =
        _FailedApi(
          dio: _client(
            _callback(
              '0',
              redirect: 'https://ssl.ptlogin2.graph.qq.com/check_sig?fixture=1',
            ),
          ),
        )..setCookie(
          'qqmusic_uin=99999; qm_keyst=old-key; qqmusic_encrypt_uin=old-encrypted',
        );
    expect(
      await VideoQqPlatform(api: api).pollQrStatus('fixture').first,
      QrLoginStatus.failed,
    );
  });

  test('未接入新适配器的旧API仍返回原始66和67', () async {
    for (final code in ['66', '67']) {
      final raw = _callback(code);
      final dio = _client(raw);
      final api = QqApi(dio: dio)..setCookie('qrsig=fixture-qr');
      final result = await api.checkQr();
      expect(result['raw'], raw);
      expect(result['cookies'], _pollCookies);
    }
  });
}

const _pollCookies = 'qrsig=fixture-qr; uin=o10001; p_skey=fixture-poll';

String _callback(String code, {String redirect = ''}) =>
    "ptuiCB('$code','0','$redirect','0','fixture','')";

_Api _api(String raw) => _Api(dio: _client(raw))..setCookie('qrsig=fixture-qr');

Dio _client(String raw) {
  final dio = Dio()..httpClientAdapter = _QrAdapter(raw);
  addTearDown(() => dio.close(force: true));
  return dio;
}

class _Api extends VideoQqApi {
  _Api({super.dio});
  String? oauthRedirect;
  String? cookiesBeforeOAuth;

  @override
  Future<String?> completeOAuthLogin(String redirectUrl) async {
    oauthRedirect = redirectUrl;
    cookiesBeforeOAuth = cookie;
    return 'qqmusic_uin=10001; qm_keyst=music-key; '
        'qqmusic_encrypt_uin=encrypted-uin';
  }

  @override
  Future<Map<String, dynamic>> getUserInfo(String uin) async => {
    'profile': {'uin': '10001', 'nick': 'fixture-user'},
  };
}

class _QrAdapter implements HttpClientAdapter {
  _QrAdapter(this.raw);
  final String raw;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    raw,
    200,
    headers: {
      Headers.contentTypeHeader: ['text/plain'],
      'set-cookie': [
        'uin=o10001; Path=/; HttpOnly',
        'p_skey=fixture-poll; Domain=example.invalid; Secure',
      ],
    },
  );

  @override
  void close({bool force = false}) {}
}

class _FailedApi extends _Api {
  _FailedApi({super.dio});
  @override
  Future<String?> completeOAuthLogin(String redirectUrl) async => null;
}
