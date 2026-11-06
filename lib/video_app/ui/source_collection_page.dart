import '../../l10n/source_strings.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../lx_source/lx_source.dart';
import '../multi_source/source_collection.dart';

class SourceCollectionPage extends StatefulWidget {
  const SourceCollectionPage({
    super.key,
    required this.initial,
    required this.onImport,
    required this.onInspect,
    required this.onSave,
    required this.onHttp,
    this.warning,
  });
  final SourceCollection initial;
  final Future<LxSourceConfig> Function(String, CancelToken) onImport;
  final Future<void> Function(LxSourceConfig, CancelToken) onInspect;
  final Future<void> Function(SourceCollection) onSave;
  final VoidCallback onHttp;
  final String? warning;
  @override
  State<SourceCollectionPage> createState() => _SourceCollectionPageState();
}

class _SourceCollectionPageState extends State<SourceCollectionPage> {
  late SourceCollection _value = widget.initial;
  final _link = TextEditingController();
  final _status = <String, String>{};
  CancelToken? _token;
  bool _busy = false;
  String? _message;
  @override
  void dispose() {
    _token?.cancel();
    _link.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(CancelToken) action) async {
    if (_busy) return;
    final token = CancelToken();
    _token = token;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action(token);
    } on LxSourceException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = SourceStrings.operationFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() => _run((token) async {
    final config = await widget.onImport(_link.text.trim(), token);
    if (!mounted) return;
    setState(() {
      _value = _value.upsert(config);
      final entry = _value.entries.firstWhere(
        (e) =>
            lxImportUri(e.config.origin.toString()) ==
            lxImportUri(config.origin.toString()),
      );
      _status[entry.id] = SourceStrings.initialized;
      _message = SourceStrings.imported;
    });
  });
  Future<void> _remove(SourceEntry entry) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(SourceStrings.deleteNamed(entry.config.name)),
        content: const Text(SourceStrings.saveToApply),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(SourceStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(SourceStrings.remove),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      setState(() => _value = _value.remove(entry.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(SourceStrings.management)),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(SourceStrings.intro),
            if (widget.warning != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(widget.warning!),
              ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('collection-link'),
              controller: _link,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: SourceStrings.scriptLink,
                hintText: 'https://…/latest.js',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _import,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_link),
              label: Text(
                _busy ? SourceStrings.busy : SourceStrings.importLink,
              ),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_message!),
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => setState(
                      () => _value = _value.copyWith(
                        autoSwitch: true,
                        sourceFirst: true,
                        highestQuality: true,
                      ),
                    ),
              child: const Text(SourceStrings.recommended),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(SourceStrings.autoSwitch),
              subtitle: const Text(SourceStrings.autoSwitchHint),
              value: _value.autoSwitch,
              onChanged: _busy
                  ? null
                  : (v) =>
                        setState(() => _value = _value.copyWith(autoSwitch: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(SourceStrings.highest),
              subtitle: const Text(SourceStrings.highestSourceHint),
              value: _value.highestQuality,
              onChanged: _busy
                  ? null
                  : (v) => setState(
                      () => _value = _value.copyWith(highestQuality: v),
                    ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(SourceStrings.sourceFirst),
              subtitle: Text(
                _value.sourceFirst
                    ? SourceStrings.sourceFirstHint
                    : SourceStrings.officialFirstHint,
              ),
              value: _value.sourceFirst,
              onChanged: _busy
                  ? null
                  : (v) => setState(
                      () => _value = _value.copyWith(sourceFirst: v),
                    ),
            ),
            const Divider(height: 28),
            Text(
              SourceStrings.savedCount(_value.entries.length),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_value.entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(SourceStrings.empty),
              ),
            for (final entry in _value.entries) _card(entry),
            const SizedBox(height: 12),
            const Text(SourceStrings.declarationHint),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('collection-save'),
              onPressed: _busy
                  ? null
                  : () => _run((_) => widget.onSave(_value)),
              child: const Text(SourceStrings.save),
            ),
            TextButton(
              onPressed: _busy ? null : widget.onHttp,
              child: const Text(SourceStrings.httpSettings),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _card(SourceEntry entry) {
    final source = entry.config;
    final preferred = _value.preferred?.id == entry.id;
    final capabilities = source.sources.entries
        .map(
          (e) =>
              '${e.key == 'tx'
                  ? SourceStrings.qq
                  : e.key == 'wy'
                  ? SourceStrings.netease
                  : e.key}：${e.value.join(' / ')}',
        )
        .join('\n');
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(source.name, style: Theme.of(context).textTheme.titleMedium),
            Text(SourceStrings.version(source.version, preferred)),
            Text(capabilities),
            Text(_status[entry.id] ?? SourceStrings.savedUnverified),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(SourceStrings.enable),
              value: source.enabled,
              onChanged: _busy
                  ? null
                  : (v) => setState(
                      () => _value = _value.replace(
                        entry.id,
                        source.copyWith(enabled: v),
                      ),
                    ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(SourceStrings.allowDownload),
              value: source.allowForDownloads,
              onChanged: _busy
                  ? null
                  : (v) => setState(
                      () => _value = _value.replace(
                        entry.id,
                        source.copyWith(allowForDownloads: v),
                      ),
                    ),
            ),
            Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: _busy || !source.enabled
                      ? null
                      : () => setState(() => _value = _value.prefer(entry.id)),
                  child: const Text(SourceStrings.prefer),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () =>
                            setState(() => _value = _value.move(entry.id, -1)),
                  child: const Text(SourceStrings.moveUp),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _value = _value.move(entry.id, 1)),
                  child: const Text(SourceStrings.moveDown),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          _link.text = source.origin.toString();
                          _import();
                        },
                  child: const Text(SourceStrings.update),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run((token) async {
                          try {
                            await widget.onInspect(source, token);
                          } on LxSourceException catch (error) {
                            if (mounted) {
                              setState(
                                () => _status[entry.id] =
                                    SourceStrings.inspectFailed(error.message),
                              );
                            }
                            rethrow;
                          }
                          if (mounted) {
                            setState(
                              () => _status[entry.id] =
                                  SourceStrings.inspectPassed,
                            );
                          }
                        }),
                  child: const Text(SourceStrings.inspect),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _remove(entry),
                  child: const Text(SourceStrings.remove),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
