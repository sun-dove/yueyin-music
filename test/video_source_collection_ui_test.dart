import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/multi_source/source_collection.dart';
import 'package:mconnect/video_app/ui/source_collection_page.dart';

void main() {
  testWidgets('多源页面保留全部条目，推荐设置与保存结果一致', (tester) async {
    SourceCollection? saved;
    final initial = const SourceCollection().upsert(
      LxSourceConfig(
        name: '已有源',
        version: '1',
        origin: Uri.parse('https://example.com/old.js'),
        script: 'fixture',
        sha256: 'old',
        sources: const {
          'tx': ['128k'],
        },
        enabled: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SourceCollectionPage(
          initial: initial,
          onImport: (_, _) async => LxSourceConfig(
            name: '新源',
            version: '2',
            origin: Uri.parse('https://example.com/new.js'),
            script: 'fixture',
            sha256: 'new',
            sources: const {
              'tx': ['flac', '320k'],
            },
          ),
          onInspect: (_, _) async {},
          onSave: (value) async {
            saved = value;
          },
          onHttp: () {},
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('collection-link')),
      'https://example.com/new.js',
    );
    await tester.tap(find.text('从链接导入'));
    await tester.pumpAndSettle();
    expect(find.text('已有源'), findsOneWidget);
    expect(find.text('新源'), findsOneWidget);
    await tester.tap(find.text('使用推荐设置'));
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('collection-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved!.entries, hasLength(2));
    expect(saved!.highestQuality, isTrue);
    expect(saved!.autoSwitch, isTrue);
    expect(saved!.sourceFirst, isTrue);
    expect(saved!.entries.last.config.enabled, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('导入失败显示原因，原有音源和保存按钮仍在', (tester) async {
    final initial = const SourceCollection().upsert(
      LxSourceConfig(
        name: '保留源',
        version: '1',
        origin: Uri.parse('https://example.com/old.js'),
        script: 'fixture',
        sha256: 'old',
        sources: const {
          'tx': ['128k'],
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SourceCollectionPage(
          initial: initial,
          onImport: (_, _) async =>
              throw const LxSourceException('script', '脚本需要尚不支持的接口'),
          onInspect: (_, _) async {},
          onSave: (_) async {},
          onHttp: () {},
        ),
      ),
    );
    await tester.tap(find.text('从链接导入'));
    await tester.pumpAndSettle();
    expect(find.text('脚本需要尚不支持的接口'), findsOneWidget);
    expect(find.text('保留源'), findsOneWidget);
  });
}
