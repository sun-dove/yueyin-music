import '../l10n/source_strings.dart';

import '../l10n/video_strings.dart';

import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../features/auth/presentation/pages/login_page.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../features/download/data/download_directory_service.dart';
import '../features/download/domain/entities/download_task.dart';
import '../features/download/domain/entities/download_failure.dart';
import '../features/download/presentation/providers/download_provider.dart';
import '../features/local_music/presentation/providers/local_music_provider.dart';
import '../features/offline_cache/presentation/providers/offline_cache_provider.dart';
import '../features/player/presentation/providers/lyrics_provider.dart';
import '../features/player/presentation/providers/player_provider.dart';
import '../models/audio_quality.dart';
import '../models/platform_type.dart';
import '../models/song.dart';
import 'custom_source/custom_source_client.dart';
import 'custom_source/custom_source_models.dart';
import 'custom_source/custom_source_storage.dart';
import 'data/video_auth_notifier.dart';
import 'data/video_catalog.dart';
import 'lx_source/lx_source.dart';
import 'lx_source/lx_runtime.dart';
import 'lx_source/lx_http.dart';
import 'multi_source/source_collection.dart';
import 'multi_source/multi_source_player.dart';
import 'ui/source_collection_page.dart';
import 'playback/video_stream_state.dart';
import 'ui/catalog_pages.dart';
import 'ui/custom_source_page.dart';
import 'ui/lx_source_page.dart';
import 'ui/my_page.dart';
import 'ui/player_page.dart';
import 'ui/video_shell.dart';
import 'ui/video_theme.dart';
import 'video_preferences.dart';

class VideoMusicApp extends StatefulWidget {
  const VideoMusicApp({
    super.key,
    required this.preferences,
    this.customSourceCredentials,
    this.customSourceDio,
    this.onCustomSourceChanged,
    this.sourceSettings,
    this.sourceEngine,
  });
  final VideoPreferences preferences;
  final CustomSourceCredentialStore? customSourceCredentials;
  final Dio? customSourceDio;
  final VoidCallback? onCustomSourceChanged;
  final SourceSettings? sourceSettings;
  final LxSourceEngine? sourceEngine;
  @override
  State<VideoMusicApp> createState() => _VideoMusicAppState();
}

class _VideoMusicAppState extends State<VideoMusicApp> {
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: VideoStrings.appName,
    debugShowCheckedModeBanner: false,
    theme: VideoTheme.light,
    darkTheme: VideoTheme.dark,
    themeMode: switch (widget.preferences.theme) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    },
    home: _VideoHome(
      preferences: widget.preferences,
      customSourceCredentials:
          widget.customSourceCredentials ??
          const SecureCustomSourceCredentialStore(),
      customSourceDio: widget.customSourceDio ?? Dio(),
      onCustomSourceChanged: widget.onCustomSourceChanged,
      sourceSettings: widget.sourceSettings,
      sourceEngine: widget.sourceEngine,
      onThemeChanged: () => setState(() {}),
    ),
  );
}

class _VideoHome extends ConsumerStatefulWidget {
  const _VideoHome({
    required this.preferences,
    required this.customSourceCredentials,
    required this.customSourceDio,
    this.onCustomSourceChanged,
    required this.onThemeChanged,
    this.sourceSettings,
    this.sourceEngine,
  });
  final VideoPreferences preferences;
  final CustomSourceCredentialStore customSourceCredentials;
  final Dio customSourceDio;
  final VoidCallback? onCustomSourceChanged;
  final VoidCallback onThemeChanged;
  final SourceSettings? sourceSettings;
  final LxSourceEngine? sourceEngine;
  @override
  ConsumerState<_VideoHome> createState() => _VideoHomeState();
}

class _VideoHomeState extends ConsumerState<_VideoHome>
    with WidgetsBindingObserver {
  final _catalog = VideoCatalog();
  final _query = LatestVideoQuery<VideoPage>();
  final _search = TextEditingController();
  final _libraries = <PlatformType, VideoLibrary>{};
  final _syncing = <PlatformType>{};
  final _libraryEpoch = <PlatformType, int>{};
  final _pendingLikes = <String>{};
  var _result = const VideoCatalogViewState();
  var _searchPlatform = PlatformType.qq;
  var _index = 3;
  var _page = 0;
  var _submitted = false;
  var _localReady = false;
  var _committedQuery = '';
  var _hotTerms = <String>[];
  final _totals = <PlatformType, int?>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    unawaited(_loadHotTerms());
    unawaited(_initializeLocal());
    await ref.read(authProvider.notifier).init();
    if (!mounted) return;
    for (final platform in [PlatformType.qq, PlatformType.netease]) {
      if (ref.read(authProvider).isLoggedIn(platform)) {
        unawaited(_sync(platform));
      }
    }
    await ref.read(offlineCacheSettingsProvider.notifier).ready;
    if (!mounted) return;
    if (widget.preferences.box.get('video.cacheInitialized') != true) {
      await ref
          .read(offlineCacheSettingsProvider.notifier)
          .setSizeLimitMb(10240);
      await widget.preferences.box.put('video.cacheInitialized', true);
    }
    await ref.read(downloadProvider.notifier).ready;
    if (!mounted) return;
    unawaited(ref.read(downloadProvider.notifier).refreshCacheUsage());
  }

  Future<void> _loadHotTerms() async {
    try {
      final words = await _catalog.hotSearch();
      if (mounted) setState(() => _hotTerms = words);
    } catch (_) {
      /* 热搜失败仍可手动输入并搜索。 */
    }
  }

  Future<void> _initializeLocal() async {
    await ref.read(localMusicProvider.notifier).initialize();
    if (mounted) setState(() => _localReady = true);
  }

  @override
  void dispose() {
    _query.invalidate();
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(ref.read(playerProvider.notifier).flushPlaybackMemory());
      unawaited(ref.read(playerProvider.notifier).reassertBackgroundPlayback());
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runSearch(String text, {bool more = false}) async {
    final keyword = more ? _committedQuery : text.trim();
    if (!more) {
      _query.invalidate();
      _page = 0;
      _committedQuery = keyword;
      setState(() {
        _submitted = keyword.isNotEmpty;
        _totals.clear();
        _result = VideoCatalogViewState(loading: keyword.isNotEmpty);
      });
    } else {
      if (_result.loading || _result.loadingMore || !_result.hasMore) return;
      setState(
        () => _result = VideoCatalogViewState(
          songs: _result.songs,
          total: _result.total,
          hasMore: true,
          loadingMore: true,
        ),
      );
    }
    if (keyword.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final platform = _searchPlatform;
    final requestedPage = _page + 1;
    try {
      final response = await _query.run(() async {
        if (platform == PlatformType.local) {
          await ref.read(localMusicProvider.notifier).initialize();
          final words = keyword.toLowerCase();
          final songs = ref
              .read(localMusicProvider)
              .songs
              .where(
                (s) => '${s.name} ${s.artistNames} ${s.album?.name ?? ''}'
                    .toLowerCase()
                    .contains(words),
              )
              .toList();
          return VideoPage(
            songs: songs,
            total: songs.length,
            page: 1,
            hasMore: false,
          );
        }
        return _catalog.search(platform, keyword, page: requestedPage);
      });
      if (!mounted || response == null) return;
      final songs = <String, Song>{
        for (final song in more ? _result.songs : <Song>[])
          videoSongKey(song): song,
        for (final song in response.songs) videoSongKey(song): song,
      };
      setState(() {
        _page = response.page;
        _totals[platform] = response.total;
        _result = VideoCatalogViewState(
          songs: songs.values.toList(),
          total: response.total,
          hasMore: response.hasMore,
        );
      });
    } catch (error) {
      if (!mounted) return;
      final failure = VideoFailure.from(error);
      setState(
        () => _result = VideoCatalogViewState(
          songs: more ? _result.songs : const [],
          total: _result.total,
          hasMore: more,
          error: failure.message,
          canRetry: failure.canRetry,
        ),
      );
      if (failure.kind == VideoFailureKind.sessionExpired) {
        await ref.read(authProvider.notifier).handleSessionExpired(platform);
      }
    }
  }

  Future<void> _sync(PlatformType platform) async {
    final user = ref.read(authProvider).userFor(platform);
    if (user == null || _syncing.contains(platform)) return;
    final authEpoch = _authEpoch(platform);
    final epoch = (_libraryEpoch[platform] ?? 0) + 1;
    _libraryEpoch[platform] = epoch;
    bool isCurrent() =>
        mounted &&
        _libraryEpoch[platform] == epoch &&
        _authEpoch(platform) == authEpoch &&
        ref.read(authProvider).userFor(platform)?.id == user.id;
    setState(() => _syncing.add(platform));
    void update(VideoLibrary value) {
      if (!isCurrent()) return;
      setState(() => _libraries[platform] = value);
      ref
          .read(playerProvider.notifier)
          .updateLikedSongs(
            _libraries.values.expand((lib) => lib.songs).toList(),
          );
    }

    try {
      final library = await _catalog.syncLikes(
        platform,
        userId: user.id,
        onProgress: update,
      );
      update(library);
      if (isCurrent() &&
          library.error?.kind == VideoFailureKind.sessionExpired) {
        await ref.read(authProvider.notifier).handleSessionExpired(platform);
      }
    } finally {
      if (isCurrent()) setState(() => _syncing.remove(platform));
    }
  }

  Future<void> _account(PlatformType platform) async {
    final user = ref.read(authProvider).userFor(platform);
    if (user == null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => LoginPage(platform: platform)),
      );
      if (mounted && ref.read(authProvider).isLoggedIn(platform)) {
        await _sync(platform);
      }
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(user.nickname),
              subtitle: Text(videoPlatformLabel(platform)),
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text(VideoStrings.resyncLikes),
              onTap: () {
                Navigator.pop(sheet);
                unawaited(_sync(platform));
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text(VideoStrings.logout),
              onTap: () async {
                Navigator.pop(sheet);
                _libraryEpoch[platform] = (_libraryEpoch[platform] ?? 0) + 1;
                _syncing.remove(platform);
                await ref.read(authProvider.notifier).logout(platform);
                if (mounted) {
                  setState(() => _libraries.remove(platform));
                  _pushLikes();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleLike(Song song) async {
    if (song.platform == PlatformType.local) {
      _notice(VideoStrings.localLikeAtSource);
      return;
    }
    if (!ref.read(authProvider).isLoggedIn(song.platform)) {
      await _account(song.platform);
      return;
    }
    final key = videoSongKey(song);
    if (_syncing.contains(song.platform)) {
      _notice(VideoStrings.syncingPleaseWait);
      return;
    }
    final userId = ref.read(authProvider).userFor(song.platform)?.id;
    final authEpoch = _authEpoch(song.platform);
    final epoch = _libraryEpoch[song.platform];
    bool isCurrent() =>
        mounted &&
        ref.read(authProvider).userFor(song.platform)?.id == userId &&
        _authEpoch(song.platform) == authEpoch &&
        _libraryEpoch[song.platform] == epoch;
    if (!_pendingLikes.add(key)) return;
    final existing = _libraries[song.platform] ?? const VideoLibrary();
    final liked = existing.songs.any((s) => videoSongKey(s) == key);
    try {
      await _catalog.setLiked(song, !liked);
      if (!isCurrent()) return;
      final latest = _libraries[song.platform] ?? const VideoLibrary();
      final songs = [...latest.songs]
        ..removeWhere((s) => videoSongKey(s) == key);
      if (!liked) songs.insert(0, song);
      setState(
        () => _libraries[song.platform] = VideoLibrary(
          songs: songs,
          total: latest.total == null ? null : latest.total! + (liked ? -1 : 1),
          complete: latest.complete,
          error: latest.error,
        ),
      );
      ref
          .read(playerProvider.notifier)
          .updateLikedSongs(
            _libraries.values.expand((lib) => lib.songs).toList(),
          );
      _notice(liked ? VideoStrings.unliked : VideoStrings.liked);
    } catch (error) {
      if (isCurrent()) _notice(VideoFailure.from(error).message);
    } finally {
      _pendingLikes.remove(key);
    }
  }

  int? _authEpoch(PlatformType platform) {
    final notifier = ref.read(authProvider.notifier);
    return notifier is VideoAuthNotifier
        ? notifier.sessionEpoch(platform)
        : null;
  }

  void _pushLikes() => ref
      .read(playerProvider.notifier)
      .updateLikedSongs(_libraries.values.expand((lib) => lib.songs).toList());

  void _retrySearch() => unawaited(
    _runSearch(_committedQuery, more: _page > 0 && _result.hasMore),
  );

  Future<void> _play(Song song, List<Song> songs) async {
    _openPlayer();
    await ref
        .read(playerProvider.notifier)
        .playPlaylist(
          songs,
          startIndex: songs.indexOf(song).clamp(0, songs.length - 1),
        );
  }

  void _openPlayer() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Consumer(
          builder: (context, ref, _) {
            final player = ref.watch(playerProvider);
            final song = player.currentSong;
            if (song == null) {
              return Scaffold(
                appBar: AppBar(),
                body: const Center(child: Text(VideoStrings.chooseSong)),
              );
            }
            final lyrics = ref.watch(lyricsProvider);
            final info = ref.watch(videoStreamInfoProvider)[videoSongKey(song)];
            final notifier = ref.read(playerProvider.notifier);
            final source = ref.watch(sourcePlaybackViewProvider);
            return VideoPlayerPage(
              song: song,
              position: player.position,
              duration: player.duration,
              isPlaying: player.isPlaying,
              isLoading: player.isTransitioning,
              error: player.error,
              sourceStatus: source.message.isEmpty
                  ? null
                  : _sourceStatus(context, source, notifier),
              qualityLabel: song.platform == PlatformType.local
                  ? VideoStrings.localAudio
                  : source.message.isNotEmpty
                  ? SourceStrings.qualityAbove
                  : player.error != null
                  ? VideoStrings.requestedQuality(
                      widget.preferences
                          .quality(song.platform)
                          .displayNameFor(song.platform),
                    )
                  : videoStreamLabel(info),
              isPreview: source.message.isEmpty && info?.isPreview == true,
              lyrics: lyrics.asData?.value?.lines ?? const [],
              lyricsLoading: lyrics.isLoading,
              lyricsError: lyrics.hasError ? VideoStrings.lyricsRetry : null,
              modeLabel: _modeLabel(player),
              onToggle: notifier.togglePlay,
              onPrevious: notifier.skipToPrevious,
              onNext: notifier.skipToNext,
              onSeek: notifier.seek,
              onQueue: _queue,
              onMode: _mode,
              onQuality: () => _quality(song.platform, false),
            );
          },
        ),
      ),
    );
  }

  Widget _sourceStatus(
    BuildContext context,
    SourcePlaybackView source,
    PlayerNotifier notifier,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          source.message,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            if (source.details.isNotEmpty)
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: const Text(SourceStrings.attemptDetails),
                    content: SingleChildScrollView(child: Text(source.details)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text(SourceStrings.close),
                      ),
                    ],
                  ),
                ),
                child: const Text(SourceStrings.details),
              ),
            if (source.canContinue &&
                notifier is MultiSourceVideoPlayerNotifier)
              TextButton(
                onPressed: source.busy ? null : notifier.continueSources,
                child: const Text(SourceStrings.continueSources),
              ),
          ],
        ),
      ],
    ),
  );

  String _modeLabel(PlayerState player) => player.isShuffle
      ? VideoStrings.shuffle
      : switch (player.repeatMode) {
          RepeatMode.off => VideoStrings.sequential,
          RepeatMode.all => VideoStrings.repeatAll,
          RepeatMode.one => VideoStrings.repeatOne,
        };
  void _mode() {
    final player = ref.read(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    if (player.isShuffle) {
      notifier.toggleShuffle();
    } else if (player.repeatMode == RepeatMode.one) {
      notifier.cycleRepeatMode();
      notifier.toggleShuffle();
    } else {
      notifier.cycleRepeatMode();
    }
  }

  void _queue() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final player = ref.watch(playerProvider);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .65,
            child: Column(
              children: [
                ListTile(
                  title: Text(VideoStrings.queueCount(player.playlist.length)),
                  trailing: TextButton(
                    onPressed: player.playlist.isEmpty
                        ? null
                        : () => ref.read(playerProvider.notifier).clearQueue(),
                    child: const Text(VideoStrings.clear),
                  ),
                ),
                Expanded(
                  child: player.playlist.isEmpty
                      ? const Center(child: Text(VideoStrings.emptyQueue))
                      : ReorderableListView.builder(
                          itemCount: player.playlist.length,
                          onReorderItem: (from, to) => ref
                              .read(playerProvider.notifier)
                              .moveInQueue(from, to),
                          itemBuilder: (context, index) {
                            final song = player.playlist[index];
                            return ListTile(
                              key: ValueKey('$index:${videoSongKey(song)}'),
                              selected: index == player.currentIndex,
                              title: Text(
                                song.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(song.artistNames, maxLines: 1),
                              onTap: () => ref
                                  .read(playerProvider.notifier)
                                  .playAtIndex(index),
                              trailing: IconButton(
                                tooltip: VideoStrings.removeFromQueue,
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => ref
                                    .read(playerProvider.notifier)
                                    .removeFromQueue(song.dedupeKey),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Future<void> _quality(PlatformType platform, bool download) async {
    if (platform == PlatformType.local) return;
    var highest = false;
    final selected = await showModalBottomSheet<AudioLevel>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                VideoStrings.qualityPickerTitle(
                  videoPlatformLabel(platform),
                  download,
                ),
              ),
              subtitle: const Text(VideoStrings.qualityPermissions),
            ),
            if (!download && widget.sourceSettings != null)
              ListTile(
                title: const Text(SourceStrings.highest),
                subtitle: const Text(SourceStrings.highestHint),
                trailing: widget.sourceSettings!.value.highestQuality
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  highest = true;
                  Navigator.pop(context);
                },
              ),
            for (final level in [
              AudioLevel.low,
              AudioLevel.high,
              AudioLevel.lossless,
              AudioLevel.hires,
              AudioLevel.master,
            ])
              ListTile(
                title: Text(level.displayNameFor(platform)),
                trailing:
                    (download ||
                            widget.sourceSettings?.value.highestQuality !=
                                true) &&
                        widget.preferences.quality(
                              platform,
                              download: download,
                            ) ==
                            level
                    ? const Icon(Icons.check, color: VideoTheme.primary)
                    : null,
                onTap: () => Navigator.pop(context, level),
              ),
          ],
        ),
      ),
    );
    if (selected == null && !highest) return;
    final settings = widget.sourceSettings;
    if (!download && settings != null) {
      await settings.save(settings.value.copyWith(highestQuality: highest));
    }
    if (selected != null) {
      await widget.preferences.setQuality(
        platform,
        selected,
        download: download,
      );
    }
    if (!mounted) return;
    setState(() {});
    if (!download &&
        ref.read(playerProvider).currentSong?.platform == platform) {
      await ref
          .read(playerProvider.notifier)
          .switchQuality(selected ?? widget.preferences.quality(platform));
    }
  }

  Future<void> _download(List<Song> songs) async {
    if (songs.isEmpty) return;
    final notifier = ref.read(downloadProvider.notifier);
    for (final song in songs) {
      await notifier.startDownload(
        song,
        widget.preferences.quality(song.platform, download: true),
      );
    }
    _notice(VideoStrings.downloadsSubmitted(songs.length));
  }

  void _songMore(Song song) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(song.name), subtitle: Text(song.artistNames)),
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: const Text(VideoStrings.toggleLike),
            onTap: () {
              Navigator.pop(sheet);
              unawaited(_toggleLike(song));
            },
          ),
          if (song.platform != PlatformType.local)
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text(VideoStrings.downloadSong),
              onTap: () {
                Navigator.pop(sheet);
                unawaited(_download([song]));
              },
            ),
        ],
      ),
    ),
  );

  void _downloads() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(downloadProvider);
          final notifier = ref.read(downloadProvider.notifier);
          return Scaffold(
            appBar: AppBar(title: const Text(VideoStrings.downloadManagement)),
            body: state.tasks.isEmpty
                ? const Center(child: Text(VideoStrings.noDownloads))
                : ListView(
                    children: [
                      if (state.queueBlockedReason != null)
                        ListTile(title: Text(state.queueBlockedReason!)),
                      for (final task in state.tasks.reversed)
                        ListTile(
                          title: Text(task.song.name),
                          onTap: task.status == DownloadStatus.completed
                              ? () => _playDownload(task)
                              : null,
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task.error ??
                                    switch (task.status) {
                                      DownloadStatus.waiting =>
                                        VideoStrings.waitingDownload,
                                      DownloadStatus.downloading =>
                                        VideoStrings.downloadProgress(
                                          (task.progress * 100).toStringAsFixed(
                                            0,
                                          ),
                                        ),
                                      DownloadStatus.paused =>
                                        VideoStrings.paused,
                                      DownloadStatus.completed =>
                                        VideoStrings.downloadedPath(
                                          task.filePath,
                                        ),
                                      DownloadStatus.failed =>
                                        VideoStrings.downloadFailed,
                                    },
                                style: const TextStyle(fontSize: 11),
                              ),
                              if (task.status == DownloadStatus.downloading)
                                LinearProgressIndicator(value: task.progress),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (task.status == DownloadStatus.downloading)
                                IconButton(
                                  tooltip: VideoStrings.pauseDownload,
                                  icon: const Icon(Icons.pause),
                                  onPressed: () =>
                                      notifier.pauseDownload(task.id),
                                ),
                              if (task.status == DownloadStatus.failed ||
                                  task.status == DownloadStatus.paused)
                                IconButton(
                                  tooltip: task.status == DownloadStatus.paused
                                      ? VideoStrings.resumeDownload
                                      : _downloadActionLabel(task),
                                  icon: const Icon(Icons.refresh),
                                  onPressed:
                                      task.status == DownloadStatus.paused
                                      ? () => notifier.resumeDownload(task.id)
                                      : _canActOnDownload(task)
                                      ? () => _resolveDownload(task)
                                      : null,
                                ),
                              if (task.status != DownloadStatus.completed)
                                IconButton(
                                  tooltip: VideoStrings.cancelDownload,
                                  icon: const Icon(Icons.close),
                                  onPressed: () =>
                                      notifier.cancelDownload(task.id),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
          );
        },
      ),
    ),
  );
  Future<void> _playDownload(DownloadTask task) async {
    final path = await ref
        .read(downloadProvider.notifier)
        .localFilePathFor(task.song, quality: task.quality);
    if (!mounted) return;
    if (path == null) {
      _notice(VideoStrings.downloadMissing);
      return;
    }
    final song = task.song;
    final local = Song(
      id: path,
      platform: PlatformType.local,
      name: song.name,
      artists: song.artists,
      album: song.album,
      duration: song.duration,
      coverUrl: song.coverUrl,
    );
    await _play(local, [local]);
  }

  bool _canActOnDownload(DownloadTask task) => ![
    DownloadFailureKind.notFound,
    DownloadFailureKind.unsupported,
    DownloadFailureKind.cancelled,
    DownloadFailureKind.unknown,
  ].contains(task.failureKind);
  String _downloadActionLabel(DownloadTask task) => switch (task.failureKind) {
    DownloadFailureKind.auth => VideoStrings.loginAgain,
    DownloadFailureKind.vip => VideoStrings.chooseDownloadQuality,
    DownloadFailureKind.storagePermission => VideoStrings.chooseStorageAgain,
    DownloadFailureKind.disk => VideoStrings.freeStorageRetry,
    DownloadFailureKind.notFound ||
    DownloadFailureKind.unsupported => VideoStrings.resourceCannotDownload,
    DownloadFailureKind.unknown ||
    DownloadFailureKind.cancelled => VideoStrings.taskCannotRetry,
    _ => VideoStrings.retryDownload,
  };
  Future<void> _resolveDownload(DownloadTask task) async {
    switch (task.failureKind) {
      case DownloadFailureKind.auth:
        await _account(task.song.platform);
      case DownloadFailureKind.vip:
        await _quality(task.song.platform, true);
      case DownloadFailureKind.storagePermission:
        await _directory();
      case DownloadFailureKind.disk:
        _notice(VideoStrings.freeDeviceSpace);
        await ref.read(downloadProvider.notifier).resumeDownload(task.id);
      default:
        await ref.read(downloadProvider.notifier).resumeDownload(task.id);
    }
  }

  Future<void> _directory() async {
    final result = await DownloadDirectoryService().applySafTreeDirectory();
    if (!result.isCancelled) _notice(result.message);
  }

  void _cache() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final settings = ref.watch(offlineCacheSettingsProvider);
        final notifier = ref.read(offlineCacheSettingsProvider.notifier);
        final download = ref.watch(downloadProvider);
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text(VideoStrings.cacheManagement),
                  subtitle: Text(
                    '${_mb(download.estimatedOfflineCacheBytes)} / ${settings.sizeLimitMb} MB',
                  ),
                ),
                ListTile(
                  title: const Text(VideoStrings.cacheLimit),
                  trailing: DropdownButton<int>(
                    value: settings.sizeLimitMb,
                    items: {1024, 5120, 10240, 20480, settings.sizeLimitMb}
                        .map(
                          (size) => DropdownMenuItem(
                            value: size,
                            child: Text('$size MB'),
                          ),
                        )
                        .toList(),
                    onChanged: (size) {
                      if (size != null) {
                        unawaited(notifier.setSizeLimitMb(size));
                      }
                    },
                  ),
                ),
                SwitchListTile(
                  title: const Text(VideoStrings.wifiCacheOnly),
                  value: settings.wifiOnly,
                  onChanged: notifier.setWifiOnly,
                ),
                SwitchListTile(
                  title: const Text(VideoStrings.autoRetry),
                  value: settings.autoRetry,
                  onChanged: notifier.setAutoRetry,
                ),
                SwitchListTile(
                  title: const Text(VideoStrings.autoCleanup),
                  value: settings.autoCleanup,
                  onChanged: notifier.setAutoCleanup,
                ),
                SwitchListTile(
                  title: const Text(VideoStrings.offlineMode),
                  subtitle: const Text(VideoStrings.useCachedFiles),
                  value: settings.offlineMode,
                  onChanged: notifier.setOfflineMode,
                ),
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text(VideoStrings.cacheSyncedLikes),
                  onTap: () async {
                    final songs = _libraries.values
                        .expand((lib) => lib.songs)
                        .toList();
                    for (final platform in [
                      PlatformType.qq,
                      PlatformType.netease,
                    ]) {
                      await ref
                          .read(downloadProvider.notifier)
                          .cacheSongs(
                            songs
                                .where((song) => song.platform == platform)
                                .toList(),
                            quality: widget.preferences.quality(platform),
                          );
                    }
                    if (context.mounted) Navigator.pop(context);
                    _notice(
                      songs.isEmpty
                          ? VideoStrings.loginSyncFirst
                          : VideoStrings.cacheSubmitted,
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text(VideoStrings.cleanupToLimit),
                  onTap: () async {
                    final count = await ref
                        .read(downloadProvider.notifier)
                        .cleanupOfflineCache();
                    _notice(VideoStrings.cleanedCache(count));
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  Future<void> _theme() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in {
              'light': VideoStrings.lightTheme,
              'dark': VideoStrings.darkTheme,
              'system': VideoStrings.systemTheme,
            }.entries)
              ListTile(
                title: Text(entry.value),
                trailing: widget.preferences.theme == entry.key
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
    );
    if (value != null) {
      await widget.preferences.setTheme(value);
      widget.onThemeChanged();
    }
  }

  String get _customSourceLabel {
    final collection = widget.sourceSettings?.value;
    if (collection != null && collection.entries.isNotEmpty) {
      return SourceStrings.sourceCount(
        collection.entries.length,
        collection.enabled.length,
      );
    }
    final lx = widget.preferences.lxSource;
    if (lx?.enabled == true) return VideoStrings.customSourceEnabled(lx!.name);
    final config = widget.preferences.customSource;
    if (config == null) {
      return lx == null
          ? VideoStrings.customSourceNotConfigured
          : VideoStrings.customSourceDisabled;
    }
    return config.enabled
        ? VideoStrings.customSourceEnabled(config.name)
        : VideoStrings.customSourceDisabled;
  }

  Future<VideoCustomSourceTestResult> _testCustomSource(
    VideoCustomSourceDraft draft,
  ) async {
    try {
      final config = _configFromDraft(draft, enabled: true);
      config.validate();
      final testCredentials = MemoryCustomSourceCredentialStore({
        if (draft.token.trim().isNotEmpty)
          config.credentialRef!: draft.token.trim(),
      });
      final requestPlatform = config.platforms.first;
      await HttpCustomSourceResolver(
        config: config,
        dio: widget.customSourceDio,
        credentialStore: testCredentials,
      ).resolve(
        CustomSourceRequest(
          requestId: 'connection-test',
          platform: requestPlatform,
          song: Song(
            id: 'connection-test',
            platform: requestPlatform,
            name: VideoStrings.customSourceConnectionTest,
            artists: const [],
          ),
          quality: AudioLevel.low,
          purpose: CustomSourcePurpose.play,
        ),
      );
      return const VideoCustomSourceTestResult.success();
    } on CustomSourceException catch (error) {
      return switch (error.code) {
        CustomSourceFailureCode.unauthorized =>
          const VideoCustomSourceTestResult.unauthorized(),
        CustomSourceFailureCode.timeout =>
          const VideoCustomSourceTestResult.timeout(),
        CustomSourceFailureCode.invalidResponse ||
        CustomSourceFailureCode.qualityUnavailable =>
          const VideoCustomSourceTestResult.incompatible(),
        _ => const VideoCustomSourceTestResult.unavailable(),
      };
    } on Object {
      return const VideoCustomSourceTestResult.incompatible();
    }
  }

  CustomSourceConfig _configFromDraft(
    VideoCustomSourceDraft draft, {
    bool? enabled,
  }) {
    final current = widget.preferences.customSource;
    final id = current?.id ?? 'primary';
    return CustomSourceConfig(
      id: id,
      name: draft.name,
      endpoint: Uri.parse(draft.endpoint),
      enabled: enabled ?? draft.enabled,
      platforms: draft.platforms,
      timeoutSeconds: draft.timeoutSeconds,
      allowForDownloads: draft.allowForDownloads,
      credentialRef: id,
    );
  }

  Future<void> _customSource() async {
    if (widget.sourceSettings != null && widget.sourceEngine != null) {
      await _sourceCollection();
      return;
    }
    final engine = LxSourceRuntime();
    final importerDio = createLxDio();
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => VideoLxSourcePage(
            initial: widget.preferences.lxSource,
            onImport: (link, token) => LxSourceImporter(
              dio: importerDio,
              engine: engine,
            ).importLink(link, cancelToken: token),
            onTest: (source) async {
              await engine.inspect(source.script);
            },
            onSave: (source) async {
              widget.onCustomSourceChanged?.call();
              if (source.enabled &&
                  widget.preferences.customSource?.enabled == true) {
                await widget.preferences.setCustomSource(
                  widget.preferences.customSource!.copyWith(enabled: false),
                );
              }
              await widget.preferences.setLxSource(source);
              if (mounted) {
                setState(() {});
                Navigator.pop(context);
              }
            },
            onDelete: widget.preferences.lxSource == null
                ? null
                : () async {
                    widget.onCustomSourceChanged?.call();
                    await widget.preferences.deleteLxSource();
                    if (mounted) {
                      setState(() {});
                      Navigator.pop(context);
                    }
                  },
            onHttp: () async {
              Navigator.pop(context);
              await _httpCustomSource();
            },
          ),
        ),
      );
    } finally {
      importerDio.close(force: true);
      engine.dio.close(force: true);
    }
  }

  Future<void> _sourceCollection() async {
    final settings = widget.sourceSettings!;
    final engine = widget.sourceEngine!;
    final dio = createLxDio();
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => SourceCollectionPage(
            initial: settings.value,
            warning: settings.loadError,
            onImport: (link, token) => LxSourceImporter(
              dio: dio,
              engine: engine,
            ).importLink(link, cancelToken: token),
            onInspect: (config, token) async {
              await engine.inspect(config.script, cancelToken: token);
            },
            onSave: (value) async {
              await settings.save(value);
              widget.onCustomSourceChanged?.call();
              if (mounted) {
                setState(() {});
                Navigator.pop(context);
              }
            },
            onHttp: () {
              Navigator.pop(context);
              unawaited(_httpCustomSource());
            },
          ),
        ),
      );
    } finally {
      dio.close(force: true);
    }
  }

  Future<void> _httpCustomSource() async {
    final current = widget.preferences.customSource;
    final token = current == null
        ? ''
        : await widget.customSourceCredentials.readToken(
                current.credentialRef ?? current.id,
              ) ??
              '';
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => VideoCustomSourcePage(
          initialDraft: current == null
              ? const VideoCustomSourceDraft()
              : VideoCustomSourceDraft(
                  name: current.name,
                  endpoint: current.endpoint.toString(),
                  platforms: current.platforms,
                  timeoutSeconds: current.timeoutSeconds,
                  token: token,
                  allowForDownloads: current.allowForDownloads,
                  enabled: current.enabled,
                ),
          onTest: _testCustomSource,
          onSave: (draft) async {
            try {
              final config = _configFromDraft(draft);
              config.validate();
              final sources = widget.sourceSettings;
              if (config.enabled && sources != null) {
                await sources.save(
                  sources.value.copyWith(
                    autoSwitch: false,
                    highestQuality: false,
                    sourceFirst: false,
                    entries: [
                      for (final e in sources.value.entries)
                        SourceEntry(e.id, e.config.copyWith(enabled: false)),
                    ],
                  ),
                );
              }
              if (config.enabled &&
                  widget.preferences.lxSource?.enabled == true) {
                await widget.preferences.setLxSource(
                  widget.preferences.lxSource!.copyWith(enabled: false),
                );
              }
              await widget.preferences.setCustomSource(config);
              widget.onCustomSourceChanged?.call();
              if (draft.token.trim().isEmpty) {
                await widget.customSourceCredentials.deleteToken(config.id);
              } else {
                await widget.customSourceCredentials.writeToken(
                  config.id,
                  draft.token,
                );
              }
              if (mounted) {
                setState(() {});
                Navigator.pop(context);
              }
            } on CustomSourceConfigurationException catch (error) {
              _notice(error.message);
            }
          },
          onDelete: current == null
              ? null
              : () async {
                  await widget.customSourceCredentials.deleteToken(
                    current.credentialRef ?? current.id,
                  );
                  await widget.preferences.deleteCustomSource();
                  widget.onCustomSourceChanged?.call();
                  if (mounted) {
                    setState(() {});
                    Navigator.pop(context);
                  }
                },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _local() async {
    await ref.read(localMusicProvider.notifier).pickAndScanDirectory();
    if (!mounted) return;
    final local = ref.read(localMusicProvider);
    _notice(local.error ?? VideoStrings.loadedLocalSongs(local.songs.length));
    setState(() {
      _index = 0;
      _searchPlatform = PlatformType.local;
    });
    if (_search.text.trim().isNotEmpty) unawaited(_runSearch(_search.text));
  }

  String _mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final player = ref.watch(playerProvider);
    final downloads = ref.watch(downloadProvider);
    final cache = ref.watch(offlineCacheSettingsProvider);
    ref.listen(authProvider, (previous, next) {
      if (next.expiredPlatform != null &&
          previous?.expiryNoticeId != next.expiryNoticeId) {
        final platform = next.expiredPlatform!;
        _libraryEpoch[platform] = (_libraryEpoch[platform] ?? 0) + 1;
        setState(() => _libraries.remove(platform));
        _syncing.remove(platform);
        _pushLikes();
        _notice(VideoStrings.expiredPlatform(videoPlatformLabel(platform)));
      }
    });
    final liked = _libraries.values
        .expand((lib) => lib.songs)
        .map(videoSongKey)
        .toSet();
    VideoCatalogViewState libraryState(PlatformType platform) {
      final library = _libraries[platform] ?? const VideoLibrary();
      return VideoCatalogViewState(
        songs: library.songs,
        total: library.total,
        loading: _syncing.contains(platform),
        error: library.error?.message,
        canRetry: library.error?.canRetry ?? true,
      );
    }

    return VideoShell(
      index: _index,
      onSelect: (index) => setState(() => _index = index),
      pages: [
        VideoSearchPage(
          controller: _search,
          onSearch: (text) => _runSearch(text),
          platform: _searchPlatform,
          onPlatformChanged: (platform) {
            setState(() => _searchPlatform = platform);
            unawaited(_runSearch(_committedQuery));
          },
          result: _result,
          submitted: _submitted,
          hotTerms: _hotTerms,
          totals: _totals,
          onRetry: _retrySearch,
          onRefresh: () => _runSearch(_committedQuery),
          onLoadMore: () => _runSearch(_committedQuery, more: true),
          onSongTap: (song) => _play(song, _result.songs),
          onSongLike: _toggleLike,
          onSongMore: _songMore,
          likedKeys: liked,
          currentSong: player.currentSong,
        ),
        for (final platform in [PlatformType.qq, PlatformType.netease])
          VideoLibraryPage(
            platform: platform,
            result: libraryState(platform),
            loggedIn: auth.isLoggedIn(platform),
            onLogin: () => _account(platform),
            onRefresh: () => _sync(platform),
            onRetry: () => _sync(platform),
            onPlayAll: () {
              final songs = _libraries[platform]?.songs ?? [];
              if (songs.isNotEmpty) unawaited(_play(songs.first, songs));
            },
            onDownloadAll: () => _download(_libraries[platform]?.songs ?? []),
            onSongTap: (song) =>
                _play(song, _libraries[platform]?.songs ?? [song]),
            onSongLike: _toggleLike,
            onSongMore: _songMore,
            likedKeys: liked,
            currentSong: player.currentSong,
            syncComplete: _libraries[platform]?.complete ?? false,
          ),
        VideoMyPage(
          localSongCount: _localReady
              ? ref.watch(localMusicProvider).songs.length
              : null,
          accounts: {
            for (final platform in [PlatformType.qq, PlatformType.netease])
              if (auth.userFor(platform) case final user?)
                platform: VideoAccountSummary(
                  nickname: user.nickname,
                  avatarUrl: user.avatarUrl,
                  loaded: _libraries[platform]?.loaded ?? 0,
                  total: _libraries[platform]?.total,
                  complete: _libraries[platform]?.complete ?? false,
                ),
          },
          cacheLabel:
              '${_mb(downloads.estimatedOfflineCacheBytes)} / ${cache.sizeLimitMb} MB',
          downloadLabel: VideoStrings.taskCount(downloads.tasks.length),
          themeLabel: switch (widget.preferences.theme) {
            'dark' => VideoStrings.darkTheme,
            'system' => VideoStrings.systemTheme,
            _ => VideoStrings.lightTheme,
          },
          qualityLabels: {
            for (final platform in [PlatformType.qq, PlatformType.netease]) ...{
              '${platform.name}:play':
                  widget.sourceSettings?.value.highestQuality == true
                  ? SourceStrings.highest
                  : widget.preferences
                        .quality(platform)
                        .displayNameFor(platform),
              '${platform.name}:download': widget.preferences
                  .quality(platform, download: true)
                  .displayNameFor(platform),
            },
          },
          customSourceLabel: _customSourceLabel,
          onAccount: _account,
          onQuality: _quality,
          onCache: _cache,
          onDownloads: _downloads,
          onDirectory: _directory,
          onTheme: _theme,
          onLocal: _local,
          onCustomSource: _customSource,
        ),
      ],
      miniPlayer: VideoMiniPlayer(
        song: player.currentSong,
        isPlaying: player.isPlaying,
        isLoading: player.isTransitioning,
        error: player.error,
        onOpen: _openPlayer,
        onToggle: ref.read(playerProvider.notifier).togglePlay,
        onQueue: _queue,
      ),
    );
  }
}
