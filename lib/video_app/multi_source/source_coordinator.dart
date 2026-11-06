import '../../l10n/source_strings.dart';

import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/platform_http.dart';
import '../../models/audio_quality.dart';
import '../../models/song.dart';
import '../custom_source/custom_source_models.dart';
import '../lx_source/lx_source.dart';
import 'source_collection.dart';

enum SourceStage { resolving, resolved, playing, failed, skipped, cancelled }

class SourceCandidate {
  const SourceCandidate({
    required this.id,
    required this.name,
    required this.quality,
    this.official = false,
    this.entry,
  });
  final String id, name;
  final AudioLevel quality;
  final bool official;
  final SourceEntry? entry;
  String get key => '$id:${quality.name}';
  String get label => '$name · ${quality.displayName}';
}

class ResolvedSource {
  const ResolvedSource(this.candidate, this.url, {this.format, this.bitrate});
  final SourceCandidate candidate;
  final Uri url;
  final String? format;
  final int? bitrate;
}

class SourceFailure implements Exception {
  const SourceFailure(
    this.code,
    this.message, {
    this.sourceWide = false,
    this.fatal = false,
  });
  final String code, message;
  final bool sourceWide, fatal;
  @override
  String toString() => message;
}

SourceFailure sourceFailure(Object error) {
  if (error is SourceFailure) return error;
  if (error is LxSourceException) {
    return SourceFailure(
      error.code,
      error.message,
      sourceWide: ['script', 'unsupported', 'link'].contains(error.code),
    );
  }
  if (error is CustomSourceException) {
    return SourceFailure(
      error.code.name,
      error.message,
      sourceWide: error.code == CustomSourceFailureCode.unauthorized,
    );
  }
  if (error is TimeoutException) {
    return const SourceFailure('timeout', SourceStrings.timeout);
  }
  final api = apiExceptionOf(error);
  return SourceFailure(
    api.code.name,
    api.message,
    sourceWide: api.code == ApiErrorCode.loginExpired,
    fatal: api.code == ApiErrorCode.unknown,
  );
}

class SourceAttempt {
  SourceAttempt(this.candidate, this.stage, [this.message]);
  final SourceCandidate candidate;
  SourceStage stage;
  String? message;
}

List<SourceCandidate> buildSourceCandidates(
  Song song,
  AudioLevel fixed,
  SourceCollection collection, {
  bool download = false,
}) {
  final levels = collection.highestQuality && !download
      ? [AudioLevel.hires, AudioLevel.lossless, AudioLevel.high, AudioLevel.low]
      : [fixed];
  final enabled = collection.enabled;
  final sources = collection.autoSwitch ? enabled : enabled.take(1).toList();
  final result = <SourceCandidate>[];
  for (final level in levels) {
    final official = SourceCandidate(
      id: 'official',
      name: song.platform.displayName,
      quality: level,
      official: true,
    );
    if (!collection.sourceFirst) result.add(official);
    for (final source in sources) {
      if (download && !source.config.allowForDownloads) continue;
      String type;
      try {
        type = lxQuality(level);
      } on LxSourceException {
        continue;
      }
      if (!(source.config.sources[lxPlatform(song.platform)]?.contains(type) ??
          false)) {
        continue;
      }
      result.add(
        SourceCandidate(
          id: source.id,
          name: source.config.name,
          quality: level,
          entry: source,
        ),
      );
    }
    if (collection.sourceFirst) result.add(official);
  }
  return result;
}

typedef SourceResolve = Future<ResolvedSource> Function(
  SourceCandidate,
  CancelToken,
);

List<String> sourceExclusions(
  Song song,
  AudioLevel fixed,
  SourceCollection collection, {
  bool download = false,
}) {
  final sources = collection.autoSwitch
      ? collection.enabled
      : collection.enabled.take(1);
  final levels = collection.highestQuality && !download
      ? [AudioLevel.hires, AudioLevel.lossless, AudioLevel.high, AudioLevel.low]
      : [fixed];
  final result = <String>[];
  for (final source in sources) {
    if (download && !source.config.allowForDownloads) {
      result.add(SourceStrings.downloadDisabled(source.config.name));
      continue;
    }
    final supported =
        source.config.sources[lxPlatform(song.platform)] ?? const <String>[];
    if (supported.isEmpty) {
      result.add(
        SourceStrings.platformUnsupported(
          source.config.name,
          song.platform.displayName,
        ),
      );
      continue;
    }
    for (final level in levels) {
      String? type;
      try {
        type = lxQuality(level);
      } on LxSourceException {
        type = null;
      }
      if (type == null || !supported.contains(type)) {
        result.add(
          SourceStrings.qualityUnsupported(
            source.config.name,
            level.displayName,
          ),
        );
      }
    }
  }
  return result;
}

/// 每次只交付一个候选，音频加载结果由播放器回报，避免把URL当作成功。
class SourceSession {
  SourceSession({
    required this.candidates,
    required this.resolve,
    this.onChanged,
    this.exclusions = const [],
    this.budget = const Duration(seconds: 45),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    renewBudget();
  }
  final List<SourceCandidate> candidates;
  final SourceResolve resolve;
  final void Function()? onChanged;
  final List<String> exclusions;
  final Duration budget;
  final DateTime Function() _now;
  late DateTime _deadline;
  final List<SourceAttempt> attempts = [];
  final Set<String> _unavailable = {}, _failedUrls = {};
  int _next = 0;
  bool _cancelled = false, _fatal = false;
  CancelToken? _token;
  bool get cancelled => _cancelled;
  bool get budgetExpired => !_now().isBefore(_deadline);
  Duration get timeLeft => _deadline.difference(_now());
  int get remaining => candidates.length - _next;
  bool get canContinue => !_cancelled && !_fatal && remaining > 0;
  void renewBudget() => _deadline = _now().add(budget);
  void cancel() {
    _cancelled = true;
    _token?.cancel(SourceStrings.userCancelled);
  }

  Future<ResolvedSource?> next() async {
    while (canContinue && !budgetExpired) {
      final candidate = candidates[_next++];
      if (_unavailable.contains(candidate.id)) {
        attempts.add(
          SourceAttempt(
            candidate,
            SourceStage.skipped,
            SourceStrings.sourceUnavailable,
          ),
        );
        onChanged?.call();
        continue;
      }
      final attempt = SourceAttempt(candidate, SourceStage.resolving);
      attempts.add(attempt);
      onChanged?.call();
      final token = CancelToken();
      _token = token;
      try {
        final remainingTime = _deadline.difference(_now());
        final limit = remainingTime < const Duration(seconds: 15)
            ? remainingTime
            : const Duration(seconds: 15);
        final result = await Future.any<ResolvedSource?>([
          resolve(candidate, token),
          token.whenCancel.then<ResolvedSource?>((_) => null),
        ]).timeout(limit);
        if (_cancelled || result == null) {
          attempt.stage = SourceStage.cancelled;
          return null;
        }
        if (_failedUrls.contains(result.url.toString())) {
          throw const SourceFailure('duplicate', SourceStrings.duplicateUrl);
        }
        attempt.stage = SourceStage.resolved;
        onChanged?.call();
        return result;
      } catch (error) {
        final failure = sourceFailure(error);
        attempt.stage = _cancelled ? SourceStage.cancelled : SourceStage.failed;
        attempt.message = failure.message;
        if (failure.sourceWide) _unavailable.add(candidate.id);
        if (failure.fatal) _fatal = true;
      } finally {
        token.cancel(SourceStrings.resolutionEnded);
        onChanged?.call();
      }
    }
    return null;
  }

  void failed(ResolvedSource source, SourceFailure failure) {
    _failedUrls.add(source.url.toString());
    final attempt = attempts
        .where((a) => a.candidate.key == source.candidate.key)
        .last;
    attempt.stage = SourceStage.failed;
    attempt.message = failure.message;
    onChanged?.call();
  }

  void loaded(ResolvedSource source) {
    attempts.where((a) => a.candidate.key == source.candidate.key).last.stage =
        SourceStage.playing;
    onChanged?.call();
  }

  String get summary => [
    ...exclusions,
    if (budgetExpired && remaining > 0) SourceStrings.remaining(remaining),
    for (final attempt in attempts)
      '${attempt.candidate.label}：${attempt.message ?? switch (attempt.stage) {
            SourceStage.resolving => SourceStrings.resolving,
            SourceStage.resolved => SourceStrings.resolved,
            SourceStage.playing => SourceStrings.playing,
            SourceStage.cancelled => SourceStrings.cancelled,
            SourceStage.skipped => SourceStrings.inapplicable,
            SourceStage.failed => SourceStrings.failed,
          }}',
    for (final candidate in candidates.skip(_next))
      SourceStrings.notTried(candidate.label),
  ].join('\n');
}
