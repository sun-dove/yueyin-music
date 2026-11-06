import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/video_app/data/video_qq_playback_api.dart';

void main() {
  test('登录失效与未知协议码分开，取消不会继续发取流请求', () async {
    final api = _Api()..code = 1000;
    await expectLater(
      api.getSongUrl('mid'),
      throwsA(isA<LoginExpiredException>()),
    );
    api.code = 20001;
    await expectLater(
      api.getSongUrl('mid'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          '分类',
          ApiErrorCode.requestFailed,
        ),
      ),
    );
    api.calls.clear();
    final token = CancelToken()..cancel();
    await expectLater(
      api.withCancellation(token, () => api.getSongUrl('mid')),
      throwsA(isA<DioException>()),
    );
    expect(api.calls, isEmpty);
  });
  test('歌手数字ID不得污染歌曲元数据，旧收藏数字ID用详情补全', () async {
    final api = _Api();
    api.metadata.capture({
      'singer': [
        {'id': 7, 'mid': 'singer-mid'},
      ],
    });
    expect(api.metadata.lookup('7'), isNull);
    await api.getSongUrl('7');
    expect(((api.calls.first['req_0'] as Map)['param'] as Map)['song_id'], 7);
    expect(((api.calls.last['req_1'] as Map)['param'] as Map)['songmid'], [
      'mid',
    ]);
  });
  test('QQ数字ID、MID、媒体MID及歌曲类型保持独立', () {
    final store = QqMetadataStore();
    store.capture({
      'req_0': {
        'data': {
          'songlist': [
            {
              'id': 123,
              'mid': 'song-mid',
              'type': 1,
              'file': {'media_mid': 'media-mid'},
            },
          ],
        },
      },
    });
    final info = store.lookup('song-mid')!;
    expect(info.songId, 123);
    expect(info.songMid, 'song-mid');
    expect(info.mediaMid, 'media-mid');
    expect(info.songType, 1);
    expect(store.lookup('123'), same(info));
    expect(info.lxInfo['songId'], 123);
    expect(info.lxInfo['strMediaMid'], 'media-mid');
  });
  test('新取流适配器先补详情，使用真实媒体文件名和歌曲类型', () async {
    final api = _Api();
    await api.getSongUrl('mid', quality: AudioLevel.lossless);
    final request = api.calls.last['req_1'] as Map;
    expect(request['module'], 'music.vkey.GetVkey');
    final param = request['param'] as Map;
    expect(param['filename'], ['F000media.flac']);
    expect(param['songmid'], ['mid']);
    expect(param['songtype'], [1]);
    expect(api.metadata.lookup('mid')!.songId, 7);
  });
}

class _Api extends VideoQqPlaybackApi {
  int code = 0;
  final calls = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> musicu(Map<String, dynamic> data) async {
    calls.add(data);
    if (data.containsKey('req_0')) {
      return {
        'code': 0,
        'req_0': {
          'code': 0,
          'data': {
            'track_info': {
              'id': 7,
              'mid': 'mid',
              'type': 1,
              'file': {'media_mid': 'media'},
            },
          },
        },
      };
    }
    return {
      'code': code,
      'req_1': {
        'code': 0,
        'data': {'midurlinfo': []},
      },
    };
  }
}
