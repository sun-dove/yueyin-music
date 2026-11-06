import 'package:flutter/material.dart';

import '../../l10n/video_strings.dart';
import '../../models/platform_type.dart';

enum VideoCustomSourceTestStatus {
  success,
  unauthorized,
  incompatible,
  timeout,
  unavailable,
}

class VideoCustomSourceTestResult {
  const VideoCustomSourceTestResult._(this.status);
  const VideoCustomSourceTestResult.success()
    : this._(VideoCustomSourceTestStatus.success);
  const VideoCustomSourceTestResult.unauthorized()
    : this._(VideoCustomSourceTestStatus.unauthorized);
  const VideoCustomSourceTestResult.incompatible()
    : this._(VideoCustomSourceTestStatus.incompatible);
  const VideoCustomSourceTestResult.timeout()
    : this._(VideoCustomSourceTestStatus.timeout);
  const VideoCustomSourceTestResult.unavailable()
    : this._(VideoCustomSourceTestStatus.unavailable);

  final VideoCustomSourceTestStatus status;

  String get message => switch (status) {
    VideoCustomSourceTestStatus.success => VideoStrings.customSourceConnected,
    VideoCustomSourceTestStatus.unauthorized =>
      VideoStrings.customSourceUnauthorized,
    VideoCustomSourceTestStatus.incompatible =>
      VideoStrings.customSourceIncompatible,
    VideoCustomSourceTestStatus.timeout => VideoStrings.customSourceTimedOut,
    VideoCustomSourceTestStatus.unavailable =>
      VideoStrings.customSourceUnavailable,
  };
}

class VideoCustomSourceDraft {
  const VideoCustomSourceDraft({
    this.name = '',
    this.endpoint = '',
    this.platforms = const {},
    this.timeoutSeconds = 10,
    this.token = '',
    this.allowForDownloads = false,
    this.enabled = false,
  });

  final String name;
  final String endpoint;
  final Set<PlatformType> platforms;
  final int timeoutSeconds;
  final String token;
  final bool allowForDownloads;
  final bool enabled;
}

class VideoCustomSourcePage extends StatefulWidget {
  const VideoCustomSourcePage({
    super.key,
    this.initialDraft = const VideoCustomSourceDraft(),
    required this.onTest,
    required this.onSave,
    this.onDelete,
  });

  static const nameFieldKey = ValueKey('custom-source-name');
  static const endpointFieldKey = ValueKey('custom-source-endpoint');
  static const tokenFieldKey = ValueKey('custom-source-token');
  static const timeoutFieldKey = ValueKey('custom-source-timeout');
  static const qqSwitchKey = ValueKey('custom-source-qq');
  static const neteaseSwitchKey = ValueKey('custom-source-netease');
  static const downloadSwitchKey = ValueKey('custom-source-download');
  static const enabledSwitchKey = ValueKey('custom-source-enabled');

  final VideoCustomSourceDraft initialDraft;
  final Future<VideoCustomSourceTestResult> Function(
    VideoCustomSourceDraft draft,
  )
  onTest;
  final Future<void> Function(VideoCustomSourceDraft draft) onSave;
  final Future<void> Function()? onDelete;

  @override
  State<VideoCustomSourcePage> createState() => _VideoCustomSourcePageState();
}

class _VideoCustomSourcePageState extends State<VideoCustomSourcePage> {
  late final TextEditingController _name;
  late final TextEditingController _endpoint;
  late final TextEditingController _token;
  late final TextEditingController _timeout;
  late Set<PlatformType> _platforms;
  late bool _downloads;
  late bool _enabled;
  String? _result;

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    _name = TextEditingController(text: draft.name);
    _endpoint = TextEditingController(text: draft.endpoint);
    _token = TextEditingController(text: draft.token);
    _timeout = TextEditingController(text: draft.timeoutSeconds.toString());
    _platforms = {...draft.platforms};
    _downloads = draft.allowForDownloads;
    _enabled = draft.enabled;
  }

  @override
  void dispose() {
    _name.dispose();
    _endpoint.dispose();
    _token.dispose();
    _timeout.dispose();
    super.dispose();
  }

  VideoCustomSourceDraft get _draft => VideoCustomSourceDraft(
    name: _name.text.trim(),
    endpoint: _endpoint.text.trim(),
    token: _token.text,
    timeoutSeconds: int.tryParse(_timeout.text) ?? 10,
    platforms: {..._platforms},
    allowForDownloads: _downloads,
    enabled: _enabled,
  );

  void _setPlatform(PlatformType platform, bool enabled) => setState(() {
    enabled ? _platforms.add(platform) : _platforms.remove(platform);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(VideoStrings.customSource)),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: VideoCustomSourcePage.nameFieldKey,
              controller: _name,
              decoration: const InputDecoration(
                labelText: VideoStrings.customSourceName,
              ),
            ),
            TextField(
              key: VideoCustomSourcePage.endpointFieldKey,
              controller: _endpoint,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: VideoStrings.customSourceHttpsAddress,
              ),
            ),
            SwitchListTile(
              key: VideoCustomSourcePage.qqSwitchKey,
              title: const Text(VideoStrings.qqMusic),
              value: _platforms.contains(PlatformType.qq),
              onChanged: (value) => _setPlatform(PlatformType.qq, value),
            ),
            SwitchListTile(
              key: VideoCustomSourcePage.neteaseSwitchKey,
              title: const Text(VideoStrings.netease),
              value: _platforms.contains(PlatformType.netease),
              onChanged: (value) => _setPlatform(PlatformType.netease, value),
            ),
            TextField(
              key: VideoCustomSourcePage.timeoutFieldKey,
              controller: _timeout,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: VideoStrings.customSourceTimeout,
              ),
            ),
            TextField(
              key: VideoCustomSourcePage.tokenFieldKey,
              controller: _token,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: VideoStrings.customSourceToken,
              ),
            ),
            SwitchListTile(
              key: VideoCustomSourcePage.downloadSwitchKey,
              title: const Text(VideoStrings.customSourceAllowDownloads),
              value: _downloads,
              onChanged: (value) => setState(() => _downloads = value),
            ),
            SwitchListTile(
              key: VideoCustomSourcePage.enabledSwitchKey,
              title: const Text(VideoStrings.customSourceEnable),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            const Text(VideoStrings.customSourcePrivacy),
            const Text(VideoStrings.customSourceAccuracy),
            if (_result != null) ...[
              const SizedBox(height: 12),
              Text(_result!),
            ],
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () async {
                final result = await widget.onTest(_draft);
                if (mounted) setState(() => _result = result.message);
              },
              child: const Text(VideoStrings.customSourceTest),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => widget.onSave(_draft),
              child: const Text(VideoStrings.customSourceSave),
            ),
            if (widget.onDelete != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(
                        VideoStrings.customSourceDeleteNamed(_name.text),
                      ),
                      content: const Text(
                        VideoStrings.customSourceDeleteEffect,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text(VideoStrings.customSourceCancel),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text(
                            VideoStrings.customSourceConfirmDelete,
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) await widget.onDelete!();
                },
                child: const Text(VideoStrings.customSourceDelete),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
