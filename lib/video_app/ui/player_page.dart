import '../../l10n/video_strings.dart';

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../lyrics/models/lyrics_line.dart';
import '../../models/song.dart';
import 'video_shell.dart';
import 'video_theme.dart';

String videoTime(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.song,
    required this.position,
    required this.duration,
    required this.isPlaying,
    this.isLoading = false,
    this.error,
    this.qualityLabel,
    this.isPreview = false,
    this.lyrics = const [],
    this.lyricsLoading = false,
    this.lyricsError,
    this.modeLabel = VideoStrings.sequential,
    required this.onToggle,
    required this.onPrevious,
    required this.onNext,
    required this.onSeek,
    required this.onQueue,
    required this.onMode,
    this.onQuality,
    this.sourceStatus,
  });
  final Song song;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isLoading;
  final String? error;
  final String? qualityLabel;
  final bool isPreview;
  final List<LyricsLine> lyrics;
  final bool lyricsLoading;
  final String? lyricsError;
  final String modeLabel;
  final VoidCallback onToggle;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onQueue;
  final VoidCallback onMode;
  final VoidCallback? onQuality;
  final Widget? sourceStatus;
  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  bool expandedLyrics = false;
  final _lyricsScroll = ScrollController();
  int get activeLine =>
      widget.lyrics.lastIndexWhere((line) => line.timestamp <= widget.position);

  @override
  void didUpdateWidget(VideoPlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song != widget.song) expandedLyrics = false;
    if (expandedLyrics && _lyricsScroll.hasClients) {
      final index = activeLine;
      if (index !=
          oldWidget.lyrics.lastIndexWhere(
            (line) => line.timestamp <= oldWidget.position,
          )) {
        final target = (index * 62.0 - 110).clamp(
          0.0,
          _lyricsScroll.position.maxScrollExtent,
        );
        _lyricsScroll.animateTo(
          target,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  void dispose() {
    _lyricsScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final currentLine = activeLine >= 0 ? widget.lyrics[activeLine].text : '';
    return Scaffold(
      backgroundColor: VideoTheme.canvas(context),
      body: Stack(
        children: [
          if (widget.song.coverUrl != null)
            Positioned.fill(
              child: Opacity(
                opacity: Theme.of(context).brightness == Brightness.dark
                    ? .12
                    : .17,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 65, sigmaY: 65),
                  child: Image.network(
                    widget.song.coverUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final coverSize = math.min(
                  constraints.maxWidth - 64,
                  constraints.maxHeight * .43,
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      Center(
                        child: InkWell(
                          onTap: () => Navigator.maybePop(context),
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 38,
                              vertical: 15,
                            ),
                            child: Container(
                              width: 26,
                              height: 3,
                              decoration: BoxDecoration(
                                color: textColor.withValues(alpha: .8),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (widget.sourceStatus != null) widget.sourceStatus!,
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 230),
                          child: expandedLyrics
                              ? _lyricsView(context)
                              : SingleChildScrollView(
                                  key: const ValueKey(VideoStrings.coverView),
                                  child: Column(
                                    children: [
                                      const SizedBox(height: 10),
                                      GestureDetector(
                                        onTap: () => setState(
                                          () => expandedLyrics = true,
                                        ),
                                        onHorizontalDragEnd: (_) => setState(
                                          () => expandedLyrics = true,
                                        ),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              22,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: .17,
                                                ),
                                                blurRadius: 24,
                                                offset: const Offset(0, 13),
                                              ),
                                            ],
                                          ),
                                          child: VideoCover(
                                            url: widget.song.coverUrl,
                                            size: coverSize,
                                            radius: 22,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 30),
                                      SizedBox(
                                        height: 42,
                                        child: Center(
                                          child: Text(
                                            widget.lyricsLoading
                                                ? VideoStrings.loadingLyrics
                                                : widget.lyricsError ??
                                                      (currentLine.isEmpty
                                                          ? VideoStrings
                                                                .noLyrics
                                                          : currentLine),
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 9),
                                      Text(
                                        widget.song.name,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        widget.song.artistNames,
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: VideoTheme.secondaryText(
                                            context,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                      if (widget.isLoading || widget.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            widget.error ?? VideoStrings.preparingAudio,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.error == null
                                  ? VideoTheme.secondaryText(context)
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      Center(
                        child: InkWell(
                          onTap: widget.onQuality,
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 10, 8, 7),
                            child: Text(
                              '● ${widget.song.platform.name == 'qq'
                                  ? VideoStrings.qqMusic
                                  : widget.song.platform.name == 'netease'
                                  ? VideoStrings.netease
                                  : VideoStrings.local}${widget.qualityLabel == null ? '' : '   ${widget.qualityLabel}'}${widget.isPreview ? VideoStrings.previewSuffix : ''}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: textColor.withValues(alpha: .8),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 13,
                          ),
                        ),
                        child: Slider(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 0,
                            vertical: 5,
                          ),
                          value: widget.position.inMilliseconds
                              .toDouble()
                              .clamp(
                                0,
                                math
                                    .max(1, widget.duration.inMilliseconds)
                                    .toDouble(),
                              ),
                          max: math
                              .max(1, widget.duration.inMilliseconds)
                              .toDouble(),
                          onChanged:
                              widget.duration <= Duration.zero ||
                                  widget.isLoading
                              ? null
                              : (value) => widget.onSeek(
                                  Duration(milliseconds: value.round()),
                                ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            videoTime(widget.position),
                            style: TextStyle(
                              fontSize: 10,
                              color: VideoTheme.secondaryText(context),
                            ),
                          ),
                          Text(
                            videoTime(widget.duration),
                            style: TextStyle(
                              fontSize: 10,
                              color: VideoTheme.secondaryText(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 13),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: VideoStrings.previousSong,
                            onPressed: widget.onPrevious,
                            icon: const Icon(
                              Icons.skip_previous_rounded,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 18),
                          IconButton.filled(
                            tooltip: widget.isPlaying && !widget.isLoading
                                ? VideoStrings.pause
                                : VideoStrings.play,
                            onPressed: widget.isLoading
                                ? null
                                : widget.onToggle,
                            style: IconButton.styleFrom(
                              backgroundColor: VideoTheme.primary,
                              disabledBackgroundColor: VideoTheme.primary
                                  .withValues(alpha: .55),
                              foregroundColor: Colors.white,
                              fixedSize: const Size(62, 62),
                            ),
                            icon: widget.isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    widget.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 33,
                                  ),
                          ),
                          const SizedBox(width: 18),
                          IconButton(
                            tooltip: VideoStrings.nextSong,
                            onPressed: widget.onNext,
                            icon: const Icon(Icons.skip_next_rounded, size: 28),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 13, bottom: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton.icon(
                              onPressed: widget.onMode,
                              icon: Icon(
                                widget.modeLabel == VideoStrings.shuffle
                                    ? Icons.shuffle_rounded
                                    : widget.modeLabel == VideoStrings.repeatOne
                                    ? Icons.repeat_one_rounded
                                    : Icons.repeat_rounded,
                                size: 17,
                              ),
                              label: Text(
                                widget.modeLabel,
                                style: const TextStyle(fontSize: 11),
                              ),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  tooltip: expandedLyrics
                                      ? VideoStrings.collapseLyrics
                                      : VideoStrings.expandLyrics,
                                  onPressed: () => setState(
                                    () => expandedLyrics = !expandedLyrics,
                                  ),
                                  icon: const Icon(
                                    Icons.lyrics_outlined,
                                    size: 21,
                                  ),
                                ),
                                IconButton(
                                  tooltip: VideoStrings.playQueue,
                                  onPressed: widget.onQueue,
                                  icon: const Icon(
                                    Icons.queue_music_rounded,
                                    size: 23,
                                  ),
                                ),
                              ],
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
        ],
      ),
    );
  }

  Widget _lyricsView(BuildContext context) => Column(
    key: const ValueKey(VideoStrings.lyricsView),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        widget.song.name,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
      ),
      Text(
        widget.song.artistNames,
        style: TextStyle(
          fontSize: 13,
          color: VideoTheme.secondaryText(context),
        ),
      ),
      const SizedBox(height: 18),
      Expanded(
        child: widget.lyrics.isEmpty
            ? Center(
                child: Text(
                  widget.lyricsLoading
                      ? VideoStrings.loadingLyrics
                      : widget.lyricsError ?? VideoStrings.noLyrics,
                ),
              )
            : ListView.builder(
                controller: _lyricsScroll,
                padding: const EdgeInsets.symmetric(vertical: 35),
                itemCount: widget.lyrics.length,
                itemBuilder: (context, index) {
                  final line = widget.lyrics[index];
                  return InkWell(
                    onTap: () => widget.onSeek(line.timestamp),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      child: Text(
                        line.text,
                        style: TextStyle(
                          fontSize: 23,
                          height: 1.4,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: index == activeLine ? 1 : .32),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    ],
  );
}
