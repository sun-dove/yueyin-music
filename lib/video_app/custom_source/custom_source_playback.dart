import 'package:dio/dio.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/platform_http.dart';
import '../../models/audio_quality.dart';
import '../../models/platform_type.dart';
import '../../models/song.dart';
import 'custom_source_models.dart';

class CustomSourcePlaybackFallback {
  CustomSourcePlaybackFallback({
    required this.resolver,
    required this.config,
    this.onResolved,
  });

  final CustomSourceResolver resolver;
  final CustomSourceConfig? Function() config;
  final void Function(Song song, CustomSourceResult result)? onResolved;
  CancelToken? _activeToken;
  int _generation = 0;
  final Map<String, Song> _songs = {};

  void registerSong(Song song) =>
      _songs[_songKey(song.platform, song.id)] = song;

  Song? songFor(PlatformType platform, String songId) =>
      _songs[_songKey(platform, songId)];

  Future<CustomSourceResult?> resolve(
    Song song,
    AudioLevel quality,
    Object officialError, {
    CustomSourcePurpose purpose = CustomSourcePurpose.play,
  }) async {
    final current = config();
    if (current == null ||
        !current.enabled ||
        !current.platforms.contains(song.platform) ||
        (purpose == CustomSourcePurpose.download &&
            !current.allowForDownloads) ||
        !_allowsFallback(officialError)) {
      return null;
    }
    _activeToken?.cancel('new custom source request');
    final token = CancelToken();
    _activeToken = token;
    final generation = ++_generation;
    try {
      final request = CustomSourceRequest(
        requestId:
            '${DateTime.now().microsecondsSinceEpoch}-$generation-${song.id}',
        platform: song.platform,
        song: song,
        quality: quality,
        purpose: purpose,
      );
      final result = await Future.any<CustomSourceResult?>([
        resolver.resolve(request, cancelToken: token),
        token.whenCancel.then<CustomSourceResult?>((_) => null),
      ]);
      if (result == null) return null;
      if (generation != _generation || token.isCancelled) return null;
      onResolved?.call(song, result);
      return result;
    } on CustomSourceException catch (error) {
      if (error.code == CustomSourceFailureCode.cancelled ||
          generation != _generation ||
          token.isCancelled) {
        return null;
      }
      rethrow;
    }
  }

  void cancel() {
    _generation++;
    _activeToken?.cancel('custom source disabled');
    _activeToken = null;
  }

  bool _allowsFallback(Object error) {
    final exception = apiExceptionOf(error);
    return exception is SongNotAvailableException ||
        exception is NoVipMembershipException ||
        exception is QualityNotAvailableException;
  }

  String _songKey(PlatformType platform, String songId) =>
      '${platform.name}:$songId';
}
