import '../../l10n/video_strings.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'video_platforms.dart';

final videoStreamInfoProvider = StateProvider<Map<String, VideoStreamInfo>>(
  (ref) => const {},
);

String videoStreamLabel(VideoStreamInfo? info) {
  if (info == null) return VideoStrings.qualityUnknown;
  final parts = <String>[
    if (info.customSourceName != null)
      VideoStrings.customSourceLabel(info.customSourceName!),
    if (info.actualFormat != null) info.actualFormat!.toUpperCase(),
    if (info.actualBitrate != null)
      '${(info.actualBitrate! / 1000).round()} kbps',
  ];
  return parts.isEmpty ? VideoStrings.qualityUnknown : parts.join(' · ');
}
