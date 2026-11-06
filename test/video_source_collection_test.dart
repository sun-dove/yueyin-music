import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/video_app/video_preferences.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/multi_source/source_collection.dart';

LxSourceConfig source(String name, {bool enabled = false}) => LxSourceConfig(
  name: name,
  version: '1',
  origin: Uri.parse('https://example.com/$name.js'),
  script: 'fixture',
  sha256: name,
  sources: const {
    'tx': ['128k', 'flac'],
  },
  enabled: enabled,
);

void main() {
  test('保存失败不更新内存或旧首选，整批写入成功后可重新加载', () async {
    final box = _Box();
    final prefs = VideoPreferences(box)..lxSource = source('旧源', enabled: true);
    final settings = SourceSettings(prefs)..load();
    final next = settings.value.upsert(source('新源', enabled: true));
    box.fail = true;
    await expectLater(settings.save(next), throwsStateError);
    expect(settings.value.entries, hasLength(1));
    expect(box.data, isEmpty);
    expect(prefs.lxSource!.name, '旧源');
    box.fail = false;
    await settings.save(next);
    final loaded = SourceSettings(prefs)..load();
    expect(loaded.value.entries, hasLength(2));
    expect(box.batches, 2);
  });
  test('保存16个源并重新读取，数量和顺序不丢失', () {
    var collection = const SourceCollection();
    for (var i = 0; i < 16; i++) {
      collection = collection.upsert(source('源$i'));
    }
    final loaded = SourceCollection.fromJson(collection.toJson());
    expect(
      loaded.entries.map((e) => e.config.name),
      List.generate(16, (i) => '源$i'),
    );
    expect(loaded.autoSwitch, isFalse);
    expect(loaded.highestQuality, isFalse);
    expect(loaded.sourceFirst, isFalse);
  });
  test('更新同链接保留启用和排序，同名不同链接不合并', () {
    var collection = const SourceCollection()
        .upsert(source('A', enabled: true))
        .upsert(source('B'));
    final id = collection.entries.first.id;
    collection = collection.upsert(source('A'));
    expect(collection.entries, hasLength(2));
    expect(collection.entries.first.id, id);
    expect(collection.entries.first.config.enabled, isTrue);
    collection = collection.move(id, 1).prefer(id);
    expect(collection.entries.last.id, id);
    expect(collection.preferred!.id, id);
    collection = collection.remove(id);
    expect(collection.preferred, isNull);
  });
  test('旧源迁移保留开关下载权限，首选失效回退首个启用源', () {
    final old = source('旧源', enabled: true).copyWith(allowForDownloads: true);
    var collection = SourceCollection.fromLegacy(old)
        .upsert(source('B', enabled: true));
    expect(collection.preferred!.config.allowForDownloads, isTrue);
    final first = collection.entries.first;
    collection = collection.replace(
      first.id,
      first.config.copyWith(enabled: false),
    );
    expect(collection.preferred!.config.name, 'B');
    expect(collection.entries.first.config.enabled, isFalse);
  });
}

class _Box extends Fake implements Box {
  final data = <dynamic, dynamic>{};
  bool fail = false;
  int batches = 0;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    data[key] = value;
  }

  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) async {
    batches++;
    if (fail) throw StateError('写入失败');
    data.addAll(entries);
  }
}
