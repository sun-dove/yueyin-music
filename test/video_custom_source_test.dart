import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/custom_source/custom_source_client.dart';
import 'package:mconnect/video_app/custom_source/custom_source_models.dart';
import 'package:mconnect/video_app/custom_source/custom_source_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('视频同款：自定义音源配置与凭据隔离', () {
    test('缺省配置保持关闭，往返持久化保留非敏感字段', () {
      final config = CustomSourceConfig(
        id: 'mine',
        name: '我的合法音源',
        endpoint: Uri.parse('https://source.example/api'),
        platforms: const {PlatformType.qq, PlatformType.netease},
        credentialRef: 'mine-token',
      );

      expect(config.enabled, isFalse);
      expect(config.timeoutSeconds, 10);
      expect(config.allowForDownloads, isFalse);
      expect(CustomSourceConfig.fromJson(config.toJson()), config);
      expect(config.toJson().toString(), isNot(contains('secret-token')));
    });

    test('配置拒绝空名称、非HTTPS、URL凭据、非法超时及空平台', () {
      final valid = _config();
      for (final entry in <String, CustomSourceConfig>{
        'name': valid.copyWith(name: '  '),
        'endpoint': valid.copyWith(
          endpoint: Uri.parse('http://source.example/api'),
        ),
        'credentials': valid.copyWith(
          endpoint: Uri.parse('https://user:pass@source.example/api'),
        ),
        'timeout': valid.copyWith(timeoutSeconds: 0),
        'platforms': valid.copyWith(platforms: const {}),
      }.entries) {
        expect(
          entry.value.validate,
          throwsA(
            isA<CustomSourceConfigurationException>().having(
              (error) => error.field,
              'field',
              entry.key,
            ),
          ),
        );
      }
    });

    test('配置只允许QQ和网易云，不扩写既有PlatformType', () {
      expect(
        _config().copyWith(platforms: const {PlatformType.local}).validate,
        throwsA(
          isA<CustomSourceConfigurationException>().having(
            (error) => error.field,
            'field',
            'platforms',
          ),
        ),
      );
      expect(PlatformType.values, containsAll(PlatformType.values));
    });

    test('普通设置存配置但不存令牌，删除后恢复为未配置', () async {
      final store = MemoryCustomSourcePreferenceStore();
      final config = _config(enabled: true, credentialRef: 'source-main');

      await store.save(config);
      expect(await store.load(), config);
      expect(jsonEncode(store.serializedValue), isNot(contains('token-value')));

      await store.delete();
      expect(await store.load(), isNull);
    });

    test('令牌只进入安全存储，按音源ID读取并随删除清除', () async {
      final backing = <String, String>{};
      FlutterSecureStorage.setMockInitialValues(backing);
      const store = SecureCustomSourceCredentialStore();

      await store.writeToken('mine', 'token-value');
      expect(await store.readToken('mine'), 'token-value');
      expect(backing.keys, [CustomSourceCredentialStore.tokenKey('mine')]);

      await store.deleteToken('mine');
      expect(await store.readToken('mine'), isNull);
      expect(backing, isEmpty);
    });
  });

  group('视频同款：受限HTTP JSON音源协议', () {
    test('请求只发送歌曲元数据与音质，令牌仅放Authorization且不发送Cookie', () async {
      final adapter = _SourceAdapter((options) {
        expect(options.method, 'POST');
        expect(options.uri.toString(), 'https://source.example/api/v1/resolve');
        expect(options.headers['Authorization'], 'Bearer token-value');
        expect(
          options.headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('cookie')),
        );
        expect(options.data, {
          'requestId': 'request-1',
          'platform': 'qq',
          'song': {
            'id': 'song-id',
            'title': '歌曲名',
            'artists': ['歌手甲', '歌手乙'],
            'album': '专辑名',
          },
          'quality': 'lossless',
          'purpose': 'play',
        });
        return _json({
          'url': 'https://media.example/song.flac',
          'quality': 'lossless',
          'format': 'flac',
          'bitrate': 921600,
          'expiresAt': '2030-01-02T03:04:05Z',
        });
      });
      final resolver = _resolver(adapter, token: 'token-value');

      final result = await resolver.resolve(_request());

      expect(result.url, Uri.parse('https://media.example/song.flac'));
      expect(result.actualQuality, AudioLevel.lossless);
      expect(result.format, 'flac');
      expect(result.bitrate, 921600);
      expect(result.expiresAt, DateTime.utc(2030, 1, 2, 3, 4, 5));
    });

    test('无令牌时不发送Authorization，下载目的被明确编码', () async {
      final adapter = _SourceAdapter((options) {
        expect(options.headers.containsKey('Authorization'), isFalse);
        expect((options.data as Map)['purpose'], 'download');
        return _json({
          'url': 'https://media.example/song.mp3',
          'quality': 'high',
        });
      });
      final result = await _resolver(adapter).resolve(
        _request(
          quality: AudioLevel.high,
          purpose: CustomSourcePurpose.download,
        ),
      );
      expect(result.actualQuality, AudioLevel.high);
    });

    test('HTTP状态映射到稳定错误类别及可重试属性', () async {
      for (final entry in <int, (CustomSourceFailureCode, bool)>{
        401: (CustomSourceFailureCode.unauthorized, false),
        403: (CustomSourceFailureCode.unauthorized, false),
        404: (CustomSourceFailureCode.notFound, false),
        429: (CustomSourceFailureCode.rateLimited, true),
        503: (CustomSourceFailureCode.sourceUnavailable, true),
      }.entries) {
        final resolver = _resolver(
          _SourceAdapter(
            (_) => _json({
              'error': {
                'code': 'fixture',
                'message': 'fixture failure',
                'retryable': entry.value.$2,
              },
            }, entry.key),
          ),
        );
        await expectLater(
          resolver.resolve(_request()),
          throwsA(
            isA<CustomSourceException>()
                .having((error) => error.code, 'code', entry.value.$1)
                .having(
                  (error) => error.retryable,
                  'retryable',
                  entry.value.$2,
                ),
          ),
        );
      }
    });

    test('网络超时与主动取消分开分类，取消不误导用户重试网络', () async {
      final timeout = _resolver(
        _SourceAdapter(
          (options) => throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
          ),
        ),
      );
      await expectLater(
        timeout.resolve(_request()),
        throwsA(
          isA<CustomSourceException>()
              .having(
                (error) => error.code,
                'code',
                CustomSourceFailureCode.timeout,
              )
              .having((error) => error.retryable, 'retryable', isTrue),
        ),
      );

      final cancelled = _resolver(
        _SourceAdapter(
          (options) => throw DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
          ),
        ),
      );
      await expectLater(
        cancelled.resolve(_request()),
        throwsA(
          isA<CustomSourceException>()
              .having(
                (error) => error.code,
                'code',
                CustomSourceFailureCode.cancelled,
              )
              .having((error) => error.retryable, 'retryable', isFalse),
        ),
      );
    });

    test('非JSON、缺少URL和未知音质都是无重试的协议错误', () async {
      for (final response in <ResponseBody>[
        ResponseBody.fromString('not-json', 200),
        _json({'quality': 'high'}),
        _json({
          'url': 'https://media.example/song.mp3',
          'quality': 'future-quality',
        }),
      ]) {
        await expectLater(
          _resolver(_SourceAdapter((_) => response)).resolve(_request()),
          throwsA(
            isA<CustomSourceException>()
                .having(
                  (error) => error.code,
                  'code',
                  CustomSourceFailureCode.invalidResponse,
                )
                .having((error) => error.retryable, 'retryable', isFalse),
          ),
        );
      }
    });

    test('响应拒绝非HTTPS、URL凭据、已过期链接和静默降音质', () async {
      final cases = <Map<String, dynamic>, CustomSourceFailureCode>{
        {'url': 'http://media.example/song.mp3', 'quality': 'lossless'}:
            CustomSourceFailureCode.invalidResponse,
        {
          'url': 'https://user:pass@media.example/song.mp3',
          'quality': 'lossless',
        }: CustomSourceFailureCode.invalidResponse,
        {
          'url': 'https://media.example/song.flac',
          'quality': 'lossless',
          'expiresAt': '2029-12-31T23:59:59Z',
        }: CustomSourceFailureCode.invalidResponse,
        {'url': 'https://media.example/song.mp3', 'quality': 'low'}:
            CustomSourceFailureCode.qualityUnavailable,
      };

      for (final entry in cases.entries) {
        final resolver = _resolver(
          _SourceAdapter((_) => _json(entry.key)),
          now: () => DateTime.utc(2030),
        );
        await expectLater(
          resolver.resolve(_request()),
          throwsA(
            isA<CustomSourceException>().having(
              (error) => error.code,
              'code',
              entry.value,
            ),
          ),
        );
      }
    });

    test('服务端标准错误体保留可读说明和显式retryable', () async {
      final resolver = _resolver(
        _SourceAdapter(
          (_) => _json({
            'error': {
              'code': 'not_found',
              'message': '当前音源没有这首歌',
              'retryable': false,
            },
          }, 422),
        ),
      );
      await expectLater(
        resolver.resolve(_request()),
        throwsA(
          isA<CustomSourceException>()
              .having(
                (error) => error.code,
                'code',
                CustomSourceFailureCode.notFound,
              )
              .having((error) => error.message, 'message', '当前音源没有这首歌')
              .having((error) => error.retryable, 'retryable', isFalse),
        ),
      );
    });
  });
}

CustomSourceConfig _config({bool enabled = false, String? credentialRef}) =>
    CustomSourceConfig(
      id: 'mine',
      name: '我的合法音源',
      endpoint: Uri.parse('https://source.example/api'),
      enabled: enabled,
      platforms: const {PlatformType.qq, PlatformType.netease},
      timeoutSeconds: 10,
      allowForDownloads: false,
      credentialRef: credentialRef,
    );

CustomSourceRequest _request({
  AudioLevel quality = AudioLevel.lossless,
  CustomSourcePurpose purpose = CustomSourcePurpose.play,
}) => CustomSourceRequest(
  requestId: 'request-1',
  platform: PlatformType.qq,
  song: const Song(
    id: 'song-id',
    platform: PlatformType.qq,
    name: '歌曲名',
    artists: [
      Artist(id: 'artist-1', name: '歌手甲'),
      Artist(id: 'artist-2', name: '歌手乙'),
    ],
    album: Album(id: 'album-1', name: '专辑名'),
  ),
  quality: quality,
  purpose: purpose,
);

HttpCustomSourceResolver _resolver(
  _SourceAdapter adapter, {
  String? token,
  DateTime Function()? now,
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  addTearDown(() => dio.close(force: true));
  return HttpCustomSourceResolver(
    config: _config(enabled: true, credentialRef: 'source-main'),
    dio: dio,
    credentialStore: MemoryCustomSourceCredentialStore(
      token == null ? null : {'source-main': token},
    ),
    now: now,
  );
}

ResponseBody _json(Map<String, dynamic> value, [int status = 200]) =>
    ResponseBody.fromString(
      jsonEncode(value),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

class _SourceAdapter implements HttpClientAdapter {
  _SourceAdapter(this.respond);

  final FutureOr<ResponseBody> Function(RequestOptions options) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);

  @override
  void close({bool force = false}) {}
}
