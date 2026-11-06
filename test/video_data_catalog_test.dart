import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/platform/netease/netease_api.dart';
import 'package:mconnect/platform/qq/qq_api.dart';
import 'package:mconnect/video_app/data/video_catalog.dart';

void main() {
  group('视频同款：完整收藏与错误状态', () {
    test('QQ 的 76 首收藏跨越三页，不能停在默认前 50 首', () async {
      final api = _QqLikesApi();
      final progress = <int>[];
      final library = await VideoCatalog(qqApi: api).syncLikes(
        PlatformType.qq,
        userId: '123',
        onProgress: (value) => progress.add(value.loaded),
      );

      expect(api.pages, [0, 1, 2]);
      expect(library.complete, isTrue);
      expect(library.error, isNull);
      expect(library.total, 76);
      expect(
        library.songs.map((song) => song.id),
        List.generate(76, (i) => 'mid-$i'),
      );
      expect(progress, [30, 60, 76]);
    });

    test('跨页重复项只出现一次，仍获取后续所有页', () async {
      final api = _QqLikesApi(duplicateBoundary: true);
      final library = await VideoCatalog(qqApi: api)
          .syncLikes(PlatformType.qq, userId: '123');

      expect(library.error, isNull);
      expect(api.pages, [0, 1, 2]);
      expect(library.complete, isTrue);
      expect(library.songs.map((song) => song.id).toSet(), hasLength(76));
      expect(library.loaded, 76);
    });

    test('第二页网络失败时保留首 30 首，不能标成完整或空收藏', () async {
      final api = _QqLikesApi(failPage: 1);
      final library = await VideoCatalog(qqApi: api)
          .syncLikes(PlatformType.qq, userId: '123');

      expect(api.pages, [0, 1]);
      expect(library.loaded, 30);
      expect(library.complete, isFalse);
      expect(library.error?.kind, VideoFailureKind.network);
      expect(library.error?.canRetry, isTrue);
    });

    test('总数声称 76 但末页提前为空时不能静默截断', () async {
      final library = await VideoCatalog(qqApi: _QqLikesApi(emptyPage: 1))
          .syncLikes(PlatformType.qq, userId: '123');

      expect(library.loaded, 30);
      expect(library.total, 76);
      expect(library.complete, isFalse);
      expect(library.error?.kind, VideoFailureKind.incomplete);
    });

    test('真实空收藏可以完整，未登录必须是明确错误', () async {
      final api = _QqLikesApi(count: 0);
      final catalog = VideoCatalog(qqApi: api);
      final empty = await catalog.syncLikes(PlatformType.qq, userId: '123');
      expect(empty.complete, isTrue);
      expect(empty.error, isNull);
      expect(empty.loaded, 0);

      final loggedOut = await catalog.syncLikes(PlatformType.qq, userId: '');
      expect(loggedOut.complete, isFalse);
      expect(loggedOut.error?.kind, VideoFailureKind.notLoggedIn);
      expect(api.pages, [0]);
    });

    test('平台返回会话失效不能解释成没有收藏', () async {
      final library = await VideoCatalog(qqApi: _QqExpiredApi())
          .syncLikes(PlatformType.qq, userId: '123');
      expect(library.complete, isFalse);
      expect(library.error?.kind, VideoFailureKind.sessionExpired);
    });

    test('网易云按收藏类型及当前用户找喜欢歌单，不取第一个同名歌单', () async {
      final api = _NeteaseLikesApi();
      final library = await VideoCatalog(neteaseApi: api)
          .syncLikes(PlatformType.netease, userId: '42');

      expect(api.playlistOffsets, [0, 50]);
      expect(api.requestedPlaylistIds, ['owned-likes']);
      expect(library.complete, isTrue);
      expect(library.songs.map((song) => song.id), ['3', '1', '2']);
      expect(api.detailBatches, [
        ['1', '2'],
      ]);
    });

    test('网易云缺少可识别的喜欢歌单时明确报错，不回退到任意歌单', () async {
      final api = _NeteaseLikesApi(includeOwnLikes: false);
      final library = await VideoCatalog(neteaseApi: api)
          .syncLikes(PlatformType.netease, userId: '42');

      expect(library.complete, isFalse);
      expect(library.error?.kind, VideoFailureKind.unavailable);
      expect(api.requestedPlaylistIds, isEmpty);
    });

    test('网易云补全接口遗漏歌曲时保留部分结果并报告不完整', () async {
      final library = await VideoCatalog(
        neteaseApi: _NeteaseLikesApi(omitDetail: true),
      ).syncLikes(PlatformType.netease, userId: '42');

      expect(library.complete, isFalse);
      expect(library.total, 3);
      expect(library.loaded, 2);
      expect(library.error?.kind, VideoFailureKind.incomplete);
    });
  });

  group('视频同款：搜索、错误与真实音质', () {
    test('QQ 搜索保留总数和平台信息，末页终止分页', () async {
      final catalog = VideoCatalog(qqApi: _QqSearchApi());
      final first = await catalog.search(PlatformType.qq, '五月天');
      final last = await catalog.search(PlatformType.qq, '五月天', page: 3);

      expect(first.songs, hasLength(30));
      expect(first.songs.first.platform, PlatformType.qq);
      expect(first.total, 76);
      expect(first.hasMore, isTrue);
      expect(first.nextPage, 2);
      expect(last.songs, hasLength(16));
      expect(last.hasMore, isFalse);
      expect(last.nextPage, isNull);
    });

    test('QQ 当前真实响应的总数位于 meta.sum，不能丢失', () async {
      final result = await VideoCatalog(qqApi: _QqMetaSearchApi())
          .search(PlatformType.qq, '五月天', limit: 2);
      expect(result.total, 1009);
      expect(result.songs, hasLength(2));
      expect(result.nextPage, 2);
    });

    test('网易云总数未知时不伪造数量，按实际页判断继续', () async {
      final result = await VideoCatalog(neteaseApi: _NeteaseSearchApi())
          .search(PlatformType.netease, '搜索');
      expect(result.total, isNull);
      expect(result.songs.single.id, '8');
      expect(result.songs.single.artistNames, '歌手');
      expect(result.songs.single.duration.inMilliseconds, 123000);
      expect(result.hasMore, isFalse);
    });

    test('查询失败与真实零结果不同；非法结构不能假装空列表', () async {
      final catalog = VideoCatalog(qqApi: _QqMalformedApi());
      await expectLater(
        catalog.search(PlatformType.qq, '搜索'),
        throwsA(
          isA<VideoFailure>().having(
            (error) => error.kind,
            'kind',
            VideoFailureKind.invalidResponse,
          ),
        ),
      );
    });

    test('QQ 桌面搜索返回 2001 时使用已核实的同平台公开读接口', () async {
      final requests = <RequestOptions>[];
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'code': 0,
                  'data': {
                    'song': {
                      'totalnum': 1,
                      'list': [_qqSong(1)],
                    },
                  },
                },
              ),
            );
          },
        ),
      );
      final result = await VideoCatalog(
        qqApi: _QqBlockedSearchApi(),
        qqPublicDio: dio,
      ).search(PlatformType.qq, '五月天');

      expect(result.total, 1);
      expect(result.songs.single.id, 'mid-1');
      expect(requests.single.uri.host, 'c.y.qq.com');
      expect(requests.single.queryParameters['w'], '五月天');
      expect(requests.single.queryParameters['p'], 1);
    });

    test('较旧搜索迟到时不能覆盖较新的查询结果', () async {
      final tracker = LatestVideoQuery<String>();
      final slow = Completer<String>();
      final oldRequest = tracker.run(() => slow.future);
      final newRequest = await tracker.run(() async => '最新结果');
      slow.complete('旧结果');

      expect(newRequest, '最新结果');
      expect(await oldRequest, isNull);
    });

    test('较旧查询失败时也不能污染较新查询', () async {
      final tracker = LatestVideoQuery<String>();
      final slow = Completer<String>();
      final oldRequest = tracker.run(() => slow.future);
      expect(await tracker.run(() async => '新结果'), '新结果');
      slow.completeError(NetworkException());
      expect(await oldRequest, isNull);
    });

    test('热搜来自真实平台结构，去除空白并保留顺序', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.uri.host, 'c.y.qq.com');
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'code': 0,
                  'data': {
                    'hotkey': [
                      {'k': ' 五月天 '},
                      {'k': '周杰伦'},
                      {'k': ''},
                    ],
                  },
                },
              ),
            );
          },
        ),
      );
      expect(await VideoCatalog(qqPublicDio: dio).hotSearch(), ['五月天', '周杰伦']);
    });

    test('QQ 收藏写入使用 mid 和真实数字 ID，不能把 mid 当数字 ID', () async {
      final api = _QqWriteApi();
      final catalog = VideoCatalog(qqApi: api);
      final result = await catalog.search(PlatformType.qq, '歌曲');
      await catalog.setLiked(result.songs.single, true);
      expect(api.writeMid, 'mid-9');
      expect(api.writeId, '9009');
    });

    test('QQ 收藏写入被平台拒绝时不能报成功', () async {
      final api = _QqWriteApi(expired: true);
      final catalog = VideoCatalog(qqApi: api);
      final result = await catalog.search(PlatformType.qq, '歌曲');
      await expectLater(
        catalog.setLiked(result.songs.single, true),
        throwsA(
          isA<VideoFailure>().having(
            (error) => error.kind,
            'kind',
            VideoFailureKind.sessionExpired,
          ),
        ),
      );
    });

    test('错误类别决定登录、重试和返回操作，而不是裸异常文案', () {
      expect(
        VideoFailure.from(LoginExpiredException()).kind,
        VideoFailureKind.sessionExpired,
      );
      expect(
        VideoFailure.from(NoVipMembershipException('QQ音乐')).kind,
        VideoFailureKind.permission,
      );
      expect(
        VideoFailure.from(SongNotAvailableException()).kind,
        VideoFailureKind.unavailable,
      );
      expect(
        VideoFailure.from(StorageFullException()).kind,
        VideoFailureKind.storageFull,
      );
      expect(
        VideoFailure.from(StoragePermissionDeniedException()).kind,
        VideoFailureKind.storagePermission,
      );
      expect(VideoFailure.from(NetworkException()).canRetry, isTrue);
      expect(
        VideoFailure.from(NoVipMembershipException('QQ音乐')).canRetry,
        isFalse,
      );
    });

    test('请求 OGG 640 不等于已实际播放 OGG 640', () {
      const unverified = VideoQualityEvidence(requestedLabel: 'OGG 640');
      const actual = VideoQualityEvidence(
        requestedLabel: 'OGG 640',
        actualFormat: 'mp3',
        actualBitrate: 128000,
        isPreview: true,
      );

      expect(unverified.actualLabel, isNull);
      expect(unverified.matchesRequested, isNull);
      expect(actual.actualLabel, 'MP3 128');
      expect(actual.matchesRequested, isFalse);
      expect(actual.isPreview, isTrue);
      expect(
        const VideoQualityEvidence(
          requestedLabel: 'MP3 128',
          actualFormat: 'mp3',
          actualBitrate: 128000,
        ).matchesRequested,
        isTrue,
      );
    });
  });
}

Map<String, dynamic> _qqSong(int i) => {
  'mid': 'mid-$i',
  'name': '歌曲 $i',
  'singer': [
    {'mid': 'artist', 'name': '歌手'},
  ],
  'interval': 120,
};

class _QqLikesApi extends QqApi {
  _QqLikesApi({
    this.count = 76,
    this.duplicateBoundary = false,
    this.failPage,
    this.emptyPage,
  });
  final int count;
  final bool duplicateBoundary;
  final int? failPage;
  final int? emptyPage;
  final pages = <int>[];

  @override
  Future<Map<String, dynamic>> getLikedSongs({
    int page = 0,
    int limit = 50,
  }) async {
    pages.add(page);
    if (page == failPage) throw NetworkException();
    final start = page * limit;
    final end = (start + limit).clamp(0, count);
    final rows = page == emptyPage
        ? <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[
            for (var i = start; i < end; i++) {'songInfo': _qqSong(i)},
          ];
    if (duplicateBoundary && page == 1) {
      rows.insert(0, {'songInfo': _qqSong(29)});
    }
    return {
      'code': 0,
      'req_0': {
        'code': 0,
        'data': {'songlist': rows, 'total': count},
      },
    };
  }
}

class _QqExpiredApi extends QqApi {
  @override
  Future<Map<String, dynamic>> getLikedSongs({
    int page = 0,
    int limit = 50,
  }) async => {
    'code': 0,
    'req_0': {'code': 1000, 'message': '登录失效'},
  };
}

class _QqSearchApi extends QqApi {
  @override
  Future<Map<String, dynamic>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async => {
    'code': 0,
    'req_0': {
      'code': 0,
      'data': {
        'body': {
          'song': {
            'sum': 76,
            'list': [
              for (
                var i = (page - 1) * limit;
                i < (page * limit).clamp(0, 76);
                i++
              )
                _qqSong(i),
            ],
          },
        },
      },
    },
  };
}

class _QqMetaSearchApi extends _QqSearchApi {
  @override
  Future<Map<String, dynamic>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    return {
      'code': 0,
      'req_0': {
        'code': 0,
        'data': {
          'meta': {'sum': 1009, 'nextpage': 2},
          'body': {
            'song': {
              'list': [_qqSong(1), _qqSong(2)],
            },
          },
        },
      },
    };
  }
}

class _QqMalformedApi extends QqApi {
  @override
  Future<Map<String, dynamic>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async => {
    'code': 0,
    'req_0': {'code': 0, 'data': {}},
  };
}

class _QqBlockedSearchApi extends QqApi {
  @override
  Future<Map<String, dynamic>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async => {
    'code': 0,
    'req_0': {
      'code': 2001,
      'data': {
        'body': {
          'song': {'list': []},
        },
      },
    },
  };
}

class _QqWriteApi extends QqApi {
  _QqWriteApi({this.expired = false});
  final bool expired;
  String? writeMid;
  String? writeId;

  @override
  Future<Map<String, dynamic>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async => {
    'code': 0,
    'req_0': {
      'code': 0,
      'data': {
        'body': {
          'song': {
            'sum': 1,
            'list': [
              {..._qqSong(9), 'id': 9009},
            ],
          },
        },
      },
    },
  };

  @override
  Future<Map<String, dynamic>> likeSong(String songMid, String songId) async {
    writeMid = songMid;
    writeId = songId;
    return {
      'code': 0,
      'req_0': {'code': expired ? 1000 : 0},
    };
  }
}

class _NeteaseSearchApi extends NeteaseApi {
  @override
  Future<Map<String, dynamic>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
    int type = 1,
  }) async => {
    'code': 200,
    'result': {
      'songs': [
        {
          'id': 8,
          'name': '歌曲',
          'artists': [
            {'id': 1, 'name': '歌手'},
          ],
          'album': {'id': 2, 'name': '专辑'},
          'duration': 123000,
        },
      ],
    },
  };
}

class _NeteaseLikesApi extends NeteaseApi {
  _NeteaseLikesApi({this.includeOwnLikes = true, this.omitDetail = false});
  final bool includeOwnLikes;
  final bool omitDetail;
  final playlistOffsets = <int>[];
  final requestedPlaylistIds = <String>[];
  final detailBatches = <List<String>>[];

  @override
  Future<Map<String, dynamic>> getUserPlaylist(
    String uid, {
    int limit = 30,
    int offset = 0,
  }) async {
    playlistOffsets.add(offset);
    return {
      'code': 200,
      'more': offset == 0,
      'playlist': offset == 0
          ? [
              {
                'id': 'wrong-first',
                'name': '我喜欢的音乐',
                'specialType': 0,
                'creator': {'userId': 42},
              },
              {
                'id': 'other-user',
                'specialType': 5,
                'creator': {'userId': 99},
              },
            ]
          : [
              if (includeOwnLikes)
                {
                  'id': 'owned-likes',
                  'name': '自定义名字',
                  'specialType': 5,
                  'creator': {'userId': 42},
                },
            ],
    };
  }

  @override
  Future<Map<String, dynamic>> getPlaylistDetail(
    String id, {
    int n = 1000,
  }) async {
    requestedPlaylistIds.add(id);
    return {
      'code': 200,
      'playlist': {
        'trackCount': 3,
        'trackIds': [
          {'id': 3},
          {'id': 1},
          {'id': 2},
        ],
        'tracks': [_song(3)],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getSongDetails(List<String> ids) async {
    detailBatches.add(List.of(ids));
    return {
      'code': 200,
      'songs': [
        for (final id in ids)
          if (!(omitDetail && id == '2')) _song(int.parse(id)),
      ],
    };
  }

  Map<String, dynamic> _song(int id) => {
    'id': id,
    'name': '歌曲 $id',
    'ar': [
      {'id': 1, 'name': '歌手'},
    ],
    'dt': 120000,
  };
}
