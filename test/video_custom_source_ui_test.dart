import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/video_app/ui/custom_source_page.dart';
import 'package:mconnect/video_app/ui/my_page.dart';
import 'package:mconnect/video_app/ui/video_theme.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
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

  VideoMyPage myPage({
    required String customSourceLabel,
    required VoidCallback onCustomSource,
  }) => VideoMyPage(
    accounts: const {},
    cacheLabel: '0 MB / 10240 MB',
    downloadLabel: '0 项',
    themeLabel: '浅色',
    customSourceLabel: customSourceLabel,
    onAccount: (_) {},
    onQuality: (_, _) {},
    onCache: () {},
    onDownloads: () {},
    onDirectory: () {},
    onTheme: () {},
    onLocal: () {},
    onCustomSource: onCustomSource,
  );

  testWidgets('我的页显示自定义音源状态并打开管理页', (tester) async {
    var opens = 0;
    await mount(
      tester,
      myPage(customSourceLabel: '未配置', onCustomSource: () => opens++),
    );
    await tester.ensureVisible(find.text('自定义音源'));
    expect(find.text('未配置'), findsOneWidget);
    await tester.tap(find.text('自定义音源'));
    expect(opens, 1);

    await mount(
      tester,
      myPage(customSourceLabel: '已关闭', onCustomSource: () => opens++),
    );
    await tester.ensureVisible(find.text('自定义音源'));
    expect(find.text('已关闭'), findsOneWidget);

    await mount(
      tester,
      myPage(customSourceLabel: '已启用（家庭音源）', onCustomSource: () => opens++),
    );
    await tester.ensureVisible(find.text('自定义音源'));
    expect(find.text('已启用（家庭音源）'), findsOneWidget);
  });

  testWidgets('新建页包含完整配置和隐私说明，令牌默认隐藏', (tester) async {
    await mount(
      tester,
      VideoCustomSourcePage(
        onTest: (_) async => const VideoCustomSourceTestResult.success(),
        onSave: (_) async {},
      ),
    );
    expect(find.text('自定义音源'), findsOneWidget);
    expect(find.text('音源名称'), findsOneWidget);
    expect(find.text('HTTPS 地址'), findsOneWidget);
    expect(find.text('QQ 音乐'), findsOneWidget);
    expect(find.text('网易云'), findsOneWidget);
    expect(find.text('请求超时（秒）'), findsOneWidget);
    expect(find.text('访问令牌（可选）'), findsOneWidget);
    expect(find.text('允许用于下载'), findsOneWidget);
    expect(find.text('启用音源'), findsOneWidget);
    expect(find.textContaining('歌曲信息和设备网络地址'), findsOneWidget);
    expect(find.textContaining('无法保证返回内容与歌曲匹配'), findsOneWidget);
    final token = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(VideoCustomSourcePage.tokenFieldKey),
        matching: find.byType(EditableText),
      ),
    );
    expect(token.obscureText, isTrue);
  });

  for (final scenario
      in <({String name, VideoCustomSourceTestResult result, String message})>[
        (
          name: '连接测试成功时显示明确结果',
          result: const VideoCustomSourceTestResult.success(),
          message: '连接成功',
        ),
        (
          name: '认证失败提示检查访问令牌',
          result: const VideoCustomSourceTestResult.unauthorized(),
          message: '认证失败，请检查访问令牌',
        ),
        (
          name: '协议不兼容显示独立错误',
          result: const VideoCustomSourceTestResult.incompatible(),
          message: '音源协议不兼容',
        ),
        (
          name: '连接超时提供可读提示',
          result: const VideoCustomSourceTestResult.timeout(),
          message: '连接超时，请重试',
        ),
        (
          name: '服务不可用显示独立错误',
          result: const VideoCustomSourceTestResult.unavailable(),
          message: '音源服务暂时不可用',
        ),
      ]) {
    testWidgets(scenario.name, (tester) async {
      var tests = 0;
      var saves = 0;
      await mount(
        tester,
        VideoCustomSourcePage(
          initialDraft: const VideoCustomSourceDraft(
            name: '验收音源',
            endpoint: 'https://source.example',
            platforms: {PlatformType.qq},
          ),
          onTest: (_) async {
            tests++;
            return scenario.result;
          },
          onSave: (_) async => saves++,
        ),
      );
      await tester.ensureVisible(find.text('测试连接'));
      await tester.tap(find.text('测试连接'));
      await tester.pumpAndSettle();
      expect(tests, 1);
      expect(find.text(scenario.message), findsOneWidget);
      expect(saves, 0, reason: '连接测试不能自动保存或启用音源');
    });
  }

  testWidgets('保存把用户编辑的全部字段交给调用方', (tester) async {
    VideoCustomSourceDraft? saved;
    await mount(
      tester,
      VideoCustomSourcePage(
        onTest: (_) async => const VideoCustomSourceTestResult.success(),
        onSave: (draft) async => saved = draft,
      ),
    );
    await tester.enterText(
      find.byKey(VideoCustomSourcePage.nameFieldKey),
      '家庭音源',
    );
    await tester.enterText(
      find.byKey(VideoCustomSourcePage.endpointFieldKey),
      'https://source.example/api',
    );
    await tester.enterText(
      find.byKey(VideoCustomSourcePage.tokenFieldKey),
      'secret-token',
    );
    await tester.enterText(
      find.byKey(VideoCustomSourcePage.timeoutFieldKey),
      '18',
    );
    await tester.tap(find.byKey(VideoCustomSourcePage.qqSwitchKey));
    await tester.tap(find.byKey(VideoCustomSourcePage.neteaseSwitchKey));
    await tester.tap(find.byKey(VideoCustomSourcePage.downloadSwitchKey));
    await tester.tap(find.byKey(VideoCustomSourcePage.enabledSwitchKey));
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.name, '家庭音源');
    expect(saved!.endpoint, 'https://source.example/api');
    expect(saved!.token, 'secret-token');
    expect(saved!.timeoutSeconds, 18);
    expect(saved!.platforms, {PlatformType.qq, PlatformType.netease});
    expect(saved!.allowForDownloads, isTrue);
    expect(saved!.enabled, isTrue);
  });

  testWidgets('删除音源展示名称，取消不删除，确认后调用删除', (tester) async {
    var deletes = 0;
    await mount(
      tester,
      VideoCustomSourcePage(
        initialDraft: const VideoCustomSourceDraft(
          name: '待删除音源',
          endpoint: 'https://source.example',
          platforms: {PlatformType.qq},
        ),
        onTest: (_) async => const VideoCustomSourceTestResult.success(),
        onSave: (_) async {},
        onDelete: () async => deletes++,
      ),
    );
    await tester.ensureVisible(find.text('删除音源'));
    await tester.tap(find.text('删除音源'));
    await tester.pumpAndSettle();
    expect(find.text('删除“待删除音源”？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(deletes, 0);

    await tester.tap(find.text('删除音源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
  });

  testWidgets('窄屏与长名称下保存和测试连接仍可见可点', (tester) async {
    var tests = 0;
    var saves = 0;
    await mount(
      tester,
      VideoCustomSourcePage(
        initialDraft: const VideoCustomSourceDraft(
          name: '一个很长很长但仍然需要完整编辑的家庭自定义音源名称',
          endpoint: 'https://source.example/very/long/endpoint/path',
          platforms: {PlatformType.qq, PlatformType.netease},
        ),
        onTest: (_) async {
          tests++;
          return const VideoCustomSourceTestResult.success();
        },
        onSave: (_) async => saves++,
      ),
      size: const Size(320, 568),
    );
    await tester.ensureVisible(find.text('测试连接'));
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(tests, 1);
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(tester.takeException(), isNull);
  });
}
