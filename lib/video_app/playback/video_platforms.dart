import '../../core/network/api_exception.dart';
import '../../core/network/platform_http.dart';
import '../../core/storage/session_storage.dart';
import '../../lyrics/models/lyrics_bundle.dart';
import '../../models/audio_quality.dart';
import '../../models/platform_type.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../models/user.dart';
import '../../platform/base/music_platform.dart';
import '../../platform/netease/netease_platform.dart';
import '../../platform/qq/qq_platform.dart';
import '../custom_source/custom_source_playback.dart';
import '../custom_source/custom_source_models.dart';

/// 本次取流响应中的信息；服务端没有给出的值保持未知。
/// QQ 的格式来自非空资源地址，表示资源声明，不能代替媒体探测出的码率。
class VideoStreamInfo {
  const VideoStreamInfo({
    required this.platform,
    required this.songId,
    required this.requestedQuality,
    this.actualQuality,
    this.actualFormat,
    this.actualBitrate,
    this.isPreview,
    this.customSourceName,
  });

  final PlatformType platform;
  final String songId;
  final AudioLevel requestedQuality;
  final AudioLevel? actualQuality;
  final String? actualFormat;
  final int? actualBitrate;
  final bool? isPreview;
  final String? customSourceName;
}

class VideoQqPlatform extends QqPlatform {
  VideoQqPlatform({super.api, this.onResolved, bool Function()? useOgg640})
    : _useOgg640 = useOgg640 ?? (() => false);

  final void Function(VideoStreamInfo)? onResolved;
  final bool Function() _useOgg640;
  final String _guid =
      ((DateTime.now().microsecondsSinceEpoch % 9000000000) + 1000000000)
          .toString();
  bool _hasVerifiedOgg640 = false;

  bool get hasVerifiedOgg640 => _hasVerifiedOgg640;

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) async {
    final ogg = quality == AudioLevel.high && _useOgg640();
    final Map<String, dynamic> response;
    try {
      response = ogg
          ? await _getOggUrl(songId)
          : await api.getSongUrl(songId, quality: quality);
    } on Object catch (error) {
      throw apiExceptionOf(error);
    }
    final request = response['req_1'];
    final data = request is Map ? request['data'] : null;
    final entries = data is Map ? data['midurlinfo'] : null;
    final entry = entries is List && entries.isNotEmpty ? entries.first : null;
    if (entry is! Map) {
      throw SongNotAvailableException(platform: platformName);
    }
    final purl = entry['purl']?.toString() ?? '';
    // filename 可能只是原样回显请求的候选文件，purl 才是返回的资源。
    final actualFormat = purl.isEmpty ? null : _fileFormat(purl);
    final actualBitrate = purl.isEmpty
        ? null
        : _positiveInt(entry['br'] ?? entry['bitrate']);
    final actualQuality = purl.isEmpty ? null : _qqResourceQuality(purl);
    final preview = entry.containsKey('freeTrialInfo')
        ? entry['freeTrialInfo'] != null
        : null;
    onResolved?.call(
      VideoStreamInfo(
        platform: platformType,
        songId: songId,
        requestedQuality: quality,
        actualQuality: actualQuality,
        actualFormat: actualFormat,
        actualBitrate: actualBitrate,
        isPreview: preview,
      ),
    );
    if (preview == true) throw NoVipMembershipException(platformName);
    if (purl.isEmpty) {
      throw SongNotAvailableException(platform: platformName);
    }
    final prefix = _fileName(purl).toUpperCase();
    final expectedPrefix = ogg ? 'O801' : _qqPrefixFor(quality);
    if ((actualQuality != null && !prefix.startsWith(expectedPrefix)) ||
        (ogg && actualFormat != null && actualFormat != 'ogg') ||
        (!ogg &&
            quality.index >= AudioLevel.lossless.index &&
            actualFormat != null &&
            actualFormat != 'flac')) {
      throw QualityNotAvailableException();
    }
    _hasVerifiedOgg640 = actualFormat == 'ogg' && actualBitrate == 640000;
    final sip = data is Map ? data['sip'] : null;
    final cdn = sip is List && sip.isNotEmpty ? sip.first.toString() : '';
    return Uri.tryParse(purl)?.hasScheme == true ? purl : '$cdn$purl';
  }

  Future<Map<String, dynamic>> _getOggUrl(String songId) {
    final cookies = <String, String>{};
    for (final part in (api.cookie ?? '').split(';')) {
      final separator = part.indexOf('=');
      if (separator > 0) {
        cookies[part.substring(0, separator).trim()] = part
            .substring(separator + 1)
            .trim();
      }
    }
    final uin =
        (cookies['qqmusic_uin'] ?? cookies['uin'] ?? cookies['loginUin'] ?? '0')
            .replaceAll(RegExp(r'\D'), '');
    return api.musicu({
      'comm': {'ct': 19, 'cv': 1845, 'uin': uin},
      'loginUin': uin,
      'req_0': {
        'module': 'CDN.SrfCdnDispatchServer',
        'method': 'GetCdnDispatch',
        'param': {'guid': _guid, 'calltype': 0, 'userip': ''},
      },
      'req_1': {
        'module': 'vkey.GetVkeyServer',
        'method': 'CgiGetVkey',
        'param': {
          'guid': _guid,
          'songmid': [songId],
          'songtype': [0],
          'uin': uin,
          'loginflag': 1,
          'platform': '20',
          'filename': ['O801$songId$songId.ogg'],
        },
      },
    });
  }
}

class VideoNeteasePlatform extends NeteasePlatform {
  VideoNeteasePlatform({super.api, this.onResolved});

  final void Function(VideoStreamInfo)? onResolved;

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) async {
    final Map<String, dynamic> response;
    try {
      response = await api.getSongUrl(songId, level: _neteaseLevelFor(quality));
    } on Object catch (error) {
      throw apiExceptionOf(error);
    }
    final entries = response['data'];
    final data = entries is List && entries.isNotEmpty ? entries.first : null;
    if (data is! Map) {
      throw SongNotAvailableException(platform: platformName);
    }
    final returnedLevel = data['level']?.toString();
    AudioLevel? actualQuality;
    for (final value in AudioLevel.values) {
      if (_neteaseLevelFor(value) == returnedLevel) {
        actualQuality = value;
        break;
      }
    }
    final url = data['url']?.toString() ?? '';
    final preview = data.containsKey('freeTrialInfo')
        ? data['freeTrialInfo'] != null
        : null;
    onResolved?.call(
      VideoStreamInfo(
        platform: platformType,
        songId: songId,
        requestedQuality: quality,
        actualQuality: actualQuality,
        actualFormat: data['type']?.toString() ?? _fileFormat(url),
        actualBitrate: _positiveInt(data['br']),
        isPreview: preview,
      ),
    );
    if (preview == true) throw NoVipMembershipException(platformName);
    if (url.isEmpty) {
      if ((_positiveInt(data['fee']) ?? 0) >= 1) {
        throw NoVipMembershipException(platformName);
      }
      throw SongNotAvailableException(platform: platformName);
    }
    if ((actualQuality != null && actualQuality.index < quality.index) ||
        returnedLevel == 'none') {
      throw QualityNotAvailableException();
    }
    return url;
  }
}

/// 只给播放器使用；下载继续直接使用同一个已登录的平台实例。
class VideoPlaybackPlatform extends MusicPlatform {
  VideoPlaybackPlatform(
    this.delegate, {
    required this.requestedQuality,
    this.song,
    this.customSourceFallback,
  });

  final MusicPlatform delegate;
  final AudioLevel Function() requestedQuality;
  final Song? song;
  final CustomSourcePlaybackFallback? customSourceFallback;

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) async {
    if (quality != requestedQuality()) {
      throw QualityNotAvailableException();
    }
    try {
      return await delegate.getSongUrl(songId, quality: quality);
    } on Object catch (error) {
      final fallback = customSourceFallback;
      final currentSong =
          song ?? fallback?.songFor(delegate.platformType, songId);
      if (currentSong == null || fallback == null) rethrow;
      try {
        final result = await fallback.resolve(currentSong, quality, error);
        if (result == null) rethrow;
        return result.url.toString();
      } on CustomSourceException catch (sourceError) {
        final official = apiExceptionOf(error);
        throw ApiException(
          message: '${official.message}；${sourceError.message}',
          code: official.code,
          platform: official.platform,
          suggestedQuality: official.suggestedQuality,
        );
      }
    }
  }

  @override
  PlatformType get platformType => delegate.platformType;
  @override
  String get platformName => delegate.platformName;
  @override
  bool get isLoggedIn => delegate.isLoggedIn;
  @override
  Future<QrLoginResult> getQrCode() => delegate.getQrCode();
  @override
  Stream<QrLoginStatus> pollQrStatus(String key) => delegate.pollQrStatus(key);
  @override
  Future<LoginResult> sendPhoneCode(String phone) =>
      delegate.sendPhoneCode(phone);
  @override
  Future<LoginResult> loginByPhone(String phone, String code) =>
      delegate.loginByPhone(phone, code);
  @override
  Future<User?> getUserInfo() => delegate.getUserInfo();
  @override
  Future<void> logout() => delegate.logout();
  @override
  Future<void> saveSession(SessionStorage storage) =>
      delegate.saveSession(storage);
  @override
  Future<void> restoreSession(SessionStorage storage) =>
      delegate.restoreSession(storage);
  @override
  Future<List<Song>> search(String keyword, {int page = 1, int limit = 30}) =>
      delegate.search(keyword, page: page, limit: limit);
  @override
  Future<List<AudioQuality>> getAvailableQualities(String songId) =>
      delegate.getAvailableQualities(songId);
  @override
  Future<String?> getLyrics(String songId) => delegate.getLyrics(songId);
  @override
  Future<LyricsBundle?> getLyricsBundle(String songId) =>
      delegate.getLyricsBundle(songId);
  @override
  Future<List<Playlist>> getUserPlaylists() => delegate.getUserPlaylists();
  @override
  Future<List<Song>> getPlaylistDetail(String playlistId) =>
      delegate.getPlaylistDetail(playlistId);
  @override
  Future<List<Song>> getLikedSongs() => delegate.getLikedSongs();
  @override
  Future<bool> likeSong(String songId, {bool like = true}) =>
      delegate.likeSong(songId, like: like);
  @override
  Future<List<Song>> getDailyRecommendations() =>
      delegate.getDailyRecommendations();
  @override
  Future<List<Song>> getRankingList() => delegate.getRankingList();
  @override
  Future<VipLevel> getVipStatus() => delegate.getVipStatus();
  @override
  Future<Playlist?> parseShareLink(String url) => delegate.parseShareLink(url);
}

String _fileName(String value) =>
    (Uri.tryParse(value)?.path ?? value).split('/').last;

String? _fileFormat(String value) {
  final name = _fileName(value);
  final dot = name.lastIndexOf('.');
  return dot < 0 ? null : name.substring(dot + 1).toLowerCase();
}

int? _positiveInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return parsed != null && parsed > 0 ? parsed : null;
}

AudioLevel? _qqResourceQuality(String filename) {
  final name = _fileName(filename).toUpperCase();
  for (final entry in {
    'M500': AudioLevel.low,
    'M800': AudioLevel.high,
    'O801': AudioLevel.high,
    'F000': AudioLevel.lossless,
    'RS01': AudioLevel.hires,
    'Q000': AudioLevel.spatial,
    'Q001': AudioLevel.dolby,
    'AI00': AudioLevel.master,
  }.entries) {
    if (name.startsWith(entry.key)) return entry.value;
  }
  return null;
}

String _qqPrefixFor(AudioLevel quality) => switch (quality) {
  AudioLevel.low => 'M500',
  AudioLevel.medium || AudioLevel.high => 'M800',
  AudioLevel.lossless => 'F000',
  AudioLevel.hires => 'RS01',
  AudioLevel.spatial => 'Q000',
  AudioLevel.dolby => 'Q001',
  AudioLevel.master => 'AI00',
};

String _neteaseLevelFor(AudioLevel quality) => switch (quality) {
  AudioLevel.low => 'standard',
  AudioLevel.medium => 'higher',
  AudioLevel.high => 'exhigh',
  AudioLevel.lossless => 'lossless',
  AudioLevel.hires => 'hires',
  AudioLevel.spatial => 'jyeffect',
  AudioLevel.dolby => 'sky',
  AudioLevel.master => 'jymaster',
};
