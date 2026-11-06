import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'custom_source_models.dart';

abstract interface class CustomSourcePreferenceStore {
  Future<CustomSourceConfig?> load();
  Future<void> save(CustomSourceConfig config);
  Future<void> delete();
}

class HiveCustomSourcePreferenceStore implements CustomSourcePreferenceStore {
  HiveCustomSourcePreferenceStore(this.box);

  static const key = 'video.customSource.config';
  final Box box;

  @override
  Future<CustomSourceConfig?> load() async {
    final value = box.get(key);
    if (value is! String || value.isEmpty) return null;
    return CustomSourceConfig.fromJson(
      jsonDecode(value) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> save(CustomSourceConfig config) =>
      box.put(key, jsonEncode(config.toJson()));

  @override
  Future<void> delete() => box.delete(key);
}

class MemoryCustomSourcePreferenceStore implements CustomSourcePreferenceStore {
  String? serializedValue;

  @override
  Future<CustomSourceConfig?> load() async => serializedValue == null
      ? null
      : CustomSourceConfig.fromJson(
          jsonDecode(serializedValue!) as Map<String, dynamic>,
        );

  @override
  Future<void> save(CustomSourceConfig config) async {
    serializedValue = jsonEncode(config.toJson());
  }

  @override
  Future<void> delete() async => serializedValue = null;
}

abstract interface class CustomSourceCredentialStore {
  static String tokenKey(String sourceId) =>
      'video.customSource.$sourceId.token';

  Future<String?> readToken(String sourceId);
  Future<void> writeToken(String sourceId, String token);
  Future<void> deleteToken(String sourceId);
}

class SecureCustomSourceCredentialStore implements CustomSourceCredentialStore {
  const SecureCustomSourceCredentialStore([
    this.storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage storage;

  @override
  Future<String?> readToken(String sourceId) =>
      storage.read(key: CustomSourceCredentialStore.tokenKey(sourceId));

  @override
  Future<void> writeToken(String sourceId, String token) async {
    final value = token.trim();
    if (value.isEmpty) return deleteToken(sourceId);
    await storage.write(
      key: CustomSourceCredentialStore.tokenKey(sourceId),
      value: value,
    );
  }

  @override
  Future<void> deleteToken(String sourceId) =>
      storage.delete(key: CustomSourceCredentialStore.tokenKey(sourceId));
}

class MemoryCustomSourceCredentialStore implements CustomSourceCredentialStore {
  MemoryCustomSourceCredentialStore([Map<String, String>? values])
    : _values = {...?values};

  final Map<String, String> _values;

  @override
  Future<String?> readToken(String sourceId) async => _values[sourceId];

  @override
  Future<void> writeToken(String sourceId, String token) async {
    _values[sourceId] = token;
  }

  @override
  Future<void> deleteToken(String sourceId) async => _values.remove(sourceId);
}
