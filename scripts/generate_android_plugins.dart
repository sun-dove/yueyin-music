import 'package:flutter_tools/src/base/template.dart';
import 'package:flutter_tools/src/context_runner.dart';
import 'package:flutter_tools/src/flutter_plugins.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/isolated/mustache_template.dart';
import 'package:flutter_tools/src/project.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw ArgumentError('必须提供应用工程路径');
  }
  // 使用固定 Flutter SDK 的官方模板，仅生成 Android 插件注册器。
  await runInContext(
    () async {
      final project = FlutterProject.fromDirectory(
        globals.fs.directory(arguments.single),
      );
      await injectPlugins(project, releaseMode: true, androidPlatform: true);
    },
    overrides: {TemplateRenderer: () => const MustacheTemplateRenderer()},
  );
}
