import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/platform/qq/qq_platform.dart';
import 'package:mconnect/video_app/custom_source/custom_source_models.dart';
import 'package:mconnect/video_app/custom_source/custom_source_playback.dart';
import 'package:mconnect/video_app/playback/video_player_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('自定义音源播放触发矩阵', () {
    test('官方取流成功时完全不请求自定义音源', () async {
      final resolver = _Resolver();
      final player = _player(_Platform(), fallback: _fallback(resolver));
      addTearDown(player.dispose);

      await player.playSong(_song('official-ok'));

      expect(resolver.requests, isEmpty);
      expect(player.state.error, isNull);
      expect(player.state.isPlaying, isTrue);
    });

    test('歌曲不可用、会员不可用、固定音质不可用才请求自定义音源', () async {
      for (final error in <Object>[
        SongNotAvailableException(platform: 'QQ音乐'),
        NoVipMembershipException('QQ音乐'),
        QualityNotAvailableException(),
      ]) {
        final resolver = _Resolver();
        final player = _player(
          _Platform(error: error),
          fallback: _fallback(resolver),
        );
        addTearDown(player.dispose);

        await player.playSong(_song('supported-${error.runtimeType}'));

        expect(resolver.requests, hasLength(1), reason: '$error 应触发音源');
        expect(resolver.requests.single.purpose, CustomSourcePurpose.play);
        expect(player.state.error, isNull);
        expect(player.state.isPlaying, isTrue);
      }
    });

    test('登录过期、取消、网络和未知错误不请求自定义音源', () async {
      for (final error in <Object>[
        LoginExpiredException(),
        RequestCancelledException(),
        NetworkException(),
        ApiException(message: '内部错误'),
      ]) {
        final resolver = _Resolver();
        final player = _player(
          _Platform(error: error),
          fallback: _fallback(resolver),
        );
        addTearDown(player.dispose);

        await player.playSong(_song('blocked-${error.runtimeType}'));

        expect(resolver.requests, isEmpty, reason: '$error 不得触发音源');
        expect(player.state.isPlaying, isFalse);
        expect(player.state.error, isNotNull);
      }
    });

    test('自定义音源成功后停留当前歌曲并播放返回地址', () async {
      final resolver = _Resolver(
        result: _result('https://source.example/custom.mp3'),
      );
      final audio = _Audio();
      final player = _player(
        _Platform(error: SongNotAvailableException()),
        fallback: _fallback(resolver),
        audio: audio,
      );
      addTearDown(player.dispose);

      await player.playVideoPlaylist([
        _song('custom-success'),
        _song('must-not-skip'),
      ]);

      expect(player.state.currentSong?.id, 'custom-success');
      expect(audio.playedUrls, ['https://source.example/custom.mp3']);
      expect(player.state.error, isNull);
      expect(player.state.isPlaying, isTrue);
    });

    test('自定义音源失败后再次点击播放会重新解析当前歌曲', () async {
      final resolver = _SequencedResolver();
      final audio = _Audio();
      final player = _player(
        _Platform(error: SongNotAvailableException()),
        fallback: _fallback(resolver),
        audio: audio,
      );
      addTearDown(player.dispose);

      await player.playSong(_song('retry-current'));
      expect(player.state.currentSong?.id, 'retry-current');
      expect(player.state.error, isNotNull);
      expect(resolver.requests, hasLength(1));

      await player.togglePlay();

      expect(resolver.requests, hasLength(2));
      expect(player.state.currentSong?.id, 'retry-current');
      expect(player.state.error, isNull);
      expect(audio.playedUrls, ['https://source.example/retry.mp3']);
    });
  });

  group('自定义音源配置与用途策略', () {
    test('配置关闭或当前平台未启用时不调用底层 resolver', () async {
      final disabledResolver = _Resolver();
      final disabled = CustomSourcePlaybackFallback(
        resolver: disabledResolver,
        config: () => _config(enabled: false),
      );
      expect(
        await disabled.resolve(
          _song('disabled'),
          AudioLevel.low,
          SongNotAvailableException(),
        ),
        isNull,
      );
      expect(disabledResolver.requests, isEmpty);

      final wrongPlatformResolver = _Resolver();
      final wrongPlatform = CustomSourcePlaybackFallback(
        resolver: wrongPlatformResolver,
        config: () => _config(platforms: {PlatformType.netease}),
      );
      expect(
        await wrongPlatform.resolve(
          _song('wrong-platform'),
          AudioLevel.low,
          SongNotAvailableException(),
        ),
        isNull,
      );
      expect(wrongPlatformResolver.requests, isEmpty);
    });

    test('下载默认禁用，用户显式开启后才允许解析', () async {
      final resolver = _Resolver();
      var config = _config();
      final fallback = CustomSourcePlaybackFallback(
        resolver: resolver,
        config: () => config,
      );

      expect(
        await fallback.resolve(
          _song('download'),
          AudioLevel.high,
          SongNotAvailableException(),
          purpose: CustomSourcePurpose.download,
        ),
        isNull,
      );
      expect(resolver.requests, isEmpty);

      config = _config(allowForDownloads: true);
      final result = await fallback.resolve(
        _song('download'),
        AudioLevel.high,
        SongNotAvailableException(),
        purpose: CustomSourcePurpose.download,
      );
      expect(result?.url.toString(), 'https://source.example/song.mp3');
      expect(resolver.requests.single.purpose, CustomSourcePurpose.download);
    });

    test('请求包含完整歌曲信息、固定音质和用途', () async {
      final resolver = _Resolver();
      final fallback = _fallback(resolver);

      await fallback.resolve(
        _song('payload'),
        AudioLevel.lossless,
        NoVipMembershipException('QQ音乐'),
      );

      final request = resolver.requests.single;
      expect(request.platform, PlatformType.qq);
      expect(request.song.id, 'payload');
      expect(request.song.name, '歌曲 payload');
      expect(request.song.artistNames, '歌手');
      expect(request.song.album?.name, '专辑');
      expect(request.quality, AudioLevel.lossless);
      expect(request.purpose, CustomSourcePurpose.play);
      expect(request.requestId, isNotEmpty);
    });
  });

  group('自定义音源并发与取消', () {
    test('新解析请求取消上一条在途请求', () async {
      final resolver = _ControlledResolver();
      final fallback = _fallback(resolver);

      final first = fallback.resolve(
        _song('first'),
        AudioLevel.low,
        SongNotAvailableException(),
      );
      await _waitFor(() => resolver.requests.length == 1);
      final second = fallback.resolve(
        _song('second'),
        AudioLevel.low,
        SongNotAvailableException(),
      );
      await _waitFor(() => resolver.requests.length == 2);

      expect(resolver.tokens.first.isCancelled, isTrue);
      expect(resolver.tokens.last.isCancelled, isFalse);
      resolver.completers.last.complete(
        _result('https://source.example/2.mp3'),
      );
      resolver.completers.first.complete(
        _result('https://source.example/1.mp3'),
      );
      await expectLater(second, completion(isNotNull));
      await expectLater(first, completion(isNull));
    });

    test('歌曲A的迟到响应不能覆盖已选择并播放的歌曲B', () async {
      final resolver = _ControlledResolver();
      final audio = _Audio();
      final player = _player(
        _Platform(errorIds: const {'a'}),
        fallback: _fallback(resolver),
        audio: audio,
      );
      addTearDown(player.dispose);

      final first = player.playSong(_song('a'));
      await _waitFor(() => resolver.requests.length == 1);
      await player.playSong(_song('b'));
      resolver.completers.single.complete(
        _result('https://source.example/a-late.mp3'),
      );
      await first;

      expect(player.state.currentSong?.id, 'b');
      expect(audio.playedUrls, ['https://official.example/b.mp3']);
      expect(player.state.error, isNull);
      expect(player.state.isPlaying, isTrue);
    });
  });
}

CustomSourcePlaybackFallback _fallback(CustomSourceResolver resolver) =>
    CustomSourcePlaybackFallback(resolver: resolver, config: _config);

CustomSourceConfig _config({
  bool enabled = true,
  Set<PlatformType> platforms = const {PlatformType.qq},
  bool allowForDownloads = false,
}) => CustomSourceConfig(
  id: 'source-1',
  name: '我的音源',
  endpoint: Uri.parse('https://source.example'),
  enabled: enabled,
  platforms: platforms,
  allowForDownloads: allowForDownloads,
);

CustomSourceResult _result(String url) => CustomSourceResult(
  url: Uri.parse(url),
  actualQuality: AudioLevel.high,
  format: 'mp3',
  bitrate: 320000,
  sourceId: 'source-1',
  sourceName: '我的音源',
);

VideoPlayerNotifier _player(
  _Platform platform, {
  required CustomSourcePlaybackFallback fallback,
  _Audio? audio,
}) => VideoPlayerNotifier(
  platformResolver: (_) => platform,
  requestedQuality: (_) => AudioLevel.low,
  customSourceFallback: fallback,
  audioController: audio ?? _Audio(),
  audioControllerFactory: _Audio.new,
  notificationController: const NoopPlaybackNotificationController(),
  keepAliveController: const NoopPlaybackKeepAliveController(),
);

Song _song(String id) => Song(
  id: id,
  platform: PlatformType.qq,
  name: '歌曲 $id',
  artists: const [Artist(id: 'artist', name: '歌手')],
  album: const Album(id: 'album', name: '专辑'),
  duration: const Duration(minutes: 3),
);

class _Platform extends QqPlatform {
  _Platform({this.error, this.errorIds = const {}});

  final Object? error;
  final Set<String> errorIds;

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) async {
    if (error != null || errorIds.contains(songId)) {
      throw error ?? SongNotAvailableException();
    }
    return 'https://official.example/$songId.mp3';
  }
}

class _Resolver implements CustomSourceResolver {
  _Resolver({CustomSourceResult? result})
    : result = result ?? _result('https://source.example/song.mp3');

  final CustomSourceResult result;
  final List<CustomSourceRequest> requests = [];
  final List<CancelToken> tokens = [];

  @override
  Future<CustomSourceResult> resolve(
    CustomSourceRequest request, {
    CancelToken? cancelToken,
  }) async {
    requests.add(request);
    if (cancelToken != null) tokens.add(cancelToken);
    return result;
  }
}

class _ControlledResolver implements CustomSourceResolver {
  final List<CustomSourceRequest> requests = [];
  final List<CancelToken> tokens = [];
  final List<Completer<CustomSourceResult>> completers = [];

  @override
  Future<CustomSourceResult> resolve(
    CustomSourceRequest request, {
    CancelToken? cancelToken,
  }) {
    requests.add(request);
    tokens.add(cancelToken!);
    final completer = Completer<CustomSourceResult>();
    completers.add(completer);
    return completer.future;
  }
}

class _SequencedResolver implements CustomSourceResolver {
  final List<CustomSourceRequest> requests = [];

  @override
  Future<CustomSourceResult> resolve(
    CustomSourceRequest request, {
    CancelToken? cancelToken,
  }) async {
    requests.add(request);
    if (requests.length == 1) {
      throw ApiException(message: '自定义音源暂时不可用');
    }
    return _result('https://source.example/retry.mp3');
  }
}

class _Audio implements PlayerAudioController {
  bool _playing = false;
  String? currentUrl;
  final List<String?> playedUrls = [];

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

Future<void> _waitFor(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('等待条件超时');
}
