import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../l10n/video_strings.dart';
import '../lx_source/lx_source.dart';

class VideoLxSourcePage extends StatefulWidget {
  const VideoLxSourcePage({
    super.key,
    this.initial,
    required this.onImport,
    required this.onSave,
    required this.onTest,
    required this.onHttp,
    this.onDelete,
  });
  static const linkKey = ValueKey('lx-link');
  static const importKey = ValueKey('lx-import');
  static const enabledKey = ValueKey('lx-enabled');
  static const downloadKey = ValueKey('lx-download');
  final LxSourceConfig? initial;
  final Future<LxSourceConfig> Function(String, CancelToken) onImport;
  final Future<void> Function(LxSourceConfig) onSave, onTest;
  final Future<void> Function()? onDelete;
  final VoidCallback onHttp;
  @override
  State<VideoLxSourcePage> createState() => _VideoLxSourcePageState();
}

class _VideoLxSourcePageState extends State<VideoLxSourcePage> {
  late final TextEditingController _link;
  LxSourceConfig? _source;
  bool _enabled = false, _downloads = false, _busy = false;
  String? _message;
  CancelToken? _cancel;
  @override
  void initState() {
    super.initState();
    _source = widget.initial;
    _link = TextEditingController(text: _source?.origin.toString() ?? '');
    _enabled = _source?.enabled ?? false;
    _downloads = _source?.allowForDownloads ?? false;
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _link.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await work();
    } on LxSourceException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = VideoStrings.lxOperationFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() => _run(() async {
    final token = CancelToken();
    _cancel = token;
    final value = await widget.onImport(_link.text.trim(), token);
    if (!mounted) return;
    setState(() {
      _source = value;
      _enabled = false;
      _downloads = false;
      _message = VideoStrings.lxImported;
    });
  });
  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          VideoStrings.customSourceDeleteNamed(
            widget.initial?.name ?? _source!.name,
          ),
        ),
        content: const Text(VideoStrings.customSourceDeleteEffect),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(VideoStrings.customSourceCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(VideoStrings.customSourceConfirmDelete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() async {
        await widget.onDelete!();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(VideoStrings.customSource)),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              VideoStrings.lxLinkImport,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            const Text(VideoStrings.lxLinkHint),
            const SizedBox(height: 16),
            TextField(
              key: VideoLxSourcePage.linkKey,
              controller: _link,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: VideoStrings.lxLinkLabel,
                hintText: 'https://…/latest.js',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: VideoLxSourcePage.importKey,
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.link),
              label: Text(
                _busy ? VideoStrings.lxImporting : VideoStrings.lxImport,
              ),
            ),
            if (_source != null) ...[
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _source!.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(VideoStrings.lxVersion(_source!.version)),
                      Text(
                        [
                          if (_source!.sources.containsKey('tx'))
                            VideoStrings.qqMusic,
                          if (_source!.sources.containsKey('wy'))
                            VideoStrings.netease,
                        ].join(' · '),
                      ),
                    ],
                  ),
                ),
              ),
              SwitchListTile(
                key: VideoLxSourcePage.enabledKey,
                contentPadding: EdgeInsets.zero,
                title: const Text(VideoStrings.customSourceEnable),
                value: _enabled,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _enabled = value),
              ),
              SwitchListTile(
                key: VideoLxSourcePage.downloadKey,
                contentPadding: EdgeInsets.zero,
                title: const Text(VideoStrings.customSourceAllowDownloads),
                value: _downloads,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _downloads = value),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await widget.onTest(_source!);
                        if (mounted) {
                          setState(() => _message = VideoStrings.lxTested);
                        }
                      }),
                child: const Text(VideoStrings.lxTest),
              ),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => widget.onSave(
                          _source!.copyWith(
                            enabled: _enabled,
                            allowForDownloads: _downloads,
                          ),
                        ),
                      ),
                child: const Text(VideoStrings.customSourceSave),
              ),
            ],
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_message!, key: const ValueKey('lx-message')),
              ),
            const SizedBox(height: 10),
            const Text(VideoStrings.customSourcePrivacy),
            const SizedBox(height: 8),
            const Text(VideoStrings.lxPlaybackHint),
            if (widget.onDelete != null)
              TextButton(
                onPressed: _busy ? null : _delete,
                child: const Text(VideoStrings.customSourceDelete),
              ),
            const Divider(height: 28),
            TextButton(
              onPressed: _busy ? null : widget.onHttp,
              child: const Text(VideoStrings.lxHttpSettings),
            ),
          ],
        ),
      ),
    ),
  );
}
