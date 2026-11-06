import '../../features/player/presentation/providers/player_provider.dart';
import '../../models/audio_quality.dart';
import '../../models/platform_type.dart';
import '../../models/song.dart';
import '../../platform/base/music_platform.dart';
import '../custom_source/custom_source_playback.dart';
import 'video_platforms.dart';

/// 视频版固定使用明确选择的音质，失败时停留在当前歌曲。
class VideoPlayerNotifier extends PlayerNotifier {
  VideoPlayerNotifier({
    required MusicPlatform Function(PlatformType) platformResolver,
    required AudioLevel Function(PlatformType) requestedQuality,
    CustomSourcePlaybackFallback? customSourceFallback,
    super.audioController,
    super.audioControllerFactory,
    super.playbackMemoryStore,
    super.notificationController,
    super.keepAliveController,
    super.isSongLiked,
    super.toggleSongLike,
    super.offlineFilePathResolver,
    super.isOfflineModeEnabled,
  }) : _requestedQuality = requestedQuality,
       _customSourceFallback = customSourceFallback,
       super(
         platformResolver: (type) => VideoPlaybackPlatform(
           platformResolver(type),
           requestedQuality: () => requestedQuality(type),
           customSourceFallback: customSourceFallback,
         ),
         maxFailureChainSkips: 0,
       );

  final AudioLevel Function(PlatformType) _requestedQuality;
  final CustomSourcePlaybackFallback? _customSourceFallback;

  void selectRequestedQuality(AudioLevel quality) {
    state = state.copyWith(
      currentQuality: quality,
      qualityPreference: AudioQualityPreference.fixed,
    );
  }

  @override
  Future<void> playSong(Song song) async {
    _customSourceFallback?.cancel();
    _customSourceFallback?.registerSong(song);
    // 旧播放器在取流成功后才停旧音源，视频版切曲前先暂停，避免失败时仍播上一首。
    await super.pause();
    if (!mounted) return;
    selectRequestedQuality(_requestedQuality(song.platform));
    await super.playSong(song);
  }

  @override
  Future<void> togglePlay() async {
    final song = state.currentSong;
    if (song != null &&
        state.error != null &&
        !state.isPlaying &&
        !state.isTransitioning) {
      // 失败曲尚未装入控制器，必须重新取流，不能恢复其中保留的旧曲。
      await playSong(song);
      return;
    }
    await super.togglePlay();
  }

  Future<void> playVideoPlaylist(List<Song> songs, {int startIndex = 0}) =>
      super.playPlaylist(songs, startIndex: startIndex);
}
