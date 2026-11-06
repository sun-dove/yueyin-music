import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/ui/catalog_pages.dart';
import 'package:mconnect/video_app/ui/video_theme.dart';

const _songs = <Song>[
  Song(
    id: 'first',
    platform: PlatformType.qq,
    name: '第一首验收歌曲',
    artists: [Artist(id: 'artist', name: '验收歌手')],
    duration: Duration(minutes: 4, seconds: 8),
    availableQualities: [
      AudioQuality(level: AudioLevel.lossless, bitrate: 1000, format: 'flac'),
    ],
  ),
  Song(
    id: 'second',
    platform: PlatformType.qq,
    name: '第二首验收歌曲',
    artists: [Artist(id: 'artist', name: '验收歌手')],
    duration: Duration(minutes: 3, seconds: 27),
  ),
];

void main() {
  Future<void> mount(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: VideoTheme.light,
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
  }

  testWidgets('搜索首页展示注入的热搜，点击热搜提交对应词', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final submitted = <String>[];
    await mount(
      tester,
      VideoSearchPage(
        controller: controller,
        onSearch: submitted.add,
        platform: PlatformType.qq,
        onPlatformChanged: (_) {},
        result: const VideoCatalogViewState(),
        hotTerms: const ['第一条热搜', '第二条热搜'],
        onSongTap: (_) {},
      ),
    );
    expect(find.text('热搜榜'), findsOneWidget);
    expect(find.text('来自 QQ 音乐'), findsOneWidget);
    await tester.tap(find.text('第二条热搜'));
    expect(submitted, ['第二条热搜']);
    expect(controller.text, '第二条热搜');
  });

  testWidgets('搜索结果显示已加载数与真实总数，平台切换触发回调', (tester) async {
    final controller = TextEditingController(text: '验收');
    addTearDown(controller.dispose);
    final platforms = <PlatformType>[];
    final played = <Song>[];
    await mount(
      tester,
      VideoSearchPage(
        controller: controller,
        onSearch: (_) {},
        platform: PlatformType.qq,
        onPlatformChanged: platforms.add,
        submitted: true,
        result: const VideoCatalogViewState(
          songs: _songs,
          total: 76,
          hasMore: true,
        ),
        totals: const {PlatformType.qq: 76, PlatformType.netease: 22},
        onSongTap: played.add,
      ),
    );
    expect(find.text('已加载 2 首 · 共 76 首'), findsOneWidget);
    expect(find.text('QQ 音乐 76'), findsOneWidget);
    await tester.tap(find.text('网易云 22'));
    expect(platforms, [PlatformType.netease]);
    await tester.tap(find.text('第一首验收歌曲'));
    expect(played, [_songs.first]);
    // 上游静态候选音质不能被当成已核实的歌曲品质。
    expect(find.text('SQ'), findsNothing);
  });

  testWidgets('搜索框键盘提交后把完整查询词传给调用方', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final queries = <String>[];
    await mount(
      tester,
      VideoSearchPage(
        controller: controller,
        onSearch: queries.add,
        platform: PlatformType.qq,
        onPlatformChanged: (_) {},
        result: const VideoCatalogViewState(),
        onSongTap: (_) {},
      ),
    );
    await tester.enterText(find.byType(TextField), '完整查询词');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    expect(queries, ['完整查询词']);
  });

  testWidgets('加载、真空结果与网络失败分别显示，错误可重试', (tester) async {
    final controller = TextEditingController(text: '验收');
    addTearDown(controller.dispose);
    var retries = 0;
    Widget page(VideoCatalogViewState state) => VideoSearchPage(
      controller: controller,
      onSearch: (_) {},
      platform: PlatformType.qq,
      onPlatformChanged: (_) {},
      result: state,
      submitted: true,
      onSongTap: (_) {},
      onRetry: () => retries++,
    );
    await mount(tester, page(const VideoCatalogViewState(loading: true)));
    expect(find.text('正在搜索…'), findsOneWidget);
    expect(find.text('没有找到歌曲'), findsNothing);
    await mount(tester, page(const VideoCatalogViewState(total: 0)));
    expect(find.text('没有找到歌曲'), findsOneWidget);
    await mount(tester, page(const VideoCatalogViewState(error: '网络连接失败')));
    expect(find.text('网络连接失败'), findsOneWidget);
    expect(find.text('没有找到歌曲'), findsNothing);
    await tester.tap(find.text('重试'));
    expect(retries, 1);
  });

  testWidgets('不可重试错误不提供重试按钮，不会伪装成空结果', (tester) async {
    final controller = TextEditingController(text: '验收');
    addTearDown(controller.dispose);
    await mount(
      tester,
      VideoSearchPage(
        controller: controller,
        onSearch: (_) {},
        platform: PlatformType.qq,
        onPlatformChanged: (_) {},
        result: const VideoCatalogViewState(
          error: '当前账号没有播放权限',
          canRetry: false,
        ),
        submitted: true,
        onRetry: () {},
        onSongTap: (_) {},
      ),
    );
    expect(find.text('当前账号没有播放权限'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(find.text('没有找到歌曲'), findsNothing);
  });

  testWidgets('未登录收藏页提供对应平台登录，播放与下载不可用', (tester) async {
    var logins = 0;
    await mount(
      tester,
      VideoLibraryPage(
        platform: PlatformType.netease,
        result: const VideoCatalogViewState(),
        loggedIn: false,
        onLogin: () => logins++,
        onRefresh: () {},
        onPlayAll: () {},
        onDownloadAll: () {},
        onSongTap: (_) {},
      ),
    );
    await tester.tap(find.text('登录网易云'));
    expect(logins, 1);
    final playButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '播放全部'),
    );
    expect(playButton.onPressed, isNull);
    final downloadButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '下载'),
    );
    expect(downloadButton.onPressed, isNull);
  });

  testWidgets('收藏页播放全部、下载及已核实音质和收藏操作可用', (tester) async {
    var plays = 0;
    var downloads = 0;
    final liked = <Song>[];
    await mount(
      tester,
      VideoLibraryPage(
        platform: PlatformType.qq,
        result: const VideoCatalogViewState(songs: _songs, total: 2),
        loggedIn: true,
        syncComplete: true,
        onLogin: () {},
        onRefresh: () {},
        onPlayAll: () => plays++,
        onDownloadAll: () => downloads++,
        onSongTap: (_) {},
        onSongLike: liked.add,
        likedKeys: const {'qq:first'},
        qualityLabels: const {'qq:first': 'SQ'},
      ),
    );
    expect(find.text('我喜欢的音乐'), findsOneWidget);
    expect(find.text('SQ'), findsOneWidget);
    expect(find.textContaining('已获取'), findsNothing);
    await tester.tap(find.text('播放全部'));
    await tester.tap(find.text('下载'));
    await tester.tap(find.byTooltip('取消收藏').first);
    expect(plays, 1);
    expect(downloads, 1);
    expect(liked, [_songs.first]);
  });

  testWidgets('部分收藏失败保留已加载歌曲并显示未完成状态', (tester) async {
    await mount(
      tester,
      VideoLibraryPage(
        platform: PlatformType.qq,
        result: const VideoCatalogViewState(
          songs: _songs,
          total: 76,
          error: '同步中断，请重试',
          hasMore: true,
        ),
        loggedIn: true,
        onLogin: () {},
        onRefresh: () {},
        onRetry: () {},
        onPlayAll: () {},
        onDownloadAll: () {},
        onSongTap: (_) {},
      ),
    );
    expect(find.text('第一首验收歌曲'), findsOneWidget);
    expect(find.text('同步中断，请重试'), findsOneWidget);
    expect(find.text('已获取 2 / 76 首，尚未同步完整'), findsOneWidget);
  });

  testWidgets('搜索总数未知时只报告实际加载数量，允许继续加载', (tester) async {
    final controller = TextEditingController(text: '验收');
    addTearDown(controller.dispose);
    var loadRequests = 0;
    await mount(
      tester,
      VideoSearchPage(
        controller: controller,
        onSearch: (_) {},
        platform: PlatformType.qq,
        onPlatformChanged: (_) {},
        result: const VideoCatalogViewState(songs: _songs, hasMore: true),
        submitted: true,
        onLoadMore: () => loadRequests++,
        onSongTap: (_) {},
      ),
    );
    expect(find.text('已加载 2 首'), findsOneWidget);
    expect(find.textContaining('共 0 首'), findsNothing);
    await tester.tap(find.text('加载更多'));
    expect(loadRequests, 1);
  });

  testWidgets('已登录但没有收藏时禁用播放全部与下载', (tester) async {
    await mount(
      tester,
      VideoLibraryPage(
        platform: PlatformType.qq,
        result: const VideoCatalogViewState(total: 0),
        loggedIn: true,
        syncComplete: true,
        onLogin: () {},
        onRefresh: () {},
        onPlayAll: () {},
        onDownloadAll: () {},
        onSongTap: (_) {},
      ),
    );
    expect(find.text('还没有喜欢的歌曲'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '播放全部'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '下载'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('窄屏与大字体显示歌曲和操作时不出现布局异常', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: VideoTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(
          body: VideoLibraryPage(
            platform: PlatformType.qq,
            result: const VideoCatalogViewState(songs: _songs, total: 2),
            loggedIn: true,
            syncComplete: true,
            onLogin: () {},
            onRefresh: () {},
            onPlayAll: () {},
            onDownloadAll: () {},
            onSongTap: (_) {},
            onSongMore: (_) {},
            onSongLike: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('第一首验收歌曲'), findsOneWidget);
  });
}
