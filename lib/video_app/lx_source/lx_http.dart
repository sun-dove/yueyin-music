import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../l10n/video_strings.dart';
import 'lx_source.dart';

bool lxPublicAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  if (bytes.length == 16) return bytes[0] >= 0x20 && bytes[0] <= 0x3f;
  final a = bytes[0], b = bytes[1];
  return !(a == 0 ||
      a == 10 ||
      a == 127 ||
      a >= 224 ||
      (a == 100 && b >= 64 && b <= 127) ||
      (a == 169 && b == 254) ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && (b == 168 || b == 0)) ||
      (a == 198 && (b == 18 || b == 19)));
}

Dio createLxDio() {
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.findProxy = (_) => 'DIRECT';
      client.connectionFactory = (uri, _, _) async {
        if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
          throw const LxSourceException('network', VideoStrings.lxInvalidLink);
        }
        final addresses = await InternetAddress.lookup(uri.host);
        if (addresses.isEmpty || addresses.any((a) => !lxPublicAddress(a))) {
          throw const LxSourceException(
            'network',
            VideoStrings.lxPrivateNetwork,
          );
        }
        // lookup 返回的 InternetAddress 保留原域名，TLS 据此验证证书与 SNI。
        final address = addresses.firstWhere(
          (a) => a.type == InternetAddressType.IPv4,
          orElse: () => addresses.first,
        );
        return SecureSocket.startConnect(address, uri.port);
      };
      return client;
    },
  );
  return dio;
}
