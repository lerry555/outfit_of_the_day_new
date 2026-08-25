import 'dart:math';

import 'package:flutter/foundation.dart';

/// Krátke ID relácie appky — inicializuje sa pri štarte (main).
abstract final class StylistQaAppSession {
  static String? _appRunId;

  static void ensureInitialized() {
    // ignore: unnecessary_statements
    appRunId;
  }

  static String get appRunId => _appRunId ??= _newShortId();

  static String newQaRunId() => _newShortId();

  static String _newShortId() {
    final timePart = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final randPart =
        Random().nextInt(1 << 20).toRadixString(36).padLeft(5, '0');
    return '$timePart-$randPart';
  }
}

/// Časové a runtime metadáta jedného QA behu (Conversation / Location).
class StylistQaRunMeta {
  const StylistQaRunMeta({
    required this.startedAt,
    required this.finishedAt,
    required this.durationMs,
    required this.appRunId,
    required this.qaRunId,
    this.source = 'runtime_run',
    this.buildMode = kDebugMode ? 'debug' : 'release',
  });

  final DateTime startedAt;
  final DateTime finishedAt;
  final int durationMs;
  final String source;
  final String buildMode;
  final String appRunId;
  final String qaRunId;

  DateTime get generatedAt => finishedAt;

  String formatReportPreamble(String reportTitle) {
    return [
      reportTitle,
      'generatedAt: ${generatedAt.toIso8601String()}',
      'startedAt: ${startedAt.toIso8601String()}',
      'finishedAt: ${finishedAt.toIso8601String()}',
      'durationMs: $durationMs',
      'source: $source',
      'buildMode: $buildMode',
      'appRunId: $appRunId',
      'qaRunId: $qaRunId',
    ].join('\n');
  }
}
