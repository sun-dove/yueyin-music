import '../../core/network/api_exception.dart';
import '../../l10n/video_strings.dart';
import '../../platform/qq/qq_api.dart';

class VideoQqApi extends QqApi {
  VideoQqApi({super.dio});

  @override
  bool get requiresCompleteMusicSession => true;

  @override
  Future<String?> completeOAuthLogin(String redirectUrl) =>
      completeMusicOAuthLogin(redirectUrl);

  @override
  Future<Map<String, dynamic>> getLikedSongs({int page = 0, int limit = 50}) =>
      getMusicLikedSongs(page: page, limit: limit);

  @override
  Future<List<int>?> getQrImage() async {
    final bytes = await super.getQrImage();
    if (bytes == null || bytes.isEmpty) {
      throw _VideoQrUnavailableException();
    }
    return bytes;
  }

  @override
  Future<Map<String, dynamic>> checkQr() async {
    final response = await super.checkQr();
    final raw = response['raw'];
    if (raw is! String) return response;
    // 仅适配旧 QqPlatform 的反向映射，实际协议 66=待扫码、67=已扫码。
    final translated = raw.replaceFirstMapped(
      RegExp(r"(ptui[Cc]B\(')(66|67)(')"),
      (match) => "${match[1]}${match[2] == '66' ? '67' : '66'}${match[3]}",
    );
    return translated == raw ? response : {...response, 'raw': translated};
  }
}

class _VideoQrUnavailableException extends ApiException {
  _VideoQrUnavailableException() : super(message: VideoStrings.qqQrUnavailable);

  @override
  String toString() => message;
}
