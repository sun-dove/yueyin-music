import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:mconnect/video_app/ui/player_page.dart';

const _song = Song(
  id: 'a',
  platform: PlatformType.qq,
  name: '验收曲目',
  artists: [Artist(id: 'b', name: '验收歌手')],
);

void main() {
  testWidgets('多源尝试状态与继续按钮在播放页可见', (tester) async {
    var continued = false;
    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          song: _song,
          position: Duration.zero,
          duration: Duration.zero,
          isPlaying: false,
          onToggle: () {},
          onPrevious: () {},
          onNext: () {},
          onSeek: (_) {},
          onQueue: () {},
          onMode: () {},
          sourceStatus: TextButton(
            onPressed: () => continued = true,
            child: const Text('继续尝试剩余音源'),
          ),
        ),
      ),
    );
    expect(find.text('继续尝试剩余音源'), findsOneWidget);
    await tester.tap(find.text('继续尝试剩余音源'));
    expect(continued, isTrue);
    expect(tester.takeException(), isNull);
  });
  Future<void> mount(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pump();
  }

  testWidgets('歌曲信息、真实进度及播放控制可用，未知音质不假标', (tester) async {
    var toggles = 0;
    var previous = 0;
    var next = 0;
    await mount(
      tester,
      VideoPlayerPage(
        song: _song,
        position: const Duration(seconds: 12),
        duration: const Duration(minutes: 4),
        isPlaying: true,
        onToggle: () => toggles++,
        onPrevious: () => previous++,
        onNext: () => next++,
        onSeek: (_) {},
        onQueue: () {},
        onMode: () {},
      ),
    );
    expect(find.text('验收曲目'), findsWidgets);
    expect(find.text('0:12'), findsOneWidget);
    expect(find.text('4:00'), findsOneWidget);
    expect(find.textContaining('OGG'), findsNothing);
    await tester.tap(find.byTooltip('暂停'));
    await tester.tap(find.byTooltip('上一首'));
    await tester.tap(find.byTooltip('下一首'));
    expect([toggles, previous, next], [1, 1, 1]);
  });

  testWidgets('准备中和失败不是播放中，错误提示可见', (tester) async {
    await mount(
      tester,
      VideoPlayerPage(
        song: _song,
        position: Duration.zero,
        duration: Duration.zero,
        isPlaying: false,
        isLoading: true,
        onToggle: () {},
        onPrevious: () {},
        onNext: () {},
        onSeek: (_) {},
        onQueue: () {},
        onMode: () {},
      ),
    );
    expect(find.text('正在准备音频…'), findsOneWidget);
    expect(find.byTooltip('暂停'), findsNothing);
    await mount(
      tester,
      VideoPlayerPage(
        song: _song,
        position: Duration.zero,
        duration: Duration.zero,
        isPlaying: false,
        error: '当前账号暂无播放权限',
        onToggle: () {},
        onPrevious: () {},
        onNext: () {},
        onSeek: (_) {},
        onQueue: () {},
        onMode: () {},
      ),
    );
    expect(find.text('当前账号暂无播放权限'), findsOneWidget);
    expect(find.text('正在准备音频…'), findsNothing);
  });

  testWidgets('切换全屏歌词并按时间轴定位播放', (tester) async {
    final seeks = <Duration>[];
    await mount(
      tester,
      VideoPlayerPage(
        song: _song,
        position: const Duration(seconds: 12),
        duration: const Duration(minutes: 4),
        isPlaying: true,
        lyrics: const [
          LyricsLine(timestamp: Duration.zero, text: '第一句'),
          LyricsLine(timestamp: Duration(seconds: 10), text: '当前句'),
          LyricsLine(timestamp: Duration(seconds: 20), text: '下一句'),
        ],
        onToggle: () {},
        onPrevious: () {},
        onNext: () {},
        onSeek: seeks.add,
        onQueue: () {},
        onMode: () {},
      ),
    );
    await tester.tap(find.byTooltip('展开歌词'));
    await tester.pumpAndSettle();
    expect(find.text('第一句'), findsOneWidget);
    expect(find.text('下一句'), findsOneWidget);
    await tester.tap(find.text('下一句'));
    expect(seeks.last, const Duration(seconds: 20));
  });
}
