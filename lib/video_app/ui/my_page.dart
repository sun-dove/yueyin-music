import '../../l10n/video_strings.dart';

import 'package:flutter/material.dart';

import '../../models/platform_type.dart';
import 'catalog_pages.dart';
import 'video_theme.dart';

class VideoAccountSummary {
  const VideoAccountSummary({
    required this.nickname,
    this.avatarUrl,
    this.loaded = 0,
    this.total,
    this.complete = false,
  });
  final String nickname;
  final String? avatarUrl;
  final int loaded;
  final int? total;
  final bool complete;
}

class VideoMyPage extends StatelessWidget {
  const VideoMyPage({
    super.key,
    required this.accounts,
    required this.cacheLabel,
    required this.downloadLabel,
    required this.themeLabel,
    required this.onAccount,
    required this.onQuality,
    required this.onCache,
    required this.onDownloads,
    required this.onDirectory,
    required this.onTheme,
    required this.onLocal,
    this.qualityLabels = const {},
    this.localSongCount,
    this.customSourceLabel = VideoStrings.customSourceNotConfigured,
    this.onCustomSource,
  });
  final Map<PlatformType, VideoAccountSummary> accounts;
  final String cacheLabel, downloadLabel, themeLabel;
  final ValueChanged<PlatformType> onAccount;
  final void Function(PlatformType, bool download) onQuality;
  final VoidCallback onCache, onDownloads, onDirectory, onTheme, onLocal;
  final Map<String, String> qualityLabels;
  final int? localSongCount;
  final String customSourceLabel;
  final VoidCallback? onCustomSource;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
    children: [
      const Text(
        VideoStrings.my,
        style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 17),
      for (final platform in [PlatformType.qq, PlatformType.netease]) ...[
        _account(context, platform),
        const SizedBox(height: 12),
      ],
      Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: VideoTheme.surface(context),
          borderRadius: BorderRadius.circular(21),
        ),
        child: Row(
          children: [
            for (final entry in <String, int?>{
              VideoStrings.qqLikes:
                  accounts[PlatformType.qq]?.total ??
                  accounts[PlatformType.qq]?.loaded,
              VideoStrings.neteaseLikes:
                  accounts[PlatformType.netease]?.total ??
                  accounts[PlatformType.netease]?.loaded,
              VideoStrings.localSongs: localSongCount,
            }.entries)
              Expanded(
                child: Column(
                  children: [
                    Text(
                      entry.value?.toString() ?? '—',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 9,
                        color: VideoTheme.secondaryText(context),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      _heading(VideoStrings.playSettings),
      _group(context, [
        _row(
          context,
          VideoStrings.customSource,
          customSourceLabel,
          Icons.hub_outlined,
          onCustomSource ?? () {},
        ),
        for (final platform in [PlatformType.qq, PlatformType.netease])
          _row(
            context,
            VideoStrings.platformQuality(videoPlatformLabel(platform)),
            qualityLabels['${platform.name}:play'] ??
                VideoStrings.standardQuality,
            Icons.equalizer_rounded,
            () => onQuality(platform, false),
          ),
        _row(
          context,
          VideoStrings.cacheManagement,
          cacheLabel,
          Icons.storage_rounded,
          onCache,
        ),
      ]),
      _heading(VideoStrings.downloadSettings),
      _group(context, [
        for (final platform in [PlatformType.qq, PlatformType.netease])
          _row(
            context,
            VideoStrings.platformQuality(
              videoPlatformLabel(platform),
              download: true,
            ),
            qualityLabels['${platform.name}:download'] ??
                VideoStrings.standardQuality,
            Icons.music_note_rounded,
            () => onQuality(platform, true),
          ),
        _row(
          context,
          VideoStrings.downloadManagement,
          downloadLabel,
          Icons.download_rounded,
          onDownloads,
        ),
        _row(
          context,
          VideoStrings.storageLocation,
          VideoStrings.chooseFolder,
          Icons.folder_outlined,
          onDirectory,
        ),
      ]),
      _heading(VideoStrings.otherSettings),
      _group(context, [
        _row(
          context,
          VideoStrings.appearanceTheme,
          themeLabel,
          Icons.palette_outlined,
          onTheme,
        ),
        _row(
          context,
          VideoStrings.localMusic,
          VideoStrings.importScan,
          Icons.library_music_outlined,
          onLocal,
        ),
      ]),
      const SizedBox(height: 16),
      Text(
        VideoStrings.appVersion,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          color: VideoTheme.secondaryText(context),
        ),
      ),
    ],
  );

  Widget _account(BuildContext context, PlatformType platform) {
    final user = accounts[platform];
    final qq = platform == PlatformType.qq;
    final count = user == null
        ? VideoStrings.loginToSyncLikes
        : VideoStrings.accountLikes(user.loaded, user.total);
    return Material(
      color: VideoTheme.surface(context),
      borderRadius: BorderRadius.circular(21),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onAccount(platform),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor:
                    (qq ? const Color(0xFF22B783) : const Color(0xFFE84D56))
                        .withValues(alpha: .12),
                backgroundImage: user?.avatarUrl == null
                    ? null
                    : NetworkImage(user!.avatarUrl!),
                child: user?.avatarUrl == null
                    ? Icon(
                        qq ? Icons.music_note_rounded : Icons.cloud_rounded,
                        color: qq
                            ? const Color(0xFF22B783)
                            : const Color(0xFFE84D56),
                        size: 27,
                      )
                    : null,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.nickname ??
                          VideoStrings.loginPlatform(
                            videoPlatformLabel(platform),
                          ),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count,
                      style: TextStyle(
                        fontSize: 11,
                        color: VideoTheme.secondaryText(context),
                      ),
                    ),
                    if (user != null && !user.complete)
                      const Text(
                        VideoStrings.syncIncomplete,
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFFB56B25),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 19),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(3, 13, 0, 9),
    child: Text(
      title,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
  );
  Widget _group(BuildContext context, List<Widget> children) => ClipRRect(
    borderRadius: BorderRadius.circular(21),
    child: ColoredBox(
      color: VideoTheme.surface(context),
      child: Column(children: children),
    ),
  );
  Widget _row(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    VoidCallback onTap,
  ) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: VideoTheme.secondaryText(context)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 11,
                color: VideoTheme.secondaryText(context),
              ),
            ),
          ),
          const Icon(Icons.chevron_right_rounded, size: 16),
        ],
      ),
    ),
  );
}
