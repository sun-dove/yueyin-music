import '../../l10n/video_strings.dart';

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/platform_http.dart';
import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/platform_type.dart';
import '../../models/song.dart';
import '../../platform/base/platform_registry.dart';
import '../../platform/netease/netease_api.dart';
import '../../platform/netease/netease_platform.dart';
import '../../platform/qq/qq_api.dart';
import '../../platform/qq/qq_platform.dart';

enum VideoFailureKind {
  notLoggedIn,
  sessionExpired,
  permission,
  network,
  unavailable,
  storageFull,
  storagePermission,
  invalidResponse,
  incomplete,
  cancelled,
  unknown,
}

class VideoFailure implements Exception {
  const VideoFailure(this.kind, this.message, {this.canRetry = false});

  final VideoFailureKind kind;
  final String message;
  final bool canRetry;

  factory VideoFailure.from(Object error) {
    if (error is VideoFailure) return error;
    if (error is FormatException || error is TypeError) {
      return const VideoFailure(
        VideoFailureKind.invalidResponse,
        VideoStrings.invalidResponse,
        canRetry: true,
      );
    }
    final apiError = apiExceptionOf(error);
    final kind = switch (apiError.code) {
      ApiErrorCode.loginExpired => VideoFailureKind.sessionExpired,
      ApiErrorCode.noVipMembership => VideoFailureKind.permission,
      ApiErrorCode.songNotAvailable ||
      ApiErrorCode.qualityNotAvailable ||
      ApiErrorCode.lyricsNotFound ||
      ApiErrorCode.notFound ||
      ApiErrorCode.unsupportedAction => VideoFailureKind.unavailable,
      ApiErrorCode.storageFull => VideoFailureKind.storageFull,
      ApiErrorCode.storagePermissionDenied =>
        VideoFailureKind.storagePermission,
      ApiErrorCode.network ||
      ApiErrorCode.requestTimeout ||
      ApiErrorCode.serverError => VideoFailureKind.network,
      ApiErrorCode.requestCancelled => VideoFailureKind.cancelled,
      ApiErrorCode.requestFailed ||
      ApiErrorCode.unknown => VideoFailureKind.unknown,
    };
    return VideoFailure(
      kind,
      kind == VideoFailureKind.unknown
          ? VideoStrings.operationFailed
          : apiError.message,
      canRetry:
          kind == VideoFailureKind.network || kind == VideoFailureKind.unknown,
    );
  }

  @override
  String toString() => message;
}

class VideoPage {
  const VideoPage({
    required this.songs,
    required this.page,
    required this.hasMore,
    this.total,
  });

  final List<Song> songs;
  final int? total;
  final int page;
  final bool hasMore;

  int? get nextPage => hasMore ? page + 1 : null;
}

class VideoLibrary {
  const VideoLibrary({
    this.songs = const [],
    this.total,
    this.complete = false,
    this.error,
  });

  final List<Song> songs;
  final int? total;
  final bool complete;
  final VideoFailure? error;

  int get loaded => songs.length;
}

/// 旧请求无论成功还是失败，都不能改写新查询的界面。
class LatestVideoQuery<T> {
  int _generation = 0;

  Future<T?> run(Future<T> Function() request) async {
    final generation = ++_generation;
    try {
      final value = await request();
      return generation == _generation ? value : null;
    } catch (_) {
      if (generation != _generation) return null;
      rethrow;
    }
  }

  void invalidate() => _generation++;
}

/// 请求档位和真实媒体信息分开；未知值不能当作已经验证的音质。
class VideoQualityEvidence {
  const VideoQualityEvidence({
    required this.requestedLabel,
    this.actualFormat,
    this.actualBitrate,
    this.isPreview,
  });

  final String requestedLabel;
  final String? actualFormat;
  final int? actualBitrate;
  final bool? isPreview;

  String? get actualLabel {
    final format = actualFormat?.trim().toUpperCase();
    if (format == null || format.isEmpty) return null;
    final bitrate = actualBitrate;
    return bitrate == null || bitrate <= 0
        ? format
        : '$format ${(bitrate / 1000).round()}';
  }

  bool? get matchesRequested {
    final format = actualFormat?.trim().toUpperCase();
    if (format == null || format.isEmpty) return null;
    final requested = requestedLabel.toUpperCase();
    final requestedFormat = RegExp(r'\b(MP3|OGG|AAC|FLAC|WAV)\b')
        .firstMatch(requested)
        ?.group(1);
    if (requestedFormat == null) return null;
    if (format != requestedFormat) return false;
    final requestedRate = int.tryParse(
      RegExp(r'(?:MP3|OGG|AAC|FLAC|WAV)\s+(\d+)')
              .firstMatch(requested)
              ?.group(1) ??
          '',
    );
    if (requestedRate == null) return true;
    if (actualBitrate == null || actualBitrate! <= 0) return null;
    return (actualBitrate! / 1000).round() == requestedRate;
  }
}

/// 视频入口专用适配器，复用已登录的底层 API，不改变原应用接口。
class VideoCatalog {
  VideoCatalog({QqApi? qqApi, NeteaseApi? neteaseApi, Dio? qqPublicDio})
    : _injectedQq = qqApi,
      _injectedNetease = neteaseApi,
      _qqPublicDio =
          qqPublicDio ??
          createPlatformDio(
            platform: PlatformType.qq,
            headers: {
              'User-Agent': 'Mozilla/5.0',
              'Referer': 'https://y.qq.com/',
            },
          );

  final QqApi? _injectedQq;
  final NeteaseApi? _injectedNetease;
  final Dio _qqPublicDio;
  final _qqSongIds = <String, String>{};

  QqApi get _qq =>
      _injectedQq ?? (PlatformRegistry.get(PlatformType.qq) as QqPlatform).api;
  NeteaseApi get _netease =>
      _injectedNetease ??
      (PlatformRegistry.get(PlatformType.netease) as NeteasePlatform).api;

  Future<VideoPage> search(
    PlatformType platform,
    String query, {
    int page = 1,
    int limit = 30,
  }) async {
    if (page < 1 || limit < 1) {
      throw ArgumentError(VideoStrings.positivePaginationRequired);
    }
    if (query.trim().isEmpty) {
      return VideoPage(songs: const [], page: page, hasMore: false, total: 0);
    }
    try {
      return switch (platform) {
        PlatformType.qq => await _searchQq(query.trim(), page, limit),
        PlatformType.netease => await _searchNetease(query.trim(), page, limit),
        _ => throw const VideoFailure(
          VideoFailureKind.unavailable,
          VideoStrings.searchUnsupported,
        ),
      };
    } catch (error) {
      throw VideoFailure.from(error);
    }
  }

  Future<VideoPage> _searchQq(String query, int page, int limit) async {
    final response = await _qq.search(query, page: page, limit: limit);
    // 实测桌面搜索匿名返回 2001；只对这个错误使用同平台公开读接口。
    final module = _map(response['req_0']);
    if (_int(response['code']) == 0 && _int(module['code']) == 2001) {
      final publicResponse = await _qqPublicDio.get(
        'https://c.y.qq.com/soso/fcgi-bin/client_search_cp',
        queryParameters: {'w': query, 'format': 'json', 'p': page, 'n': limit},
      );
      final payload = _responseMap(publicResponse.data);
      _checkCode(payload, PlatformType.qq);
      final data = _map(payload['data']);
      return _qqSearchPage(_map(data['song']), page, limit);
    }
    final data = _map(_qqModule(response)['data']);
    return _qqSearchPage(
      _map(_map(data['body'])['song']),
      page,
      limit,
      reportedTotal: _total(_map(data['meta'])),
    );
  }

  VideoPage _qqSearchPage(
    Map<dynamic, dynamic> payload,
    int page,
    int limit, {
    int? reportedTotal,
  }) {
    final total = _total(payload) ?? reportedTotal;
    final rows = _songRows(payload['list'], total: total);
    final songs = rows.map(_parseQqSong).toList(growable: false);
    return VideoPage(
      songs: songs,
      total: total,
      page: page,
      hasMore:
          rows.isNotEmpty &&
          (total == null ? rows.length >= limit : page * limit < total),
    );
  }

  Future<VideoPage> _searchNetease(String query, int page, int limit) async {
    final response = await _netease.search(query, page: page, limit: limit);
    _checkCode(response, PlatformType.netease);
    final result = _map(response['result']);
    final total = _int(result['songCount']);
    final rows = _songRows(result['songs'], total: total);
    return VideoPage(
      songs: rows.map(_parseNeteaseSong).toList(growable: false),
      total: total,
      page: page,
      hasMore:
          rows.isNotEmpty &&
          (total != null
              ? page * limit < total
              : result['hasMore'] is bool
              ? result['hasMore'] as bool
              : rows.length >= limit),
    );
  }

  Future<List<String>> hotSearch() async {
    try {
      final response = await _qqPublicDio.get(
        'https://c.y.qq.com/splcloud/fcgi-bin/gethotkey.fcg',
        queryParameters: {'format': 'json'},
      );
      final payload = _responseMap(response.data);
      _checkCode(payload, PlatformType.qq);
      final rows = _map(payload['data'])['hotkey'];
      if (rows is! List) throw _invalid();
      return rows
          .map((row) => _text([_map(row)['k']]))
          .whereType<String>()
          .toList(growable: false);
    } catch (error) {
      throw VideoFailure.from(error);
    }
  }

  Future<VideoLibrary> syncLikes(
    PlatformType platform, {
    required String userId,
    void Function(VideoLibrary)? onProgress,
  }) async {
    if (userId.trim().isEmpty) {
      return const VideoLibrary(
        error: VideoFailure(
          VideoFailureKind.notLoggedIn,
          VideoStrings.loginToViewLikes,
        ),
      );
    }
    return switch (platform) {
      PlatformType.qq => _syncQq(onProgress),
      PlatformType.netease => _syncNetease(userId, onProgress),
      _ => const VideoLibrary(
        error: VideoFailure(
          VideoFailureKind.unavailable,
          VideoStrings.syncUnsupported,
        ),
      ),
    };
  }

  Future<VideoLibrary> _syncQq(void Function(VideoLibrary)? onProgress) async {
    final songs = <String, Song>{};
    int? total;
    try {
      for (var page = 0; ; page++) {
        final response = await _qq.getLikedSongs(page: page, limit: 30);
        final data = _map(_qqModule(response)['data']);
        total = _total(data) ?? total;
        final rows = _songRows(data['songlist'], total: total);
        final previous = songs.length;
        for (final row in rows) {
          final song = _parseQqSong(row);
          songs[song.id] = song;
        }
        final complete = total != null
            ? songs.length >= total
            : rows.length < 30;
        final snapshot = VideoLibrary(
          songs: List.unmodifiable(songs.values),
          total: total,
          complete: complete,
        );
        onProgress?.call(snapshot);
        if (complete) return snapshot;
        if (rows.isEmpty || songs.length == previous) throw _incomplete();
      }
    } catch (error) {
      return VideoLibrary(
        songs: List.unmodifiable(songs.values),
        total: total,
        error: VideoFailure.from(error),
      );
    }
  }

  Future<VideoLibrary> _syncNetease(
    String userId,
    void Function(VideoLibrary)? onProgress,
  ) async {
    final songs = <String, Song>{};
    var order = <String>[];
    int? total;
    VideoLibrary snapshot({bool complete = false, VideoFailure? error}) {
      final orderedSongs = order.isEmpty
          ? songs.values
          : order.map((id) => songs[id]).whereType<Song>();
      return VideoLibrary(
        songs: List.unmodifiable(orderedSongs),
        total: total,
        complete: complete,
        error: error,
      );
    }

    try {
      String? likesId;
      final seenPlaylists = <String>{};
      for (var offset = 0; ; offset += 50) {
        final response = await _netease.getUserPlaylist(
          userId,
          limit: 50,
          offset: offset,
        );
        _checkCode(response, PlatformType.netease);
        final rows = response['playlist'];
        if (rows is! List) throw _invalid();
        final previous = seenPlaylists.length;
        for (final raw in rows) {
          final row = _map(raw);
          final id = _text([row['id']]);
          if (id != null) seenPlaylists.add(id);
          if (_int(row['specialType']) == 5 &&
              _text([_map(row['creator'])['userId']]) == userId) {
            likesId = id;
            break;
          }
        }
        if (likesId != null || response['more'] != true) break;
        if (rows.isEmpty || seenPlaylists.length == previous) {
          throw _incomplete();
        }
      }
      if (likesId == null) {
        throw const VideoFailure(
          VideoFailureKind.unavailable,
          VideoStrings.likesPlaylistNotFound,
        );
      }
      final detail = await _netease.getPlaylistDetail(likesId);
      _checkCode(detail, PlatformType.netease);
      final playlist = _map(detail['playlist']);
      total = _int(playlist['trackCount']);
      final tracks = _songRows(playlist['tracks'], total: total);
      for (final row in tracks) {
        final song = _parseNeteaseSong(row);
        songs[song.id] = song;
      }
      final trackIds = playlist['trackIds'];
      if (trackIds is List) {
        order = trackIds
            .map((row) => _text([_map(row)['id']]))
            .whereType<String>()
            .toSet()
            .toList();
        if (order.length != trackIds.length) throw _incomplete();
      } else {
        order = songs.keys.toList(growable: false);
        if (total == null || songs.length < total) throw _incomplete();
      }
      total ??= order.length;
      onProgress?.call(snapshot());
      final missing = order
          .where((id) => !songs.containsKey(id))
          .toList(growable: false);
      for (var begin = 0; begin < missing.length; begin += 200) {
        final end = (begin + 200).clamp(0, missing.length);
        final response = await _netease.getSongDetails(
          missing.sublist(begin, end),
        );
        _checkCode(response, PlatformType.netease);
        final rows = _songRows(response['songs']);
        for (final row in rows) {
          final song = _parseNeteaseSong(row);
          songs[song.id] = song;
        }
        onProgress?.call(snapshot());
      }
      if (order.any((id) => !songs.containsKey(id)) || order.length < total) {
        throw _incomplete();
      }
      return snapshot(complete: true);
    } catch (error) {
      return snapshot(error: VideoFailure.from(error));
    }
  }

  Future<void> setLiked(Song song, bool liked) async {
    try {
      switch (song.platform) {
        case PlatformType.qq:
          final songId = _qqSongIds[song.id];
          if (songId == null) {
            throw const VideoFailure(
              VideoFailureKind.unavailable,
              VideoStrings.songInfoMissing,
            );
          }
          final response = liked
              ? await _qq.likeSong(song.id, songId)
              : await _qq.unlikeSong(song.id, songId);
          _qqModule(response);
        case PlatformType.netease:
          _checkCode(
            await _netease.likeSong(song.id, like: liked),
            PlatformType.netease,
          );
        default:
          throw const VideoFailure(
            VideoFailureKind.unavailable,
            VideoStrings.likeUnsupported,
          );
      }
    } catch (error) {
      throw VideoFailure.from(error);
    }
  }

  Song _parseQqSong(dynamic raw) {
    var row = _map(raw);
    for (final key in const [
      'songInfo',
      'songData',
      'song',
      'musicData',
      'data',
    ]) {
      final inner = _map(row[key]);
      if (inner.containsKey('mid') ||
          inner.containsKey('songmid') ||
          inner.containsKey('singer')) {
        row = inner;
        break;
      }
    }
    final mid = _text([row['mid'], row['songmid'], row['songMid']]);
    final id = mid ?? _text([row['id'], row['songid']]);
    final name = _text([
      row['name'],
      row['title'],
      row['songname'],
      row['songName'],
    ]);
    if (id == null || name == null) throw _invalid();
    final numericId = _int(row['id'] ?? row['songid'] ?? row['songId']);
    if (numericId != null) _qqSongIds[id] = numericId.toString();
    final singers = row['singer'];
    final artists = singers is List
        ? singers
              .map((raw) {
                final singer = _map(raw);
                return Artist(
                  id: _text([singer['mid'], singer['id']]) ?? '',
                  name:
                      _text([singer['name'], singer['title']]) ??
                      VideoStrings.unknownArtist,
                );
              })
              .toList(growable: false)
        : <Artist>[];
    final album = _map(row['album']);
    final albumId = _text([album['mid'], row['albummid'], row['albumMid']]);
    final albumName = _text([
      album['name'],
      album['title'],
      row['albumname'],
      row['albumName'],
    ]);
    final cover = albumId == null
        ? _text([album['cover'], row['cover'], row['pic']])
        : 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$albumId.jpg';
    return Song(
      id: id,
      platform: PlatformType.qq,
      name: name,
      artists: artists,
      duration: Duration(
        seconds: _int(row['interval'] ?? row['duration']) ?? 0,
      ),
      album: albumName == null
          ? null
          : Album(id: albumId ?? '', name: albumName, coverUrl: cover),
      albumId: albumId,
      artistId: artists.isEmpty ? null : artists.first.id,
      coverUrl: cover,
    );
  }

  Song _parseNeteaseSong(dynamic raw) {
    final row = _map(raw);
    final id = _text([row['id']]);
    final name = _text([row['name']]);
    if (id == null || name == null) throw _invalid();
    final singers = row['ar'] ?? row['artists'];
    final artists = singers is List
        ? singers
              .map((raw) {
                final singer = _map(raw);
                return Artist(
                  id: _text([singer['id']]) ?? '',
                  name: _text([singer['name']]) ?? VideoStrings.unknownArtist,
                );
              })
              .toList(growable: false)
        : <Artist>[];
    final album = _map(row['al'] ?? row['album']);
    final albumId = _text([album['id']]);
    final albumName = _text([album['name']]);
    final cover = _text([album['picUrl']]);
    return Song(
      id: id,
      platform: PlatformType.netease,
      name: name,
      artists: artists,
      duration: Duration(milliseconds: _int(row['dt'] ?? row['duration']) ?? 0),
      album: albumName == null
          ? null
          : Album(id: albumId ?? '', name: albumName, coverUrl: cover),
      albumId: albumId,
      artistId: artists.isEmpty ? null : artists.first.id,
      coverUrl: cover,
      fee: _int(row['fee']),
      trackNumber: _int(row['no']),
    );
  }

  static Map<dynamic, dynamic> _qqModule(Map<dynamic, dynamic> response) {
    _checkCode(response, PlatformType.qq);
    final module = _map(response['req_0']);
    _checkCode(module, PlatformType.qq);
    return module;
  }

  static void _checkCode(
    Map<dynamic, dynamic> response,
    PlatformType platform,
  ) {
    final code = _int(response['code']);
    if (code == null) throw _invalid();
    if (code == (platform == PlatformType.qq ? 0 : 200)) return;
    if ((platform == PlatformType.qq && code == 1000) ||
        (platform == PlatformType.netease && (code == 301 || code == 302))) {
      SessionExpiryReporter.report(platform);
      throw const VideoFailure(
        VideoFailureKind.sessionExpired,
        VideoStrings.sessionExpired,
      );
    }
    if (code == 403) {
      throw const VideoFailure(
        VideoFailureKind.permission,
        VideoStrings.permissionDenied,
      );
    }
    throw VideoFailure(
      VideoFailureKind.unavailable,
      VideoStrings.rejectedOperation(code),
      canRetry: true,
    );
  }

  static Map<dynamic, dynamic> _map(dynamic value) =>
      value is Map ? value : const {};

  static Map<dynamic, dynamic> _responseMap(dynamic value) {
    if (value is String) value = jsonDecode(value);
    if (value is! Map) throw _invalid();
    return value;
  }

  static List<dynamic> _songRows(dynamic value, {int? total}) {
    if (value is List) return value;
    if (total == 0 && value == null) return const [];
    throw _invalid();
  }

  static int? _total(Map<dynamic, dynamic> value) {
    for (final key in const [
      'sum',
      'total',
      'totalnum',
      'total_num',
      'total_song_num',
      'songnum',
    ]) {
      final number = _int(value[key]);
      if (number != null && number >= 0) return number;
    }
    return null;
  }

  static int? _int(dynamic value) =>
      value is int ? value : int.tryParse('$value');

  static String? _text(List<dynamic> values) {
    for (final value in values) {
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return null;
  }

  static VideoFailure _invalid() => const VideoFailure(
    VideoFailureKind.invalidResponse,
    VideoStrings.invalidResponse,
    canRetry: true,
  );

  static VideoFailure _incomplete() => const VideoFailure(
    VideoFailureKind.incomplete,
    VideoStrings.libraryIncomplete,
    canRetry: true,
  );
}
