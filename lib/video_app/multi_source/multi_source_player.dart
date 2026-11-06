import '../../l10n/source_strings.dart';

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/player/presentation/providers/player_provider.dart';
import '../../core/platform/platform_utils.dart';
import '../../features/player/data/media_kit_windows_audio_controller.dart';
import '../../features/player/data/playback_notification_service.dart';
import '../../models/audio_quality.dart';
import '../../models/platform_type.dart';
import '../../models/song.dart';
import '../../platform/base/music_platform.dart';
import '../custom_source/custom_source_playback.dart';
import '../playback/video_platforms.dart';
import '../playback/video_player_notifier.dart';
import 'source_collection.dart';
import 'source_coordinator.dart';

class SourcePlaybackView {
  const SourcePlaybackView({
    this.message = '',
    this.details = '',
    this.busy = false,
    this.canContinue = false,
  });
  final String message, details;
  final bool busy, canContinue;
}

final sourcePlaybackViewProvider = StateProvider<SourcePlaybackView>(
  (ref) => const SourcePlaybackView(),
);

class PreparedSourceRouter {
  PreparedSourceRouter({
    required this.platformResolver,
    required this.fixedQuality,
  });
  final MusicPlatform Function(PlatformType) platformResolver;
  final AudioLevel Function(PlatformType) fixedQuality;
  ResolvedSource? prepared;
  Song? song;
  bool guarded = false;
  CancelToken mediaToken = CancelToken();
  Duration Function()? timeLeft;
  final failedUrls = <String>{};
  bool seekFailed = false;
  void cancelMedia() {
    mediaToken.cancel();
    mediaToken = CancelToken();
  }

  AudioLevel quality(PlatformType type) =>
      song?.platform == type && prepared != null
      ? prepared!.candidate.quality
      : fixedQuality(type);
  MusicPlatform platform(PlatformType type) =>
      _PreparedPlatform(platformResolver(type), this);
}

class _PreparedPlatform extends VideoPlaybackPlatform {
  _PreparedPlatform(super.platform, this.router)
    : super(requestedQuality: () => router.quality(platform.platformType));
  final PreparedSourceRouter router;
  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) {
    if (router.song?.id == songId &&
        router.song?.platform == platformType &&
        router.prepared != null) {
      return Future.value(router.prepared!.url.toString());
    }
    if (router.guarded) {
      throw const SourceFailure('cancelled', SourceStrings.oldRequestCancelled);
    }
    return delegate.getSongUrl(songId, quality: quality);
  }
}

typedef MultiSourceResolve = Future<ResolvedSource> Function(
  Song,
  SourceCandidate,
  CancelToken,
);

PlayerAudioController _defaultSourceAudio() {
  if (PlatformUtils.isAndroid) return AudioServicePlayerController.instance;
  if (PlatformUtils.isWindows) return MediaKitWindowsAudioController();
  return JustAudioController();
}

/// 只作用于新增入口：拦截重复坏地址和取消后迟到的播放，保留底层重建能力。
class _SourceAudio
    implements PlayerAudioController, PlaybackSpeedCapable, SkipSilenceCapable {
  _SourceAudio(this.delegate, this.router);
  final PlayerAudioController delegate;
  final PreparedSourceRouter router;
  CancelToken? _loaded;
  bool get _current =>
      !router.guarded ||
      (_loaded == router.mediaToken && _loaded?.isCancelled == false);
  Stream<T> _events<T>(Stream<T> stream) => stream.transform(
    StreamTransformer<T, T>.fromHandlers(
      handleData: (value, sink) {
        if (_current) sink.add(value);
      },
      handleError: (Object error, StackTrace stack, EventSink<T> sink) {
        if (_current) sink.addError(error, stack);
      },
    ),
  );
  @override
  bool get playing => delegate.playing;
  @override
  Duration get position => delegate.position;
  @override
  double get volume => delegate.volume;
  @override
  Stream<Duration> get positionStream => _events(delegate.positionStream);
  @override
  Stream<Duration?> get durationStream => _events(delegate.durationStream);
  @override
  Stream<AudioPlaybackState> get playerStateStream =>
      _events(delegate.playerStateStream);
  @override
  Future<void> setUrl(String url) async {
    if (!router.guarded) {
      _loaded = null;
      await delegate.setUrl(url);
      return;
    }
    final token = router.mediaToken;
    if (router.prepared?.url.toString() != url ||
        router.failedUrls.contains(url)) {
      throw const SourceFailure('load', SourceStrings.invalidAudio);
    }
    final remaining = router.timeLeft?.call() ?? const Duration(seconds: 10);
    if (remaining <= Duration.zero) {
      throw const SourceFailure('timeout', SourceStrings.loadBudgetUsed);
    }
    try {
      await Future.any<void>([
        delegate.setUrl(url),
        token.whenCancel.then(
          (_) => throw const SourceFailure(
            'cancelled',
            SourceStrings.loadCancelled,
          ),
        ),
      ]).timeout(
        remaining < const Duration(seconds: 10)
            ? remaining
            : const Duration(seconds: 10),
      );
      if (token.isCancelled) throw token.cancelError!;
      _loaded = token;
    } catch (_) {
      router.failedUrls.add(url);
      rethrow;
    }
  }

  @override
  Future<void> play() {
    if (router.guarded &&
        (_loaded != router.mediaToken || _loaded?.isCancelled != false)) {
      return Future.value();
    }
    return delegate.play();
  }

  @override
  Future<void> stop() => delegate.stop();
  @override
  Future<void> pause() => delegate.pause();
  @override
  Future<void> seek(Duration value) async {
    try {
      await delegate.seek(value);
    } catch (_) {
      router.seekFailed = true;
      rethrow;
    }
  }

  @override
  Future<void> setVolume(double value) => delegate.setVolume(value);
  @override
  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> bandGains,
  }) => delegate.applyEqualizer(enabled: enabled, bandGains: bandGains);
  @override
  double get playbackSpeed => delegate is PlaybackSpeedCapable
      ? (delegate as PlaybackSpeedCapable).playbackSpeed
      : 1;
  @override
  Future<void> setPlaybackSpeed(double speed) async {
    if (delegate is PlaybackSpeedCapable) {
      await (delegate as PlaybackSpeedCapable).setPlaybackSpeed(speed);
    }
  }

  @override
  Future<void> setSkipSilence(bool enabled) async {
    if (delegate is SkipSilenceCapable) {
      await (delegate as SkipSilenceCapable).setSkipSilence(enabled);
    }
  }

  @override
  Future<void> dispose() => delegate.dispose();
}

/// 多源解析在旧播放器单次取流计时器外；每次只装载已准备好的候选。
class MultiSourceVideoPlayerNotifier extends VideoPlayerNotifier {
  MultiSourceVideoPlayerNotifier({
    required this.settings,
    required this.router,
    required this.resolve,
    this.onProgress,
    CustomSourcePlaybackFallback? legacyFallback,
    PlayerAudioController? audioController,
    PlayerAudioController Function()? audioControllerFactory,
    super.playbackMemoryStore,
    super.notificationController,
    super.keepAliveController,
    super.isSongLiked,
    super.toggleSongLike,
    super.offlineFilePathResolver,
    super.isOfflineModeEnabled,
  }) : _offlinePath = offlineFilePathResolver,
       _offlineMode = isOfflineModeEnabled,
       super(
         platformResolver: router.platform,
         requestedQuality: router.quality,
         audioController: audioController == null
             ? null
             : _SourceAudio(audioController, router),
         audioControllerFactory: () => _SourceAudio(
           (audioControllerFactory ?? _defaultSourceAudio)(),
           router,
         ),
         customSourceFallback: legacyFallback,
       ) {
    settings.addListener(_settingsChanged);
    _unlisten = addListener((value) {
      final session = _session;
      if (_advancing ||
          _paused ||
          session == null ||
          session.cancelled ||
          _active == null ||
          value.error == null) {
        return;
      }
      if (value.currentSong != _song) return;
      final source = _active!;
      _active = null;
      session.failed(source, SourceFailure('playback', value.error!));
      session.renewBudget();
      _advancing = true;
      final generation = _generation;
      scheduleMicrotask(() => _advance(generation, value.position));
    }, fireImmediately: false);
  }
  final SourceSettings settings;
  final PreparedSourceRouter router;
  final MultiSourceResolve resolve;
  final void Function(SourcePlaybackView)? onProgress;
  final OfflineFilePathResolver? _offlinePath;
  final bool Function()? _offlineMode;
  late final void Function() _unlisten;
  SourceSession? _session;
  ResolvedSource? _active;
  Song? _song;
  int _generation = 0;
  bool _advancing = false, _paused = false;
  Future<void>? _loading;
  AudioLevel? _fixedOverride;

  bool get _multiEnabled =>
      settings.value.autoSwitch ||
      settings.value.highestQuality ||
      settings.value.sourceFirst;
  void _settingsChanged() {
    final wasGuarded = router.guarded;
    cancelSourceAttempts();
    if (wasGuarded) unawaited(super.pause());
  }

  void cancelSourceAttempts() {
    _generation++;
    _session?.cancel();
    router.cancelMedia();
    _active = null;
    router.prepared = null;
    _advancing = false;
    if (mounted && state.isTransitioning) {
      state = state.copyWith(
        isTransitioning: false,
        isPlaying: false,
        error: () => null,
      );
    }
    onProgress?.call(const SourcePlaybackView());
  }

  @override
  Future<void> playSong(Song song) => _start(song, Duration.zero);

  Future<void> _start(Song song, Duration position) async {
    cancelSourceAttempts();
    final generation = _generation;
    await _loading;
    if (generation != _generation || !mounted) return;
    _paused = false;
    _song = song;
    router.song = song;
    router.failedUrls.clear();
    router.guarded = _multiEnabled && song.platform != PlatformType.local;
    if (!router.guarded) {
      await super.playSong(song);
      return;
    }
    if (_offlineMode?.call() == true && _offlinePath != null) {
      final local = await _offlinePath(song);
      if (generation != _generation || !mounted) return;
      if (local != null) {
        router.guarded = false;
        await super.playSong(song);
        return;
      }
    }
    await super.pause();
    if (generation != _generation || !mounted) return;
    final queue = [...state.playlist];
    var index = queue.indexWhere((s) => s == song);
    if (index < 0) {
      index = queue.length;
      queue.add(song);
    }
    state = state.copyWith(
      currentSong: song,
      playlist: queue,
      currentIndex: index,
      position: position,
      duration: song.duration,
      isPlaying: false,
      isTransitioning: true,
      error: () => null,
    );
    _session = SourceSession(
      exclusions: sourceExclusions(
        song,
        _fixedOverride ?? router.fixedQuality(song.platform),
        settings.value,
      ),
      candidates: buildSourceCandidates(
        song,
        _fixedOverride ?? router.fixedQuality(song.platform),
        settings.value,
      ),
      resolve: (candidate, token) => resolve(song, candidate, token),
      onChanged: _report,
    );
    router.timeLeft = () => _session?.timeLeft ?? Duration.zero;
    await _advance(generation, position);
  }

  void _report() {
    if (!mounted || _session?.cancelled == true) return;
    final session = _session;
    if (session == null) return;
    final last = session.attempts.lastOrNull;
    final downgraded =
        settings.value.highestQuality &&
        last != null &&
        last.candidate.quality != AudioLevel.hires;
    final qualityNotice = downgraded ? SourceStrings.downshift : '';
    final evidence = _active?.bitrate != null
        ? SourceStrings.bitrate(_active!.bitrate! ~/ 1000)
        : SourceStrings.qualityUnverified;
    final message = last == null
        ? SourceStrings.preparing
        : switch (last.stage) {
            SourceStage.resolving => SourceStrings.trying(
              qualityNotice,
              last.candidate.label,
            ),
            SourceStage.resolved => SourceStrings.loading(last.candidate.label),
            SourceStage.playing => SourceStrings.playback(
              qualityNotice,
              last.candidate.name,
              last.candidate.quality.displayName,
              evidence,
              router.seekFailed,
            ),
            _ => SourceStrings.switching,
          };
    onProgress?.call(
      SourcePlaybackView(
        message: message,
        details: session.summary,
        busy: _advancing,
        canContinue: session.budgetExpired && session.canContinue,
      ),
    );
  }

  Future<void> _advance(int generation, Duration position) async {
    if (!mounted || generation != _generation || _paused) return;
    final session = _session;
    final song = _song;
    if (session == null || song == null) return;
    _advancing = true;
    try {
      while (mounted && generation == _generation && !_paused) {
        final resolved = await session.next();
        if (!mounted || generation != _generation || _paused) return;
        if (resolved == null) {
          router.prepared = null;
          state = state.copyWith(
            isPlaying: false,
            isTransitioning: false,
            error: () => session.budgetExpired && session.canContinue
                ? SourceStrings.budgetUsed
                : SourceStrings.noPlayback,
          );
          onProgress?.call(
            SourcePlaybackView(
              message: state.error!,
              details: session.summary,
              canContinue: session.canContinue && session.budgetExpired,
            ),
          );
          return;
        }
        router.prepared = resolved;
        _loading = super.playSong(song);
        await _loading;
        _loading = null;
        if (!mounted || generation != _generation || _paused) return;
        if (state.error != null || !state.isPlaying) {
          session.failed(
            resolved,
            SourceFailure('load', state.error ?? SourceStrings.loadFailed),
          );
          router.prepared = null;
          state = state.copyWith(error: () => null, isTransitioning: true);
          continue;
        }
        if (position > Duration.zero) {
          router.seekFailed = false;
          await super.seek(position);
          if (!mounted || generation != _generation || _paused) return;
        }
        _active = resolved;
        session.loaded(resolved);
        _advancing = false;
        _report();
        return;
      }
    } finally {
      if (generation == _generation) _advancing = false;
    }
  }

  Future<void> continueSources() async {
    if (_advancing || _session?.canContinue != true) return;
    _session!.renewBudget();
    _paused = false;
    state = state.copyWith(error: () => null, isTransitioning: true);
    await _advance(_generation, state.position);
  }

  @override
  Future<void> pause() async {
    if (!_multiEnabled) {
      await super.pause();
      return;
    }
    _paused = true;
    _session?.cancel();
    router.cancelMedia();
    final generation = ++_generation;
    final loading = _loading;
    _advancing = false;
    await super.pause();
    await loading;
    if (generation != _generation) return;
    if (mounted) {
      state = state.copyWith(
        isTransitioning: false,
        isPlaying: false,
        error: () => null,
      );
    }
    onProgress?.call(const SourcePlaybackView(message: SourceStrings.paused));
  }

  @override
  Future<void> togglePlay() async {
    if (_multiEnabled && (state.isPlaying || state.isTransitioning)) {
      await pause();
      return;
    }
    if (_multiEnabled && state.currentSong != null && !state.isPlaying) {
      if (_session?.canContinue == true && _session!.budgetExpired) {
        await continueSources();
        return;
      }
      await _start(state.currentSong!, state.position);
      return;
    }
    await super.togglePlay();
  }

  @override
  Future<void> switchQuality(
    AudioLevel quality, {
    bool preferHighest = false,
  }) async {
    if (!_multiEnabled) {
      await _loading;
      router.guarded = false;
      router.prepared = null;
      await super.switchQuality(quality, preferHighest: preferHighest);
      return;
    }
    final song = state.currentSong;
    if (song == null) return;
    _fixedOverride = quality;
    try {
      await _start(song, state.position);
    } finally {
      _fixedOverride = null;
    }
  }

  @override
  Future<void> clearQueue() async {
    cancelSourceAttempts();
    await super.clearQueue();
  }

  @override
  void dispose() {
    settings.removeListener(_settingsChanged);
    _unlisten();
    _session?.cancel();
    router.cancelMedia();
    _generation++;
    super.dispose();
  }
}
