import '../../l10n/video_strings.dart';

import 'package:flutter/material.dart';

import '../../models/platform_type.dart';
import '../../models/song.dart';
import 'video_theme.dart';

String videoSongKey(Song song) => '${song.platform.name}:${song.id}';

String videoPlatformLabel(PlatformType platform) => switch (platform) {
  PlatformType.qq => VideoStrings.qqMusic,
  PlatformType.netease => VideoStrings.netease,
  PlatformType.local => VideoStrings.local,
  PlatformType.kugou => VideoStrings.kugou,
};

/// 界面只消费明确状态；空列表、失败和仍在加载不能相互代替。
class VideoCatalogViewState {
  final List<Song> songs;
  final bool loading;
  final bool loadingMore;
  final int? total;
  final bool hasMore;
  final String? error;
  final bool canRetry;

  const VideoCatalogViewState({
    this.songs = const [],
    this.loading = false,
    this.loadingMore = false,
    this.total,
    this.hasMore = false,
    this.error,
    this.canRetry = true,
  });
}

class VideoSearchPage extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final PlatformType platform;
  final ValueChanged<PlatformType> onPlatformChanged;
  final VideoCatalogViewState result;
  final bool submitted;
  final List<String> hotTerms;
  final Map<PlatformType, int?> totals;
  final VoidCallback? onRetry;
  final VoidCallback? onRefresh;
  final VoidCallback? onLoadMore;
  final ValueChanged<Song> onSongTap;
  final ValueChanged<Song>? onSongLike;
  final ValueChanged<Song>? onSongMore;
  final Set<String> likedKeys;
  final Song? currentSong;
  final Map<String, String> qualityLabels;

  const VideoSearchPage({
    super.key,
    required this.controller,
    required this.onSearch,
    required this.platform,
    required this.onPlatformChanged,
    required this.result,
    this.submitted = false,
    this.hotTerms = const [],
    this.totals = const {},
    this.onRetry,
    this.onRefresh,
    this.onLoadMore,
    required this.onSongTap,
    this.onSongLike,
    this.onSongMore,
    this.likedKeys = const {},
    this.currentSong,
    this.qualityLabels = const {},
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: VideoTheme.canvas(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 9, 16, 12),
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: onSearch,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: VideoStrings.searchHint,
                hintStyle: TextStyle(color: VideoTheme.secondaryText(context)),
                filled: true,
                fillColor: VideoTheme.surface(context),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                prefixIconConstraints: const BoxConstraints(minWidth: 38),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          tooltip: VideoStrings.clearSearch,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.cancel, size: 17),
                          onPressed: () {
                            controller.clear();
                            onSearch('');
                          },
                        ),
                ),
                suffixIconConstraints: const BoxConstraints(minWidth: 36),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (!submitted)
            Expanded(child: _hotSearches(context))
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: VideoTheme.surface(context),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Row(
                    children: [
                      for (final source in const [
                        PlatformType.local,
                        PlatformType.qq,
                        PlatformType.netease,
                      ])
                        Expanded(child: _platformChip(context, source)),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 10, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _loadedLabel(result),
                      style: TextStyle(
                        fontSize: 10,
                        color: VideoTheme.secondaryText(context),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: VideoStrings.refreshSearch,
                    onPressed: result.loading || result.loadingMore
                        ? null
                        : onRefresh ?? onRetry,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _VideoSongList(
                result: result,
                loadingLabel: VideoStrings.searching,
                emptyLabel: VideoStrings.noSongsFound,
                onRetry: onRetry,
                onLoadMore: onLoadMore,
                onSongTap: onSongTap,
                onSongLike: onSongLike,
                onSongMore: onSongMore,
                likedKeys: likedKeys,
                currentSong: currentSong,
                qualityLabels: qualityLabels,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _platformChip(BuildContext context, PlatformType source) {
    final selected = source == platform;
    final total = totals[source];
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? VideoTheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => onPlatformChanged(source),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
            child: Text(
              '${videoPlatformLabel(source)} ${total ?? '—'}',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hotSearches(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
    children: [
      Row(
        children: [
          const Text(
            VideoStrings.hotSearches,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(width: 12),
          Text(
            VideoStrings.hotSearchSource,
            style: TextStyle(
              fontSize: 10,
              color: VideoTheme.secondaryText(context),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      DecoratedBox(
        decoration: BoxDecoration(
          color: VideoTheme.surface(context),
          borderRadius: BorderRadius.circular(20),
        ),
        child: hotTerms.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  VideoStrings.noHotSearches,
                  style: TextStyle(
                    fontSize: 12,
                    color: VideoTheme.secondaryText(context),
                  ),
                ),
              )
            : Column(
                children: [
                  for (var index = 0; index < hotTerms.length; index++)
                    _hotSearchRow(context, index),
                ],
              ),
      ),
    ],
  );

  Widget _hotSearchRow(BuildContext context, int index) {
    final color = switch (index) {
      0 => const Color(0xFFBA333B),
      1 => const Color(0xFF9E741D),
      2 => VideoTheme.primary,
      _ => Theme.of(context).colorScheme.onSurface,
    };
    return InkWell(
      onTap: () {
        controller.text = hotTerms[index];
        onSearch(hotTerms[index]);
      },
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '${index + 1}',
                style: TextStyle(fontSize: 11, color: color),
              ),
            ),
            Expanded(
              child: Text(
                hotTerms[index],
                style: TextStyle(fontSize: 14, color: color),
              ),
            ),
            if (index < 3)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: VideoTheme.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  VideoStrings.hot,
                  style: TextStyle(fontSize: 9, color: VideoTheme.primary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class VideoLibraryPage extends StatelessWidget {
  final PlatformType platform;
  final VideoCatalogViewState result;
  final bool loggedIn;
  final bool syncComplete;
  final VoidCallback onLogin;
  final VoidCallback onRefresh;
  final VoidCallback onPlayAll;
  final VoidCallback onDownloadAll;
  final ValueChanged<Song> onSongTap;
  final ValueChanged<Song>? onSongLike;
  final ValueChanged<Song>? onSongMore;
  final VoidCallback? onRetry;
  final VoidCallback? onLoadMore;
  final Set<String> likedKeys;
  final Song? currentSong;
  final Map<String, String> qualityLabels;

  const VideoLibraryPage({
    super.key,
    required this.platform,
    required this.result,
    required this.loggedIn,
    this.syncComplete = false,
    required this.onLogin,
    required this.onRefresh,
    required this.onPlayAll,
    required this.onDownloadAll,
    required this.onSongTap,
    this.onSongLike,
    this.onSongMore,
    this.onRetry,
    this.onLoadMore,
    this.likedKeys = const {},
    this.currentSong,
    this.qualityLabels = const {},
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: VideoTheme.canvas(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 5, 9, 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    videoPlatformLabel(platform),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: VideoStrings.syncLikes,
                  onPressed: loggedIn && !result.loading ? onRefresh : null,
                  icon: const Icon(Icons.refresh_rounded, size: 21),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _playlistCard(context),
          ),
          if (loggedIn && result.songs.isNotEmpty && !syncComplete)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: Text(
                VideoStrings.partialLibrary(result.songs.length, result.total),
                style: TextStyle(
                  fontSize: 11,
                  color: VideoTheme.secondaryText(context),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 21, 18, 8),
            child: Row(
              children: [
                const Text(
                  VideoStrings.song,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Text(
                  VideoStrings.sortByCollectionTime,
                  style: TextStyle(
                    fontSize: 9,
                    color: VideoTheme.secondaryText(context),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: !loggedIn
                ? _CatalogMessage(
                    icon: Icons.account_circle_outlined,
                    message: VideoStrings.loginToSyncMusic,
                    action: TextButton(
                      onPressed: onLogin,
                      child: Text(
                        VideoStrings.loginPlatform(
                          videoPlatformLabel(platform),
                        ),
                      ),
                    ),
                  )
                : _VideoSongList(
                    result: result,
                    loadingLabel: VideoStrings.syncingMusic,
                    emptyLabel: VideoStrings.noLikedSongs,
                    onRetry: onRetry ?? onRefresh,
                    onLoadMore: onLoadMore,
                    onSongTap: onSongTap,
                    onSongLike: onSongLike,
                    onSongMore: onSongMore,
                    likedKeys: likedKeys,
                    currentSong: currentSong,
                    qualityLabels: qualityLabels,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _playlistCard(BuildContext context) {
    final qq = platform == PlatformType.qq;
    final enabled = loggedIn && result.songs.isNotEmpty;
    final minutes =
        result.songs.fold<int>(
          0,
          (sum, song) => sum + song.duration.inSeconds,
        ) ~/
        60;
    final count = result.total ?? result.songs.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: VideoTheme.surface(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: qq
                      ? const [Color(0xFF5770ED), Color(0xFF08634C)]
                      : const [Color(0xFFEE5677), Color(0xFFAD1649)],
                ),
              ),
              child: const Icon(Icons.favorite, color: Colors.white, size: 27),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    VideoStrings.likedMusic,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    VideoStrings.libraryDetails(
                      count,
                      minutes,
                      syncComplete,
                      videoPlatformLabel(platform),
                    ),
                    style: TextStyle(
                      fontSize: 9.5,
                      color: VideoTheme.secondaryText(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 3,
                    children: [
                      FilledButton.icon(
                        onPressed: enabled ? onPlayAll : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: VideoTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(fontSize: 10.5),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 15),
                        label: Text(
                          enabled && !syncComplete
                              ? VideoStrings.playLoaded
                              : VideoStrings.playAll,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: enabled ? onDownloadAll : null,
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context)
                              .colorScheme
                              .onSurface,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(fontSize: 10.5),
                        ),
                        icon: const Icon(Icons.download_rounded, size: 15),
                        label: Text(
                          enabled && !syncComplete
                              ? VideoStrings.downloadLoaded
                              : VideoStrings.download,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoSongTile extends StatelessWidget {
  final Song song;
  final int index;
  final VoidCallback onTap;
  final bool liked;
  final bool playing;
  final VoidCallback? onLike;
  final VoidCallback? onMore;
  final String? qualityLabel;

  const VideoSongTile({
    super.key,
    required this.song,
    required this.index,
    required this.onTap,
    this.liked = false,
    this.playing = false,
    this.onLike,
    this.onMore,
    this.qualityLabel,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = VideoTheme.secondaryText(context);
    final scaled = MediaQuery.textScalerOf(context).scale(14) > 19;
    return Semantics(
      selected: playing,
      child: Material(
        color: playing
            ? VideoTheme.primary.withValues(alpha: .1)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 5, 7),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: playing
                      ? const Icon(
                          Icons.equalizer_rounded,
                          size: 14,
                          color: VideoTheme.primary,
                          semanticLabel: VideoStrings.playing,
                        )
                      : Text(
                          '$index',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10, color: secondary),
                        ),
                ),
                const SizedBox(width: 4),
                VideoSongCover(song: song, size: 38),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              song.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: playing ? VideoTheme.primary : null,
                              ),
                            ),
                          ),
                          if (qualityLabel?.isNotEmpty ?? false) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFC8AF71)
                                    .withValues(alpha: .18),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Text(
                                qualityLabel!,
                                style: const TextStyle(
                                  color: Color(0xFF8B713B),
                                  fontSize: 8,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (song.artistNames.isNotEmpty) song.artistNames,
                          if (song.album?.name.isNotEmpty ?? false)
                            song.album!.name,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: secondary),
                      ),
                    ],
                  ),
                ),
                if (!scaled) ...[
                  const SizedBox(width: 5),
                  Text(
                    _songDuration(song.duration),
                    style: TextStyle(fontSize: 10, color: secondary),
                  ),
                ],
                IconButton(
                  tooltip: liked ? VideoStrings.unlike : VideoStrings.like,
                  onPressed: onLike,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 36,
                  ),
                  icon: Icon(
                    liked ? Icons.favorite : Icons.favorite_border_rounded,
                    size: 17,
                    color: liked ? const Color(0xFFC02C35) : secondary,
                  ),
                ),
                IconButton(
                  tooltip: VideoStrings.songActions,
                  onPressed: onMore,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 36,
                  ),
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    size: 18,
                    color: secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class VideoSongCover extends StatelessWidget {
  final Song song;
  final double size;

  const VideoSongCover({super.key, required this.song, this.size = 38});

  @override
  Widget build(BuildContext context) {
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: song.platform == PlatformType.netease
              ? const [Color(0xFFC5A47E), Color(0xFF8D8F80)]
              : const [Color(0xFF94B4C1), Color(0xFF558C78)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: size * .48,
          color: Colors.white70,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .13),
      child: SizedBox.square(
        dimension: size,
        child: song.coverUrl?.isNotEmpty ?? false
            ? Image.network(
                song.coverUrl!,
                fit: BoxFit.cover,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                errorBuilder: (context, error, stackTrace) => placeholder,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : placeholder,
              )
            : placeholder,
      ),
    );
  }
}

class _VideoSongList extends StatefulWidget {
  final VideoCatalogViewState result;
  final String loadingLabel;
  final String emptyLabel;
  final VoidCallback? onRetry;
  final VoidCallback? onLoadMore;
  final ValueChanged<Song> onSongTap;
  final ValueChanged<Song>? onSongLike;
  final ValueChanged<Song>? onSongMore;
  final Set<String> likedKeys;
  final Song? currentSong;
  final Map<String, String> qualityLabels;

  const _VideoSongList({
    required this.result,
    required this.loadingLabel,
    required this.emptyLabel,
    this.onRetry,
    this.onLoadMore,
    required this.onSongTap,
    this.onSongLike,
    this.onSongMore,
    required this.likedKeys,
    this.currentSong,
    required this.qualityLabels,
  });

  @override
  State<_VideoSongList> createState() => _VideoSongListState();
}

class _VideoSongListState extends State<_VideoSongList> {
  bool _requestedMore = false;

  @override
  void didUpdateWidget(covariant _VideoSongList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result.songs.length != widget.result.songs.length ||
        oldWidget.result.loadingMore != widget.result.loadingMore ||
        oldWidget.result.error != widget.result.error) {
      _requestedMore = false;
    }
  }

  void _loadMore() {
    if (_requestedMore ||
        widget.result.loadingMore ||
        widget.onLoadMore == null) {
      return;
    }
    _requestedMore = true;
    widget.onLoadMore!();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.result;
    if (state.songs.isEmpty) {
      if (state.loading) {
        return _CatalogMessage(loading: true, message: widget.loadingLabel);
      }
      if (state.error != null) return _errorMessage();
      return _CatalogMessage(
        icon: Icons.music_note_outlined,
        message: widget.emptyLabel,
      );
    }
    final hasFooter = state.loadingMore || state.hasMore || state.error != null;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 240 &&
            state.hasMore &&
            !state.loading &&
            state.error == null) {
          _loadMore();
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 18),
        itemCount: state.songs.length + (hasFooter ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.songs.length) {
            if (state.error != null) return _errorMessage();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: state.loadingMore
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : TextButton(
                        onPressed: widget.onLoadMore == null ? null : _loadMore,
                        child: const Text(VideoStrings.loadMore),
                      ),
              ),
            );
          }
          final song = state.songs[index];
          final key = videoSongKey(song);
          return VideoSongTile(
            key: ValueKey(key),
            song: song,
            index: index + 1,
            liked: widget.likedKeys.contains(key),
            playing: widget.currentSong == song,
            qualityLabel: widget.qualityLabels[key],
            onTap: () => widget.onSongTap(song),
            onLike: widget.onSongLike == null
                ? null
                : () => widget.onSongLike!(song),
            onMore: widget.onSongMore == null
                ? null
                : () => widget.onSongMore!(song),
          );
        },
      ),
    );
  }

  Widget _errorMessage() => _CatalogMessage(
    icon: Icons.wifi_off_rounded,
    message: widget.result.error!,
    compact: widget.result.songs.isNotEmpty,
    action: widget.result.canRetry && widget.onRetry != null
        ? TextButton(
            onPressed: widget.onRetry,
            child: const Text(VideoStrings.retry),
          )
        : null,
  );
}

class _CatalogMessage extends StatelessWidget {
  final IconData? icon;
  final String message;
  final Widget? action;
  final bool loading;
  final bool compact;

  const _CatalogMessage({
    this.icon,
    required this.message,
    this.action,
    this.loading = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 24,
        vertical: compact ? 18 : 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (icon != null)
            Icon(icon, size: 30, color: VideoTheme.secondaryText(context)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: VideoTheme.secondaryText(context),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 7), action!],
        ],
      ),
    ),
  );
}

String _loadedLabel(VideoCatalogViewState result) =>
    VideoStrings.loadedSongs(result.songs.length, result.total);

String _songDuration(Duration duration) =>
    '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
