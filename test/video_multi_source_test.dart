import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/multi_source/source_collection.dart';
import 'package:mconnect/video_app/multi_source/source_coordinator.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';

const song = Song(
  id: 'mid',
  platform: PlatformType.qq,
  name: '歌曲',
  artists: [],
);
SourceCandidate candidate(String id, AudioLevel quality) => SourceCandidate(
  id: id,
  name: id,
  quality: quality,
  official: id == 'official',
);

void main() {
  test('真实集合按跨源最高档排序，固定模式和下载按权限过滤', () {
    var collection = const SourceCollection(
      autoSwitch: true,
      sourceFirst: true,
      highestQuality: true,
    );
    for (final name in ['A', 'B']) {
      collection = collection.upsert(
        LxSourceConfig(
          name: name,
          version: '1',
          origin: Uri.parse('https://example.com/$name.js'),
          script: 'fixture',
          sha256: name,
          sources: {
            'tx': name == 'A' ? ['128k'] : ['flac', '128k'],
          },
          enabled: true,
          allowForDownloads: name == 'B',
        ),
      );
    }
    final plan = buildSourceCandidates(song, AudioLevel.low, collection);
    expect(
      sourceExclusions(song, AudioLevel.low, collection),
      contains('A · ${AudioLevel.lossless.displayName}：未声明支持，不参与'),
    );
    expect(plan.map((c) => '${c.name}:${c.quality.name}'), [
      'QQ音乐:hires',
      'B:lossless',
      'QQ音乐:lossless',
      'QQ音乐:high',
      'A:low',
      'B:low',
      'QQ音乐:low',
    ]);
    expect(
      buildSourceCandidates(
        song,
        AudioLevel.lossless,
        collection,
        download: true,
      ).map((c) => c.name),
      ['B', 'QQ音乐'],
    );
    expect(
      buildSourceCandidates(
        song,
        AudioLevel.low,
        collection.copyWith(highestQuality: false, autoSwitch: false),
      ).map((c) => c.name),
      ['A', 'QQ音乐'],
    );
  });
  test('坏地址跨源重复返回不再加载，未知内部异常停止并保留未试项', () async {
    final session = SourceSession(
      candidates: [
        candidate('A', AudioLevel.high),
        candidate('B', AudioLevel.high),
        candidate('C', AudioLevel.high),
      ],
      resolve: (c, _) async {
        if (c.id == 'C') throw StateError('内部错误');
        return ResolvedSource(c, Uri.parse('https://example.com/same'));
      },
    );
    final first = (await session.next())!;
    session.failed(first, const SourceFailure('load', '404'));
    expect(await session.next(), isNull);
    expect(session.attempts[1].message, contains('已经加载失败'));
    expect(session.canContinue, isFalse);
  });
  test('最高音质先跨源尝试无损，不接受排第一的标准源', () async {
    final calls = <String>[];
    final session = SourceSession(
      candidates: [
        candidate('B', AudioLevel.lossless),
        candidate('A', AudioLevel.low),
      ],
      resolve: (c, token) async {
        calls.add(c.id);
        return ResolvedSource(c, Uri.parse('https://example.com/${c.id}'));
      },
    );
    final result = await session.next();
    expect(result!.candidate.id, 'B');
    expect(calls, ['B']);
  });
  test('解析失败及加载失败继续下一源，成功前不宣称正在播放', () async {
    final session = SourceSession(
      candidates: [
        candidate('A', AudioLevel.high),
        candidate('B', AudioLevel.high),
        candidate('C', AudioLevel.high),
      ],
      resolve: (c, token) async {
        if (c.id == 'A') throw const SourceFailure('unavailable', '音源无资源');
        return ResolvedSource(c, Uri.parse('https://example.com/${c.id}'));
      },
    );
    final b = await session.next();
    expect(b!.candidate.id, 'B');
    expect(session.attempts.last.stage, SourceStage.resolved);
    session.failed(b, const SourceFailure('load', '音频加载失败'));
    final c = await session.next();
    session.loaded(c!);
    expect(session.attempts.map((a) => a.stage), [
      SourceStage.failed,
      SourceStage.failed,
      SourceStage.playing,
    ]);
    expect(await session.next(), isNull);
  });
  test('取消后迟到结果不生效', () async {
    final pending = Completer<ResolvedSource>();
    final c = candidate('A', AudioLevel.low);
    CancelToken? token;
    final session = SourceSession(
      candidates: [c],
      resolve: (_, t) {
        token = t;
        return pending.future;
      },
    );
    final future = session.next();
    session.cancel();
    pending.complete(ResolvedSource(c, Uri.parse('https://example.com/a')));
    expect(await future, isNull);
    expect(token!.isCancelled, isTrue);
  });
  test('源级错误跳过该源其他档位，其他源仍可用', () async {
    final calls = <String>[];
    final session = SourceSession(
      candidates: [
        candidate('A', AudioLevel.lossless),
        candidate('A', AudioLevel.high),
        candidate('B', AudioLevel.low),
      ],
      resolve: (c, _) async {
        calls.add(c.id);
        if (c.id == 'A') {
          throw const SourceFailure('script', '缺少接口', sourceWide: true);
        }
        return ResolvedSource(c, Uri.parse('https://example.com/b'));
      },
    );
    expect((await session.next())!.candidate.id, 'B');
    expect(calls, ['A', 'B']);
  });
  test('候选计划按音质再按源，关闭所有源仍有官方候选', () {
    final collection = SourceCollection(
      highestQuality: true,
      sourceFirst: true,
      autoSwitch: true,
    );
    final plan = buildSourceCandidates(song, AudioLevel.low, collection);
    expect(plan.map((c) => c.quality), [
      AudioLevel.hires,
      AudioLevel.lossless,
      AudioLevel.high,
      AudioLevel.low,
    ]);
    expect(plan.every((c) => c.official), isTrue);
  });
  test('总预算结束保留未试项，继续不会重复已失败项', () async {
    var now = DateTime(2026);
    final calls = <String>[];
    final session = SourceSession(
      candidates: [
        candidate('A', AudioLevel.high),
        candidate('B', AudioLevel.high),
      ],
      now: () => now,
      budget: const Duration(seconds: 1),
      resolve: (c, _) async {
        calls.add(c.id);
        if (c.id == 'A') {
          now = now.add(const Duration(seconds: 2));
          throw const SourceFailure('timeout', '超时');
        }
        return ResolvedSource(c, Uri.parse('https://example.com/b'));
      },
    );
    expect(await session.next(), isNull);
    expect(session.budgetExpired, isTrue);
    expect(session.remaining, 1);
    session.renewBudget();
    expect((await session.next())!.candidate.id, 'B');
    expect(calls, ['A', 'B']);
  });
}
