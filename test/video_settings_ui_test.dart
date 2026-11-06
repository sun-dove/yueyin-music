import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/video_app/ui/my_page.dart';
import 'package:mconnect/video_app/ui/video_theme.dart';

void main() {
  testWidgets('双账号状态、真实统计和设置入口可见可点', (tester) async {
    var login = 0;
    var cache = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: VideoTheme.light,
        home: Scaffold(
          body: VideoMyPage(
            accounts: const {
              PlatformType.qq: VideoAccountSummary(
                nickname: '我的昵称',
                loaded: 76,
                total: 80,
                complete: false,
              ),
            },
            cacheLabel: '12 MB / 10240 MB',
            downloadLabel: '2 项',
            themeLabel: '浅色',
            onAccount: (_) => login++,
            onQuality: (_, _) {},
            onCache: () => cache++,
            onDownloads: () {},
            onDirectory: () {},
            onTheme: () {},
            onLocal: () {},
          ),
        ),
      ),
    );
    expect(find.text('我的昵称'), findsOneWidget);
    expect(find.text('QQ 音乐喜欢'), findsOneWidget);
    expect(find.text('网易云喜欢'), findsOneWidget);
    expect(find.text('本地歌曲'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
    expect(find.textContaining('76 / 80'), findsOneWidget);
    expect(find.text('未完整同步'), findsOneWidget);
    await tester.tap(find.text('登录网易云'));
    expect(login, 1);
    await tester.ensureVisible(find.text('12 MB / 10240 MB'));
    await tester.tap(find.text('12 MB / 10240 MB'));
    expect(cache, 1);
    await tester.scrollUntilVisible(find.text('悦音音乐 · 0.3.3'), 200);
    expect(find.text('悦音音乐 · 0.3.3'), findsOneWidget);
  });
}
