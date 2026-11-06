import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/audio_quality.dart';
import '../models/platform_type.dart';
import 'custom_source/custom_source_models.dart';
import 'custom_source/custom_source_storage.dart';
import 'lx_source/lx_source.dart';

/// 新入口使用独立键，不改变原入口已有设置的默认行为。
class VideoPreferences {
  VideoPreferences(this.box)
    : customSourceStore = HiveCustomSourcePreferenceStore(box);
  final Box box;
  final CustomSourcePreferenceStore customSourceStore;
  CustomSourceConfig? customSource;
  LxSourceConfig? lxSource;

  CustomSourceConfig? get activeSourceConfig =>
      lxSource?.enabled == true ? lxSource!.fallbackConfig : customSource;

  Future<void> loadLxSource() async {
    final value = box.get('video.lxSource.config');
    if (value is String) {
      try {
        lxSource = LxSourceConfig.fromJson(
          jsonDecode(value) as Map<String, dynamic>,
        );
      } catch (_) {
        lxSource = null;
      }
    }
  }

  Future<void> setLxSource(LxSourceConfig config) async {
    await box.put('video.lxSource.config', jsonEncode(config.toJson()));
    lxSource = config;
  }

  Future<void> deleteLxSource() async {
    await box.delete('video.lxSource.config');
    lxSource = null;
  }

  Future<void> loadCustomSource() async {
    customSource = await customSourceStore.load();
  }

  Future<void> setCustomSource(CustomSourceConfig config) async {
    config.validate();
    await customSourceStore.save(config);
    customSource = config;
  }

  Future<void> deleteCustomSource() async {
    await customSourceStore.delete();
    customSource = null;
  }

  AudioLevel quality(PlatformType platform, {bool download = false}) {
    final name = box.get(
      'video.${platform.name}.${download ? 'download' : 'play'}',
    );
    return AudioLevel.values.where((level) => level.name == name).firstOrNull ??
        AudioLevel.low;
  }

  Future<void> setQuality(
    PlatformType platform,
    AudioLevel level, {
    bool download = false,
  }) => box.put(
    'video.${platform.name}.${download ? 'download' : 'play'}',
    level.name,
  );
  String get theme => box.get('video.theme', defaultValue: 'light') as String;
  Future<void> setTheme(String value) => box.put('video.theme', value);
}
