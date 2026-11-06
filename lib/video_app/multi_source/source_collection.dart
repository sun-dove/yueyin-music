import '../../l10n/source_strings.dart';

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../lx_source/lx_source.dart';
import '../custom_source/custom_source_storage.dart';
import '../video_preferences.dart';

class SourceEntry {
  const SourceEntry(this.id, this.config);
  final String id;
  final LxSourceConfig config;
  Map<String, dynamic> toJson() => {'id': id, 'config': config.toJson()};
  factory SourceEntry.fromJson(Map<String, dynamic> value) => SourceEntry(
    value['id'] as String,
    LxSourceConfig.fromJson(Map<String, dynamic>.from(value['config'] as Map)),
  );
}

class SourceCollection {
  const SourceCollection({
    this.entries = const [],
    this.preferredId,
    this.autoSwitch = false,
    this.highestQuality = false,
    this.sourceFirst = false,
  });
  final List<SourceEntry> entries;
  final String? preferredId;
  final bool autoSwitch, highestQuality, sourceFirst;

  SourceEntry? get preferred =>
      entries
          .where((e) => e.id == preferredId && e.config.enabled)
          .firstOrNull ??
      entries.where((e) => e.config.enabled).firstOrNull;

  List<SourceEntry> get enabled {
    final first = preferred;
    return [
      ?first,
      ...entries.where((e) => e.config.enabled && e.id != first?.id),
    ];
  }

  SourceCollection copyWith({
    List<SourceEntry>? entries,
    String? preferredId,
    bool? autoSwitch,
    bool? highestQuality,
    bool? sourceFirst,
  }) => SourceCollection(
    entries: entries ?? this.entries,
    preferredId: preferredId ?? this.preferredId,
    autoSwitch: autoSwitch ?? this.autoSwitch,
    highestQuality: highestQuality ?? this.highestQuality,
    sourceFirst: sourceFirst ?? this.sourceFirst,
  );

  SourceCollection upsert(LxSourceConfig config) {
    final origin = lxImportUri(config.origin.toString()).toString();
    final id = sha256.convert(utf8.encode(origin)).toString();
    final old = entries.where((e) => e.id == id).firstOrNull;
    if (old != null) {
      return replace(
        id,
        config.copyWith(
          enabled: old.config.enabled,
          allowForDownloads: old.config.allowForDownloads,
        ),
      );
    }
    return copyWith(entries: [...entries, SourceEntry(id, config)]);
  }

  SourceCollection replace(String id, LxSourceConfig config) => copyWith(
    entries: [
      for (final entry in entries)
        if (entry.id == id) SourceEntry(id, config) else entry,
    ],
  );
  SourceCollection remove(String id) =>
      copyWith(entries: entries.where((e) => e.id != id).toList());
  SourceCollection prefer(String id) => copyWith(preferredId: id);
  SourceCollection move(String id, int delta) {
    final values = [...entries];
    final index = values.indexWhere((e) => e.id == id);
    if (index < 0) return this;
    final target = (index + delta).clamp(0, values.length - 1);
    values.insert(target, values.removeAt(index));
    return copyWith(entries: values);
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'entries': entries.map((e) => e.toJson()).toList(),
    'preferredId': preferredId,
    'autoSwitch': autoSwitch,
    'highestQuality': highestQuality,
    'sourceFirst': sourceFirst,
  };
  factory SourceCollection.fromJson(Map<String, dynamic> value) {
    if (value['schemaVersion'] != 1 || value['entries'] is! List) {
      throw const FormatException(SourceStrings.invalidCollection);
    }
    return SourceCollection(
      entries: (value['entries'] as List)
          .map((e) => SourceEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      preferredId: value['preferredId'] as String?,
      autoSwitch: value['autoSwitch'] == true,
      highestQuality: value['highestQuality'] == true,
      sourceFirst: value['sourceFirst'] == true,
    );
  }
  factory SourceCollection.fromLegacy(LxSourceConfig? config) => config == null
      ? const SourceCollection()
      : const SourceCollection().upsert(config);
}

/// 新键保存完整列表，旧键只镜像首选，旧页面与旧入口仍使用原契约。
class SourceSettings extends ChangeNotifier {
  SourceSettings(this.preferences);
  static const key = 'video.lxSource.collection.v1';
  final VideoPreferences preferences;
  SourceCollection value = const SourceCollection();
  String? loadError;

  void load() {
    final raw = preferences.box.get(key);
    if (raw == null) {
      value = SourceCollection.fromLegacy(preferences.lxSource);
      return;
    }
    try {
      value = SourceCollection.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw as String) as Map),
      );
    } catch (_) {
      value = SourceCollection.fromLegacy(preferences.lxSource);
      loadError = SourceStrings.collectionLoadFailed;
    }
  }

  Future<void> save(SourceCollection next) async {
    final preferred = next.preferred;
    final mirror =
        preferred?.config ?? preferences.lxSource?.copyWith(enabled: false);
    final http = preferred != null
        ? preferences.customSource?.copyWith(enabled: false)
        : preferences.customSource;
    await preferences.box.putAll({
      key: jsonEncode(next.toJson()),
      if (mirror != null) 'video.lxSource.config': jsonEncode(mirror.toJson()),
      if (http != null)
        HiveCustomSourcePreferenceStore.key: jsonEncode(http.toJson()),
    });
    preferences.lxSource = mirror;
    preferences.customSource = http;
    value = next;
    loadError = null;
    notifyListeners();
  }
}
