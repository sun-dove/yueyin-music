import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/platform/netease/netease_api.dart';
import 'package:mconnect/platform/qq/qq_api.dart';
import 'package:mconnect/platform/qq/qq_platform.dart';
import 'package:mconnect/video_app/playback/video_platforms.dart';
import 'package:mconnect/video_app/playback/video_player_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('第一首歌播放前可以选择固定音质', () {
    final delegate = _PlaybackDelegate();
    final player = _player(delegate, () => AudioLevel.hires);
    addTearDown(player.dispose);
    player.selectRequestedQuality(AudioLevel.lossless);
    expect(player.state.currentQuality, AudioLevel.lossless);
    expect(player.state.qualityPreference, AudioQualityPreference.fixed);
  });

  test('播放失败时只请求明确选择的音质，不降档或跳过当前歌曲', () async {
    final delegate = _PlaybackDelegate(fail: true);
    final player = _player(delegate, () => AudioLevel.hires);
    addTearDown(player.dispose);
    await player.playVideoPlaylist([_song('first'), _song('second')]);
    expect(delegate.requests, [('first', AudioLevel.hires)]);
    expect(player.state.currentSong?.id, 'first');
    expect(player.state.currentQuality, AudioLevel.hires);
    expect(player.state.error, isNotNull);
    expect(player.state.isPlaying, isFalse);
  });

  test('A正在播放时切到取流失败的B，旧音频必须停下', () async {
    final delegate = _PlaybackDelegate(unavailable: {'second'});
    final audio = _Audio();
    final player = _player(delegate, () => AudioLevel.high, audio: audio);
    addTearDown(player.dispose);
    await player.playSong(_song('first'));
    expect(audio.playing, isTrue);
    await player.playSong(_song('second'));
    expect(player.state.currentSong?.id, 'second');
    expect(player.state.error, isNotNull);
    expect(player.state.isPlaying, isFalse);
    expect(audio.playing, isFalse);
    expect(audio.playedUrls, ['https://audio.example/first.mp3']);
  });

  test('B取流失败后点击播放必须重新请求B，不能恢复旧音源A', () async {
    final unavailable = {'second'};
    final delegate = _PlaybackDelegate(unavailable: unavailable);
    final audio = _Audio();
    final player = _player(delegate, () => AudioLevel.high, audio: audio);
    addTearDown(player.dispose);
    await player.playSong(_song('first'));
    await player.playSong(_song('second'));
    unavailable.clear();
    await player.togglePlay();
    expect(delegate.requests, [
      ('first', AudioLevel.high),
      ('second', AudioLevel.high),
      ('second', AudioLevel.high),
    ]);
    expect(audio.playedUrls, [
      'https://audio.example/first.mp3',
      'https://audio.example/second.mp3',
    ]);
    expect(player.state.currentSong?.id, 'second');
    expect(player.state.error, isNull);
    expect(player.state.isPlaying, isTrue);
    expect(audio.playing, isTrue);
  });

  test('播放包装不会限制下载直接调用平台时选择不同音质', () async {
    final delegate = _PlaybackDelegate();
    final playback = VideoPlaybackPlatform(
      delegate,
      requestedQuality: () => AudioLevel.hires,
    );
    await expectLater(
      playback.getSongUrl('first', quality: AudioLevel.low),
      throwsA(isA<QualityNotAvailableException>()),
    );
    expect(delegate.requests, isEmpty);
    await delegate.getSongUrl('first', quality: AudioLevel.low);
    expect(delegate.requests, [('first', AudioLevel.low)]);
  });

  test('每次手动切歌读取对应平台的当前偏好', () async {
    final delegate = _PlaybackDelegate();
    var requested = AudioLevel.medium;
    final player = _player(delegate, () => requested);
    addTearDown(player.dispose);
    await player.playSong(_song('first'));
    requested = AudioLevel.lossless;
    await player.playSong(_song('second'));
    expect(delegate.requests, [
      ('first', AudioLevel.medium),
      ('second', AudioLevel.lossless),
    ]);
    expect(player.state.currentQuality, AudioLevel.lossless);
  });

  test('QQ记录返回音源的格式，未知码率与试听不假定', () async {
    final metadata = <VideoStreamInfo>[];
    final platform = VideoQqPlatform(
      api: _QqResponseApi(_qqResponse('F000song.flac')),
      onResolved: metadata.add,
    );
    final url = await platform.getSongUrl('song', quality: AudioLevel.lossless);
    expect(url, 'https://audio.example/F000song.flac');
    expect(metadata.single.requestedQuality, AudioLevel.lossless);
    expect(metadata.single.actualFormat, 'flac');
    expect(metadata.single.actualBitrate, isNull);
    expect(metadata.single.isPreview, isNull);
  });

  test('QQ要求无损但平台回低码率文件时明确拒绝', () async {
    final platform = VideoQqPlatform(
      api: _QqResponseApi(_qqResponse('M500song.mp3')),
    );
    await expectLater(
      platform.getSongUrl('song', quality: AudioLevel.lossless),
      throwsA(isA<QualityNotAvailableException>()),
    );
  });

  test('QQ只回显候选文件名但没有音源时，真实格式和码率保持未知', () async {
    final metadata = <VideoStreamInfo>[];
    final response = _qqResponse('O801song.ogg');
    (response['req_1']['data']['midurlinfo'] as List).first['purl'] = '';
    final platform = VideoQqPlatform(
      api: _QqResponseApi(response),
      useOgg640: () => true,
      onResolved: metadata.add,
    );
    await expectLater(
      platform.getSongUrl('song', quality: AudioLevel.high),
      throwsA(isA<SongNotAvailableException>()),
    );
    expect(metadata.single.actualFormat, isNull);
    expect(metadata.single.actualQuality, isNull);
    expect(metadata.single.actualBitrate, isNull);
    expect(platform.hasVerifiedOgg640, isFalse);
  });

  test('QQ候选无损文件名不能覆盖实际返回MP3资源的降档证据', () async {
    final response = _qqResponse('F000song.flac');
    (response['req_1']['data']['midurlinfo'] as List).first['purl'] =
        'M500song.mp3?vkey=anonymous';
    final metadata = <VideoStreamInfo>[];
    final platform = VideoQqPlatform(
      api: _QqResponseApi(response),
      onResolved: metadata.add,
    );
    await expectLater(
      platform.getSongUrl('song', quality: AudioLevel.lossless),
      throwsA(isA<QualityNotAvailableException>()),
    );
    expect(metadata.single.actualFormat, 'mp3');
  });

  test('QQ显式OGG请求使用独立文件档位，不把文件名推断为实测码率', () async {
    final api = _QqResponseApi(_qqResponse('O801song.ogg'));
    final metadata = <VideoStreamInfo>[];
    final platform = VideoQqPlatform(
      api: api,
      useOgg640: () => true,
      onResolved: metadata.add,
    );
    await platform.getSongUrl('song', quality: AudioLevel.high);
    final request = api.lastMusicu!['req_1'] as Map;
    expect((request['param'] as Map)['filename'], ['O801songsong.ogg']);
    expect(metadata.single.actualFormat, 'ogg');
    expect(metadata.single.actualBitrate, isNull);
    expect(platform.hasVerifiedOgg640, isFalse);
  });

  test('网易云返回降档时记录真实返回规格后拒绝静默接受', () async {
    final metadata = <VideoStreamInfo>[];
    final platform = VideoNeteasePlatform(
      api: _NeteaseResponseApi({
        'data': [
          {
            'url': 'https://audio.example/song.mp3',
            'level': 'standard',
            'type': 'mp3',
            'br': 128000,
            'freeTrialInfo': null,
          },
        ],
      }),
      onResolved: metadata.add,
    );
    await expectLater(
      platform.getSongUrl('song', quality: AudioLevel.hires),
      throwsA(isA<QualityNotAvailableException>()),
    );
    expect(metadata.single.actualBitrate, 128000);
    expect(metadata.single.actualFormat, 'mp3');
    expect(metadata.single.isPreview, isFalse);
  });

  test('网易云试听不能当作完整歌曲起播', () async {
    final metadata = <VideoStreamInfo>[];
    final platform = VideoNeteasePlatform(
      api: _NeteaseResponseApi({
        'data': [
          {
            'url': 'https://audio.example/trial.mp3',
            'level': 'standard',
            'br': 128000,
            'freeTrialInfo': {'start': 0, 'end': 30000},
          },
        ],
      }),
      onResolved: metadata.add,
    );
    await expectLater(
      platform.getSongUrl('song'),
      throwsA(isA<NoVipMembershipException>()),
    );
    expect(metadata.single.isPreview, isTrue);
  });

  test('网易云实际音质正确时保留对应格式和码率', () async {
    final metadata = <VideoStreamInfo>[];
    final api = _NeteaseResponseApi({
      'data': [
        {
          'url': 'https://audio.example/song.flac',
          'level': 'lossless',
          'type': 'flac',
          'br': 921600,
          'freeTrialInfo': null,
        },
      ],
    });
    final platform = VideoNeteasePlatform(api: api, onResolved: metadata.add);
    expect(
      await platform.getSongUrl('song', quality: AudioLevel.lossless),
      'https://audio.example/song.flac',
    );
    expect(api.lastLevel, 'lossless');
    expect(metadata.single.actualBitrate, 921600);
    expect(metadata.single.actualFormat, 'flac');
  });
}

VideoPlayerNotifier _player(
  _PlaybackDelegate delegate,
  AudioLevel Function() requested, {
  _Audio? audio,
}) => VideoPlayerNotifier(
  platformResolver: (_) => delegate,
  requestedQuality: (_) => requested(),
  audioController: audio ?? _Audio(),
  audioControllerFactory: _Audio.new,
  notificationController: const NoopPlaybackNotificationController(),
  keepAliveController: const NoopPlaybackKeepAliveController(),
);

Song _song(String id) => Song(
  id: id,
  platform: PlatformType.qq,
  name: id,
  artists: const [],
  duration: const Duration(minutes: 3),
);

Map<String, dynamic> _qqResponse(String filename) => {
  'req_1': {
    'code': 0,
    'data': {
      'sip': ['https://audio.example/'],
      'midurlinfo': [
        {'filename': filename, 'purl': filename},
      ],
    },
  },
};

class _PlaybackDelegate extends QqPlatform {
  final bool fail;
  final Set<String> unavailable;
  final requests = <(String, AudioLevel)>[];
  _PlaybackDelegate({this.fail = false, this.unavailable = const {}});

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) async {
    requests.add((songId, quality));
    if (fail || unavailable.contains(songId)) throw SongNotAvailableException();
    return 'https://audio.example/$songId.mp3';
  }
}

class _QqResponseApi extends QqApi {
  final Map<String, dynamic> response;
  Map<String, dynamic>? lastMusicu;
  _QqResponseApi(this.response);

  @override
  Future<Map<String, dynamic>> getSongUrl(
    String songMid, {
    AudioLevel quality = AudioLevel.low,
  }) async => response;

  @override
  Future<Map<String, dynamic>> musicu(Map<String, dynamic> data) async {
    lastMusicu = data;
    return response;
  }
}

class _NeteaseResponseApi extends NeteaseApi {
  final Map<String, dynamic> response;
  String? lastLevel;
  _NeteaseResponseApi(this.response);

  @override
  Future<Map<String, dynamic>> getSongUrl(
    String songId, {
    String level = 'standard',
  }) async {
    lastLevel = level;
    return response;
  }
}

class _Audio implements PlayerAudioController {
  bool _playing = false;
  String? currentUrl;
  final playedUrls = <String?>[];
  @override
  bool get playing => _playing;
  @override
  Duration get position => Duration.zero;
  @override
  double get volume => 1;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<AudioPlaybackState> get playerStateStream => const Stream.empty();
  @override
  Future<void> stop() async => _playing = false;
  @override
  Future<void> setUrl(String url) async => currentUrl = url;
  @override
  Future<void> play() async {
    playedUrls.add(currentUrl);
    _playing = true;
  }

  @override
  Future<void> pause() async => _playing = false;
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> bandGains,
  }) async {}
  @override
  Future<void> dispose() async {}
}
