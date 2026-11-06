import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/video_app/ui/video_shell.dart';

void main() {
  testWidgets('四入口切换后保留页面状态和同一个迷你播放器', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Harness()));
    for (final label in ['搜索', 'QQ 音乐', '网易云', '我的']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('增加页面计数'));
    await tester.pump();
    expect(find.text('页面计数 1'), findsOneWidget);
    await tester.tap(find.text('迷你播放按钮'));
    for (final label in ['QQ 音乐', '网易云', '我的', '搜索']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text('迷你播放中'), findsOneWidget);
    }
    expect(find.text('页面计数 1'), findsOneWidget);
  });

  testWidgets('窄屏放大文字时四个入口仍可点且不遮挡内容', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: _Harness(),
        ),
      ),
    );
    for (final label in ['搜索', 'QQ 音乐', '网易云', '我的']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}

class _Harness extends StatefulWidget {
  const _Harness();
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int index = 0;
  @override
  Widget build(BuildContext context) => VideoShell(
    index: index,
    onSelect: (value) => setState(() => index = value),
    pages: const [_Counter(), Text('QQ 页面'), Text('网易页面'), Text('设置页面')],
    miniPlayer: const _Mini(),
  );
}

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('页面计数 $count'),
      TextButton(
        onPressed: () => setState(() => count++),
        child: const Text('增加页面计数'),
      ),
    ],
  );
}

class _Mini extends StatefulWidget {
  const _Mini();
  @override
  State<_Mini> createState() => _MiniState();
}

class _MiniState extends State<_Mini> {
  bool playing = false;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => playing = !playing),
    child: Text(playing ? '迷你播放中' : '迷你播放按钮'),
  );
}
