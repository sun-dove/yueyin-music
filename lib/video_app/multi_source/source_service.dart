import '../../l10n/source_strings.dart';

import 'package:dio/dio.dart';

import '../../models/platform_type.dart';
import '../../models/song.dart';
import '../../platform/base/music_platform.dart';
import '../custom_source/custom_source_models.dart';
import '../lx_source/lx_source.dart';
import '../playback/video_platforms.dart';
import 'source_coordinator.dart';

class MultiSourceService {
  MultiSourceService({
    required this.platformResolver,
    required this.engine,
    this.streamInfo,
    this.officialResolve,
  });
  final MusicPlatform Function(PlatformType) platformResolver;
  final LxSourceEngine engine;
  final VideoStreamInfo? Function(Song)? streamInfo;
  final Future<String> Function(Song, SourceCandidate, CancelToken)?
  officialResolve;
  Future<ResolvedSource> resolve(
    Song song,
    SourceCandidate candidate,
    CancelToken token, {
    CustomSourcePurpose purpose = CustomSourcePurpose.play,
  }) async {
    if (token.isCancelled) throw token.cancelError!;
    final url = candidate.official
        ? await (officialResolve?.call(song, candidate, token) ??
              platformResolver(song.platform)
                  .getSongUrl(song.id, quality: candidate.quality))
        : await engine.resolve(
            candidate.entry!.config,
            CustomSourceRequest(
              requestId: '${song.platform.name}:${song.id}:${candidate.key}',
              platform: song.platform,
              song: song,
              quality: candidate.quality,
              purpose: purpose,
            ),
            cancelToken: token,
          );
    if (token.isCancelled) throw token.cancelError!;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const SourceFailure('url', SourceStrings.invalidUrl);
    }
    final info = candidate.official ? streamInfo?.call(song) : null;
    return ResolvedSource(
      candidate,
      uri,
      format: info?.actualFormat,
      bitrate: info?.actualBitrate,
    );
  }
}
