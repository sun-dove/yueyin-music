import '../../l10n/source_strings.dart';

import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/network/api_exception.dart';
import '../../models/audio_quality.dart';
import '../../platform/qq/qq_endpoints.dart';
import '../../platform/qq/qq_api.dart';
import 'video_qq_api.dart';

class QqSongMetadata {
  const QqSongMetadata({
    required this.songMid,
    this.songId,
    this.mediaMid,
    this.songType,
  });
  final String songMid;
  final int? songId, songType;
  final String? mediaMid;
  Map<String, dynamic> get lxInfo => {
    'songmid': songMid,
    if (songId != null) 'songId': songId,
    if (mediaMid != null) 'strMediaMid': mediaMid,
    if (songType != null) 'songtype': songType,
  };
}

class QqMetadataStore {
  final _values = <String, QqSongMetadata>{};
  QqSongMetadata? lookup(String id) => _values[id];
  void capture(Object? value) {
    if (value is List) {
      for (final item in value) {
        capture(item);
      }
      return;
    }
    if (value is! Map) return;
    final mid = (value['mid'] ?? value['songmid'])?.toString();
    final id = int.tryParse('${value['id'] ?? value['songid']}');
    final file = value['file'];
    if (mid != null &&
        mid.isNotEmpty &&
        (file is Map ||
            value.containsKey('songid') ||
            value.containsKey('songtype'))) {
      final previous = _values[mid];
      final media = (file is Map ? file['media_mid'] : value['strMediaMid'])
          ?.toString();
      final info = QqSongMetadata(
        songMid: mid,
        songId: id ?? previous?.songId,
        mediaMid: media?.isNotEmpty == true ? media : previous?.mediaMid,
        songType:
            int.tryParse('${value['type'] ?? value['songtype']}') ??
            previous?.songType,
      );
      _values[mid] = info;
      if (info.songId != null) _values['${info.songId}'] = info;
    }
    for (final child in value.values) {
      if (child is Map || child is List) capture(child);
    }
  }
}

/// 独立入口的新取流适配器；旧 QqApi 和 VideoQqApi 保持原实现。
class VideoQqPlaybackApi extends VideoQqApi {
  VideoQqPlaybackApi({super.dio, QqMetadataStore? metadata})
    : _requestDio = dio,
      metadata = metadata ?? QqMetadataStore();
  final Dio? _requestDio;
  final QqMetadataStore metadata;
  final _details = <String, Future<QqSongMetadata?>>{};
  static final _requestToken = Object();
  Future<T> withCancellation<T>(
    CancelToken token,
    Future<T> Function() request,
  ) => runZoned(request, zoneValues: {_requestToken: token});
  final String _guid =
      (DateTime.now().microsecondsSinceEpoch % 9000000000 + 1000000000)
          .toString();
  @override
  Future<Map<String, dynamic>> musicu(Map<String, dynamic> data) async {
    final token = Zone.current[_requestToken] as CancelToken?;
    final response = token == null || _requestDio == null
        ? await super.musicu(data)
        : QqApi.responseMapOf(
            (await _requestDio.post(
              QqEndpoints.musicu,
              data: data,
              cancelToken: token,
              options: Options(
                contentType: Headers.jsonContentType,
                responseType: ResponseType.json,
              ),
            )).data,
          );
    metadata.capture(response);
    return response;
  }

  Future<QqSongMetadata?> ensureMetadata(String id) async {
    final existing = metadata.lookup(id);
    if (existing?.mediaMid != null && existing?.songId != null) return existing;
    Future<QqSongMetadata?> fetch() async {
      final response = await musicu({
        'comm': {'ct': 19, 'cv': 1845},
        'req_0': {
          'module': 'music.pf_song_detail_svr',
          'method': 'get_song_detail_yqq',
          'param': {
            if (int.tryParse(id) != null)
              'song_id': int.parse(id)
            else
              'song_mid': id,
          },
        },
      });
      metadata.capture(response);
      return metadata.lookup(id);
    }

    if (Zone.current[_requestToken] != null) return fetch();
    final pending = _details.putIfAbsent(id, fetch);
    try {
      return await pending;
    } finally {
      if (identical(_details[id], pending)) {
        unawaited(_details.remove(id));
      }
    }
  }

  @override
  Future<Map<String, dynamic>> getSongUrl(
    String songMid, {
    AudioLevel quality = AudioLevel.low,
  }) async {
    QqSongMetadata? info = metadata.lookup(songMid);
    try {
      info = await ensureMetadata(songMid) ?? info;
    } catch (_) {
      /* 详情不可用时保留已有MID回退。 */
    }
    final token = Zone.current[_requestToken] as CancelToken?;
    if (token?.isCancelled == true) throw token!.cancelError!;
    if (info == null && int.tryParse(songMid) != null) {
      throw ApiException(message: SourceStrings.qqMetadataMissing);
    }
    final cookies = <String, String>{};
    for (final part in (cookie ?? '').split(';')) {
      final separator = part.indexOf('=');
      if (separator > 0) {
        cookies[part.substring(0, separator).trim()] = part
            .substring(separator + 1)
            .trim();
      }
    }
    final uin = (cookies['qqmusic_uin'] ?? cookies['uin'] ?? '0').replaceAll(
      RegExp(r'\D'),
      '',
    );
    final key = cookies['qm_keyst'] ?? cookies['qqmusic_key'];
    final mid = info?.songMid ?? songMid;
    final file = info?.mediaMid ?? '$mid$mid';
    final prefix = switch (quality) {
      AudioLevel.low => 'M500',
      AudioLevel.medium || AudioLevel.high => 'M800',
      AudioLevel.lossless => 'F000',
      AudioLevel.hires => 'RS01',
      AudioLevel.spatial => 'Q000',
      AudioLevel.dolby => 'Q001',
      AudioLevel.master => 'AI00',
    };
    final extension = quality.index >= AudioLevel.lossless.index
        ? 'flac'
        : 'mp3';
    final response = await musicu({
      'comm': {
        'ct': 19,
        'cv': 1845,
        'uin': uin,
        'authst': ?key,
        if (key != null) 'tmeLoginType': 2,
      },
      'req_1': {
        'module': 'music.vkey.GetVkey',
        'method': 'UrlGetVkey',
        'param': {
          'uin': uin,
          'guid': _guid,
          'songmid': [mid],
          'songtype': [info?.songType ?? 0],
          'filename': ['$prefix$file.$extension'],
          'ctx': 0,
        },
      },
    });
    final module = response['req_1'];
    final codes = [response['code'], if (module is Map) module['code']];
    if (codes.any((c) => int.tryParse('$c') == 1000)) {
      throw LoginExpiredException();
    }
    if (codes.any((c) => c != null && int.tryParse('$c') != 0)) {
      throw ApiException(
        message: SourceStrings.qqPlaybackError,
        code: ApiErrorCode.requestFailed,
      );
    }
    return response;
  }
}
