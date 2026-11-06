import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/platform/qq/qq_platform.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/multi_source/source_collection.dart';
import 'package:mconnect/video_app/multi_source/source_coordinator.dart';
import 'package:mconnect/video_app/multi_source/multi_source_player.dart';
import 'package:mconnect/video_app/video_preferences.dart';

const song = Song(
  id: 'mid',
  platform: PlatformType.qq,
  name: '测试歌曲',
  artists: [],
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('实际播放器在A地址加载失败后播放B，不重新请求标准档', () async {
    final settings = SourceSettings(VideoPreferences(_Box()));
    var collection = const SourceCollection(
      autoSwitch: true,
      sourceFirst: true,
      highestQuality: true,
    );
    for (final name in ['A', 'B']) {
      collection = collection.upsert(
        LxSourceConfig(
          name: name,
          version: '1',
          origin: Uri.parse('https://example.com/$name.js'),
          script: 'fixture',
          sha256: name,
          sources: const {
            'tx': ['flac', '128k'],
          },
          enabled: true,
        ),
      );
    }
    settings.value = collection;
    final calls = <String>[];
    final audio = _Audio();
    final router = PreparedSourceRouter(
      platformResolver: (_) => QqPlatform(),
      fixedQuality: (_) => AudioLevel.low,
    );
    final player = MultiSourceVideoPlayerNotifier(
      settings: settings,
      router: router,
      resolve: (_, c, token) async {
        calls.add('${c.name}:${c.quality.name}');
        if (c.official) throw const SourceFailure('unavailable', '官方不可用');
        return ResolvedSource(c, Uri.parse('https://example.com/${c.name}'));
      },
      audioController: audio,
      audioControllerFactory: () => audio,
      notificationController: const NoopPlaybackNotificationController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(player.dispose);
    await player.playSong(song);
    expect(player.state.isPlaying, isTrue);
    expect(player.state.currentSong, song);
    expect(player.state.currentQuality, AudioLevel.lossless);
    expect(audio.url, 'https://example.com/B');
    expect(audio.loads.where((url) => url.endsWith('/A')), hasLength(1));
    expect(calls, ['QQ音乐:hires', 'A:lossless', 'B:lossless']);
  });
  test('切歌后旧解析结果不能覆盖新歌曲', () async {
    final settings = SourceSettings(VideoPreferences(_Box()));
    settings.value = const SourceCollection(highestQuality: true);
    final pending = Completer<ResolvedSource>();
    final audio = _Audio();
    final player = MultiSourceVideoPlayerNotifier(
      settings: settings,
      router: PreparedSourceRouter(
        platformResolver: (_) => QqPlatform(),
        fixedQuality: (_) => AudioLevel.low,
      ),
      resolve: (s, c, _) => s.id == 'mid'
          ? pending.future
          : Future.value(ResolvedSource(c, Uri.parse('https://example.com/B'))),
      audioController: audio,
      audioControllerFactory: () => audio,
      notificationController: const NoopPlaybackNotificationController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(player.dispose);
    final a = player.playSong(song);
    await Future<void>.delayed(Duration.zero);
    const other = Song(
      id: 'other',
      platform: PlatformType.qq,
      name: '新歌',
      artists: [],
    );
    await player.playSong(other);
    pending.complete(
      ResolvedSource(
        const SourceCandidate(id: 'old', name: 'old', quality: AudioLevel.low),
        Uri.parse('https://example.com/old'),
      ),
    );
    await a;
    expect(player.state.currentSong, other);
    expect(audio.url, 'https://example.com/B');
  });
  test('暂停使正在装载的旧音频失效，完成后不能出声', () async {
    final settings = SourceSettings(VideoPreferences(_Box()))
      ..value = const SourceCollection(highestQuality: true);
    final audio = _Audio()..pending = Completer<void>();
    final player = MultiSourceVideoPlayerNotifier(
      settings: settings,
      router: PreparedSourceRouter(
        platformResolver: (_) => QqPlatform(),
        fixedQuality: (_) => AudioLevel.low,
      ),
      resolve: (s, c, _) async =>
          ResolvedSource(c, Uri.parse('https://example.com/B')),
      audioController: audio,
      audioControllerFactory: () => audio,
      notificationController: const NoopPlaybackNotificationController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(player.dispose);
    final work = player.playSong(song);
    while (audio.loads.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await player.togglePlay();
    audio.pending!.complete();
    await work;
    expect(audio.playCalls, 0);
    expect(player.state.isPlaying, isFalse);
    expect(player.state.error, isNull);
  });
  test('播放中错误继续下一源并恢复进度，暂停不触发换源', () async {
    final settings = SourceSettings(VideoPreferences(_Box()));
    var collection = const SourceCollection(
      autoSwitch: true,
      sourceFirst: true,
    );
    for (final name in ['B', 'C']) {
      collection = collection.upsert(
        LxSourceConfig(
          name: name,
          version: '1',
          origin: Uri.parse('https://example.com/$name.js'),
          script: 'fixture',
          sha256: name,
          sources: const {
            'tx': ['128k'],
          },
          enabled: true,
        ),
      );
    }
    settings.value = collection;
    final audio = _Audio();
    final calls = <String>[];
    final player = MultiSourceVideoPlayerNotifier(
      settings: settings,
      router: PreparedSourceRouter(
        platformResolver: (_) => QqPlatform(),
        fixedQuality: (_) => AudioLevel.low,
      ),
      resolve: (s, c, _) async {
        calls.add(c.name);
        return ResolvedSource(c, Uri.parse('https://example.com/${c.name}'));
      },
      audioController: audio,
      audioControllerFactory: () => audio,
      notificationController: const NoopPlaybackNotificationController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(player.dispose);
    await player.playSong(song);
    await player.seek(const Duration(seconds: 42));
    audio.events.addError(StateError('媒体断开'));
    for (var i = 0; i < 30 && audio.url != 'https://example.com/C'; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(Duration.zero);
    expect(audio.url, 'https://example.com/C');
    expect(player.state.currentSong, song);
    expect(audio.seekPosition, const Duration(seconds: 42));
    expect(calls, ['B', 'C']);
    await player.togglePlay();
    audio.events.addError(StateError('暂停后的旧错误'));
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['B', 'C']);
    expect(player.state.isPlaying, isFalse);
    expect(player.state.error, isNull);
  });
  test('离线本地命中不向任何音源请求，固定质量切换重新取流', () async {
    final settings = SourceSettings(VideoPreferences(_Box()))
      ..value = const SourceCollection(autoSwitch: true);
    final audio = _Audio();
    final qualities = <AudioLevel>[];
    var offline = true;
    final player = MultiSourceVideoPlayerNotifier(
      settings: settings,
      router: PreparedSourceRouter(
        platformResolver: (_) => QqPlatform(),
        fixedQuality: (_) => AudioLevel.low,
      ),
      resolve: (s, c, _) async {
        qualities.add(c.quality);
        return ResolvedSource(
          c,
          Uri.parse('https://example.com/${c.quality.name}'),
        );
      },
      isOfflineModeEnabled: () => offline,
      offlineFilePathResolver: (_) async => 'D:/cache/song.mp3',
      audioController: audio,
      audioControllerFactory: () => audio,
      notificationController: const NoopPlaybackNotificationController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(player.dispose);
    await player.playSong(song);
    expect(qualities, isEmpty);
    expect(audio.url, startsWith('file:'));
    offline = false;
    await player.playSong(song);
    await player.switchQuality(AudioLevel.lossless);
    expect(qualities, [AudioLevel.low, AudioLevel.lossless]);
    expect(player.state.currentQuality, AudioLevel.lossless);
  });
}

class _Box extends Fake implements Box {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => defaultValue;
}

class _Audio implements PlayerAudioController {
  String? url;
  final loads = <String>[];
  Completer<void>? pending;
  int playCalls = 0;
  final events = StreamController<AudioPlaybackState>.broadcast();
  Duration seekPosition = Duration.zero;
  bool _playing = false;
  @override
  bool get playing => _playing;
  @override
  Duration get position => seekPosition;
  @override
  double get volume => 1;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<AudioPlaybackState> get playerStateStream => events.stream;
  @override
  Future<void> stop() async {
    _playing = false;
  }

  @override
  Future<void> setUrl(String value) async {
    loads.add(value);
    await pending?.future;
    if (value.endsWith('/A')) throw StateError('音频404');
    url = value;
  }

  @override
  Future<void> play() async {
    playCalls++;
    _playing = true;
  }

  @override
  Future<void> pause() async {
    _playing = false;
  }

  @override
  Future<void> seek(Duration position) async {
    seekPosition = position;
  }

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
