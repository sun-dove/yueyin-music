import 'l10n/source_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:dio/dio.dart';

import 'core/diagnostics/diagnostics_service.dart';
import 'core/network/platform_http.dart';
import 'features/player/data/background_audio_initializer.dart';
import 'features/player/data/player_playback_memory_store.dart';
import 'features/player/presentation/providers/player_provider.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/download/presentation/providers/download_provider.dart';
import 'features/download/data/repositories/download_manager.dart';
import 'features/download/domain/entities/download_failure.dart';
import 'features/offline_cache/presentation/providers/offline_cache_provider.dart';
import 'platform/base/platform_registry.dart';
import 'platform/netease/netease_api.dart';
import 'platform/netease/netease_endpoints.dart';
import 'models/platform_type.dart';
import 'models/song.dart';
import 'l10n/video_strings.dart';
import 'video_app/data/video_auth_notifier.dart';
import 'video_app/data/video_qq_playback_api.dart';
import 'video_app/data/video_session_http.dart';
import 'video_app/custom_source/custom_source_client.dart';
import 'video_app/custom_source/custom_source_models.dart';
import 'video_app/custom_source/custom_source_playback.dart';
import 'video_app/custom_source/custom_source_storage.dart';
import 'video_app/lx_source/lx_source.dart';
import 'video_app/lx_source/lx_runtime.dart';
import 'video_app/lx_source/lx_runtime_v2.dart';
import 'video_app/multi_source/source_collection.dart';
import 'video_app/multi_source/source_coordinator.dart';
import 'video_app/multi_source/source_service.dart';
import 'video_app/multi_source/multi_source_player.dart';
import 'video_app/playback/video_platforms.dart';
import 'video_app/playback/video_stream_state.dart';
import 'video_app/video_app.dart';
import 'video_app/video_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'node-forge 1.3.1',
    ], await rootBundle.loadString('assets/lx-runtime/forge-LICENSE'));
    yield LicenseEntryWithLineBreaks([
      'pako 2.1.0',
    ], await rootBundle.loadString('assets/lx-runtime/pako-LICENSE'));
  });
  await Hive.initFlutter();
  final settings = await Hive.openBox('settings');
  final diagnostics = DiagnosticsService.instance;
  await diagnostics.initialize();
  await BackgroundAudioInitializer.initialize(diagnostics: diagnostics);
  final preferences = VideoPreferences(settings);
  await preferences.loadCustomSource();
  await preferences.loadLxSource();
  final sourceSettings = SourceSettings(preferences)..load();
  late VideoQqPlaybackApi qqApi;
  final sourceEngine = LxSourceRuntimeV2(
    qqInfoCancellable: (id, token) => qqApi.withCancellation(
      token,
      () async => (await qqApi.ensureMetadata(id))?.lxInfo ?? {},
    ),
  );
  final sourceRouter = PreparedSourceRouter(
    platformResolver: PlatformRegistry.get,
    fixedQuality: preferences.quality,
  );
  final streamInfos = <String, VideoStreamInfo>{};
  final sourceService = MultiSourceService(
    platformResolver: PlatformRegistry.get,
    engine: sourceEngine,
    officialResolve: (song, candidate, token) {
      Future<String> request() =>
          PlatformRegistry.get(song.platform)
              .getSongUrl(song.id, quality: candidate.quality);
      return song.platform == PlatformType.qq
          ? qqApi.withCancellation(token, request)
          : request();
    },
    streamInfo: (song) => streamInfos['${song.platform.name}:${song.id}'],
  );
  const customSourceCredentials = SecureCustomSourceCredentialStore();
  final customSourceDio = Dio();
  void Function(Song, CustomSourceResult)? customSourceResolved;
  final customSourceResolver = _PreferenceCustomSourceResolver(
    preferences: preferences,
    dio: customSourceDio,
    credentials: customSourceCredentials,
    lxEngine: sourceEngine,
  );
  final playbackCustomSourceFallback = CustomSourcePlaybackFallback(
    resolver: customSourceResolver,
    config: () => preferences.activeSourceConfig,
    onResolved: (song, result) => customSourceResolved?.call(song, result),
  );
  final downloadCustomSourceFallback = CustomSourcePlaybackFallback(
    resolver: customSourceResolver,
    config: () => preferences.activeSourceConfig,
  );
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => VideoAuthNotifier()),
      downloadProvider.overrideWith(
        (ref) => DownloadNotifier(
          manager: DownloadManager(
            urlResolver: (song, quality) async {
              final policy = sourceSettings.value;
              if (policy.autoSwitch || policy.sourceFirst) {
                final session = SourceSession(
                  exclusions: sourceExclusions(
                    song,
                    quality,
                    policy,
                    download: true,
                  ),
                  candidates: buildSourceCandidates(
                    song,
                    quality,
                    policy,
                    download: true,
                  ),
                  resolve: (candidate, token) => sourceService.resolve(
                    song,
                    candidate,
                    token,
                    purpose: CustomSourcePurpose.download,
                  ),
                );
                try {
                  final resolved = await session.next();
                  if (resolved != null) return resolved.url.toString();
                  throw DownloadFailure(
                    kind: session.budgetExpired
                        ? DownloadFailureKind.network
                        : DownloadFailureKind.unknown,
                    message: session.budgetExpired
                        ? SourceStrings.downloadTimeout(
                            session.remaining,
                            session.summary,
                          )
                        : SourceStrings.downloadFailed(session.summary),
                  );
                } finally {
                  session.cancel();
                }
              }
              final platform = PlatformRegistry.get(song.platform);
              try {
                return await platform.getSongUrl(song.id, quality: quality);
              } on Object catch (error) {
                final result = await downloadCustomSourceFallback.resolve(
                  song,
                  quality,
                  error,
                  purpose: CustomSourcePurpose.download,
                );
                if (result == null) rethrow;
                return result.url.toString();
              }
            },
          ),
          policy: () => ref.read(offlineCacheSettingsProvider).toQueuePolicy(),
        ),
      ),
      playerProvider.overrideWith(
        (ref) => MultiSourceVideoPlayerNotifier(
          settings: sourceSettings,
          router: sourceRouter,
          resolve: sourceService.resolve,
          onProgress: (value) =>
              ref.read(sourcePlaybackViewProvider.notifier).state = value,
          legacyFallback: playbackCustomSourceFallback,
          playbackMemoryStore: HivePlayerPlaybackMemoryStore(),
          isOfflineModeEnabled: () =>
              ref.read(offlineCacheSettingsProvider).offlineMode,
          offlineFilePathResolver: (song) =>
              ref.read(downloadProvider.notifier).localFilePathFor(song),
        ),
      ),
    ],
  );
  void onResolved(VideoStreamInfo info) {
    streamInfos['${info.platform.name}:${info.songId}'] = info;
    container
        .read(videoStreamInfoProvider.notifier)
        .update(
          (values) => {...values, '${info.platform.name}:${info.songId}': info},
        );
  }

  final auth = container.read(authProvider.notifier) as VideoAuthNotifier;
  customSourceResolved = (song, result) => container
      .read(videoStreamInfoProvider.notifier)
      .update(
        (values) => {
          ...values,
          '${song.platform.name}:${song.id}': VideoStreamInfo(
            platform: song.platform,
            songId: song.id,
            requestedQuality: preferences.quality(song.platform),
            actualQuality: result.actualQuality,
            actualFormat: result.format,
            actualBitrate: result.bitrate,
            customSourceName: result.sourceName,
          ),
        },
      );
  final qqDio = createPlatformDio(
    platform: PlatformType.qq,
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'Referer': 'https://y.qq.com/',
      'Origin': 'https://y.qq.com',
    },
  );
  final neteaseDio = createPlatformDio(
    platform: PlatformType.netease,
    baseUrl: NeteaseEndpoints.baseUrl,
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/125.0.0.0 NeteaseMusicDesktop/3.0.18.203152',
      'Referer': '${NeteaseEndpoints.baseUrl}/',
      'Origin': NeteaseEndpoints.baseUrl,
    },
  );
  attachVideoSessionGuard(qqDio, PlatformType.qq, auth);
  attachVideoSessionGuard(neteaseDio, PlatformType.netease, auth);
  qqApi = VideoQqPlaybackApi(dio: qqDio);
  PlatformRegistry.register(
    VideoQqPlatform(api: qqApi, onResolved: onResolved),
  );
  PlatformRegistry.register(
    VideoNeteasePlatform(
      api: NeteaseApi(dio: neteaseDio),
      onResolved: onResolved,
    ),
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: VideoMusicApp(
        preferences: preferences,
        customSourceCredentials: customSourceCredentials,
        customSourceDio: customSourceDio,
        sourceSettings: sourceSettings,
        sourceEngine: sourceEngine,
        onCustomSourceChanged: () {
          playbackCustomSourceFallback.cancel();
          downloadCustomSourceFallback.cancel();
        },
      ),
    ),
  );
}

class _PreferenceCustomSourceResolver implements CustomSourceResolver {
  _PreferenceCustomSourceResolver({
    required this.preferences,
    required this.dio,
    required this.credentials,
    LxSourceEngine? lxEngine,
  }) : _lxEngine = lxEngine ?? LxSourceRuntime();

  final VideoPreferences preferences;
  final Dio dio;
  final CustomSourceCredentialStore credentials;
  final LxSourceEngine _lxEngine;

  @override
  Future<CustomSourceResult> resolve(
    CustomSourceRequest request, {
    CancelToken? cancelToken,
  }) {
    final lx = preferences.lxSource;
    if (lx?.enabled == true) {
      return LxCustomSourceResolver(
        config: lx!,
        engine: _lxEngine,
      ).resolve(request, cancelToken: cancelToken);
    }
    final config = preferences.customSource;
    if (config == null) {
      throw const CustomSourceException(
        code: CustomSourceFailureCode.sourceUnavailable,
        message: VideoStrings.customSourceMissing,
        retryable: false,
      );
    }
    return HttpCustomSourceResolver(
      config: config,
      dio: dio,
      credentialStore: credentials,
    ).resolve(request, cancelToken: cancelToken);
  }
}
