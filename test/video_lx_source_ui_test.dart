import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/ui/lx_source_page.dart';

LxSourceConfig source() => LxSourceConfig(
  name: '家庭音源',
  version: '1.2',
  origin: Uri.parse('https://source.example/a.js'),
  script: 'fixture',
  sha256: 'fixture-hash',
  sources: const {
    'tx': ['128k', '320k'],
  },
);

void main() {
  Future<void> mount(WidgetTester tester, VideoLxSourcePage page) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pump();
  }

  testWidgets('链接导入成功显示名称，未启用且不自动保存', (tester) async {
    var saved = 0;
    await mount(
      tester,
      VideoLxSourcePage(
        onImport: (url, _) async {
          expect(url, 'https://source.example/a.js');
          return source();
        },
        onSave: (_) async {
          saved++;
        },
        onTest: (_) async {},
        onHttp: () {},
      ),
    );
    await tester.enterText(
      find.byKey(VideoLxSourcePage.linkKey),
      'https://source.example/a.js',
    );
    await tester.tap(find.text('从链接导入'));
    await tester.pumpAndSettle();
    expect(find.text('家庭音源'), findsOneWidget);
    expect(find.textContaining('导入成功'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(VideoLxSourcePage.enabledKey))
          .value,
      isFalse,
    );
    expect(saved, 0);
  });
  testWidgets('导入失败保留旧音源并显示错误', (tester) async {
    await mount(
      tester,
      VideoLxSourcePage(
        initial: source(),
        onImport: (_, _) async => throw const LxSourceException('link', '链接无效'),
        onSave: (_) async {},
        onTest: (_) async {},
        onHttp: () {},
      ),
    );
    await tester.tap(find.text('从链接导入'));
    await tester.pumpAndSettle();
    expect(find.text('链接无效'), findsOneWidget);
    expect(find.text('家庭音源'), findsOneWidget);
  });
  testWidgets('脚本缺接口时显示具体原因并保留已保存音源', (tester) async {
    await mount(
      tester,
      VideoLxSourcePage(
        initial: source(),
        onImport: (_, _) async => throw const LxSourceException(
          'script',
          '此脚本需要尚不支持的接口：utils.crypto.md5',
        ),
        onSave: (_) async {},
        onTest: (_) async {},
        onHttp: () {},
      ),
    );
    await tester.tap(find.text('从链接导入'));
    await tester.pumpAndSettle();
    expect(find.text('此脚本需要尚不支持的接口：utils.crypto.md5'), findsOneWidget);
    expect(find.text('家庭音源'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '从链接导入'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('导入期间禁止重复请求且离开页面取消', (tester) async {
    final pending = Completer<LxSourceConfig>();
    var cancelled = false;
    await mount(
      tester,
      VideoLxSourcePage(
        onImport: (_, token) {
          token.whenCancel.then((_) => cancelled = true);
          return pending.future;
        },
        onSave: (_) async {},
        onTest: (_) async {},
        onHttp: () {},
      ),
    );
    await tester.enterText(
      find.byKey(VideoLxSourcePage.linkKey),
      'https://source.example/a.js',
    );
    await tester.tap(find.text('从链接导入'));
    await tester.pump();
    expect(find.text('正在下载并检查…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(VideoLxSourcePage.importKey))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(cancelled, isTrue);
    pending.complete(source());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('启用和下载开关只在用户保存时提交', (tester) async {
    LxSourceConfig? saved;
    await mount(
      tester,
      VideoLxSourcePage(
        initial: source(),
        onImport: (_, _) async => source(),
        onSave: (value) async => saved = value,
        onTest: (_) async {},
        onHttp: () {},
      ),
    );
    await tester.tap(find.byKey(VideoLxSourcePage.enabledKey));
    await tester.tap(find.byKey(VideoLxSourcePage.downloadKey));
    expect(saved, isNull);
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved?.enabled, isTrue);
    expect(saved?.allowForDownloads, isTrue);
  });
  testWidgets('测试初始化显示实测范围，不冒充歌曲可播放', (tester) async {
    await mount(
      tester,
      VideoLxSourcePage(
        initial: source(),
        onImport: (_, _) async => source(),
        onSave: (_) async {},
        onTest: (_) async {},
        onHttp: () {},
      ),
    );
    await tester.ensureVisible(find.text('测试音源'));
    await tester.tap(find.text('测试音源'));
    await tester.pumpAndSettle();
    expect(find.text('脚本初始化通过；歌曲能否播放仍取决于音源'), findsOneWidget);
  });
  testWidgets('删除需确认，HTTP 设置入口仍可进入', (tester) async {
    var deletes = 0, http = 0;
    await mount(
      tester,
      VideoLxSourcePage(
        initial: source(),
        onImport: (_, _) async => source(),
        onSave: (_) async {},
        onTest: (_) async {},
        onDelete: () async {
          deletes++;
        },
        onHttp: () {
          http++;
        },
      ),
    );
    await tester.ensureVisible(find.text('删除音源'));
    await tester.tap(find.text('删除音源'));
    await tester.pumpAndSettle();
    expect(find.text('删除“家庭音源”？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    await tester.tap(find.text('删除音源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    await tester.ensureVisible(find.text('HTTP 音源设置'));
    await tester.tap(find.text('HTTP 音源设置'));
    expect(http, 1);
  });
}
