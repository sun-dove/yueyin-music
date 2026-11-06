import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../l10n/video_strings.dart';
import '../../models/audio_quality.dart';
import '../../models/platform_type.dart';
import '../../models/song.dart';

enum CustomSourcePurpose { play, download }

enum CustomSourceFailureCode {
  notFound,
  qualityUnavailable,
  unauthorized,
  rateLimited,
  timeout,
  sourceUnavailable,
  invalidResponse,
  cancelled,
}

class CustomSourceConfigurationException implements Exception {
  const CustomSourceConfigurationException(this.field, this.message);

  final String field;
  final String message;

  @override
  String toString() => message;
}

class CustomSourceException implements Exception {
  const CustomSourceException({
    required this.code,
    required this.message,
    required this.retryable,
  });

  final CustomSourceFailureCode code;
  final String message;
  final bool retryable;

  @override
  String toString() => message;
}

@immutable
class CustomSourceConfig {
  const CustomSourceConfig({
    required this.id,
    required this.name,
    required this.endpoint,
    this.enabled = false,
    required this.platforms,
    this.timeoutSeconds = 10,
    this.allowForDownloads = false,
    this.credentialRef,
  });

  final String id;
  final String name;
  final Uri endpoint;
  final bool enabled;
  final Set<PlatformType> platforms;
  final int timeoutSeconds;
  final bool allowForDownloads;
  final String? credentialRef;

  void Function() get validate => () {
    if (name.trim().isEmpty) {
      throw const CustomSourceConfigurationException(
        'name',
        VideoStrings.customSourceNameRequired,
      );
    }
    if (endpoint.scheme != 'https' || endpoint.host.isEmpty) {
      throw const CustomSourceConfigurationException(
        'endpoint',
        VideoStrings.customSourceHttpsRequired,
      );
    }
    if (endpoint.userInfo.isNotEmpty) {
      throw const CustomSourceConfigurationException(
        'credentials',
        VideoStrings.customSourceCredentialsInUrl,
      );
    }
    if (timeoutSeconds < 1 || timeoutSeconds > 60) {
      throw const CustomSourceConfigurationException(
        'timeout',
        VideoStrings.customSourceTimeoutRange,
      );
    }
    if (platforms.isEmpty ||
        platforms.any(
          (platform) =>
              platform != PlatformType.qq && platform != PlatformType.netease,
        )) {
      throw const CustomSourceConfigurationException(
        'platforms',
        VideoStrings.customSourcePlatformRequired,
      );
    }
  };

  CustomSourceConfig copyWith({
    String? id,
    String? name,
    Uri? endpoint,
    bool? enabled,
    Set<PlatformType>? platforms,
    int? timeoutSeconds,
    bool? allowForDownloads,
    Object? credentialRef = _unset,
  }) => CustomSourceConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    endpoint: endpoint ?? this.endpoint,
    enabled: enabled ?? this.enabled,
    platforms: platforms ?? this.platforms,
    timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    allowForDownloads: allowForDownloads ?? this.allowForDownloads,
    credentialRef: identical(credentialRef, _unset)
        ? this.credentialRef
        : credentialRef as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'endpoint': endpoint.toString(),
    'enabled': enabled,
    'platforms': platforms.map((platform) => platform.name).toList(),
    'timeoutSeconds': timeoutSeconds,
    'allowForDownloads': allowForDownloads,
    if (credentialRef != null) 'credentialRef': credentialRef,
  };

  factory CustomSourceConfig.fromJson(Map<String, dynamic> json) =>
      CustomSourceConfig(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        endpoint: Uri.parse(json['endpoint']?.toString() ?? ''),
        enabled: json['enabled'] == true,
        platforms: {
          for (final name in (json['platforms'] as List? ?? const []))
            ?PlatformType.values
                .where((value) => value.name == name)
                .firstOrNull,
        },
        timeoutSeconds: (json['timeoutSeconds'] as num?)?.toInt() ?? 10,
        allowForDownloads: json['allowForDownloads'] == true,
        credentialRef: json['credentialRef']?.toString(),
      );

  @override
  bool operator ==(Object other) =>
      other is CustomSourceConfig &&
      other.id == id &&
      other.name == name &&
      other.endpoint == endpoint &&
      other.enabled == enabled &&
      setEquals(other.platforms, platforms) &&
      other.timeoutSeconds == timeoutSeconds &&
      other.allowForDownloads == allowForDownloads &&
      other.credentialRef == credentialRef;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    endpoint,
    enabled,
    Object.hashAllUnordered(platforms),
    timeoutSeconds,
    allowForDownloads,
    credentialRef,
  );
}

const Object _unset = Object();

@immutable
class CustomSourceRequest {
  const CustomSourceRequest({
    required this.requestId,
    required this.platform,
    required this.song,
    required this.quality,
    required this.purpose,
  });

  final String requestId;
  final PlatformType platform;
  final Song song;
  final AudioLevel quality;
  final CustomSourcePurpose purpose;
}

@immutable
class CustomSourceResult {
  const CustomSourceResult({
    required this.url,
    required this.actualQuality,
    this.format,
    this.bitrate,
    this.expiresAt,
    required this.sourceId,
    required this.sourceName,
  });

  final Uri url;
  final AudioLevel actualQuality;
  final String? format;
  final int? bitrate;
  final DateTime? expiresAt;
  final String sourceId;
  final String sourceName;
}

abstract interface class CustomSourceResolver {
  Future<CustomSourceResult> resolve(
    CustomSourceRequest request, {
    CancelToken? cancelToken,
  });
}
