import 'dart:async';

/// Terminal-or-wait states for `users/{uid}/stylistJobs/{jobId}`.
enum StylistJobStatus { done, pending, failed, missing }

/// One job document observation after status mapping + result normalization.
class StylistJobSnapshot {
  const StylistJobSnapshot({
    required this.jobId,
    required this.status,
    this.response,
  });

  final String jobId;
  final StylistJobStatus status;

  /// Same shape as [StylistChatService.sendMessage] when [status] is done.
  final Map<String, dynamic>? response;
}

/// Raw Firestore job document as seen by [StylistJobConsumer].
class StylistJobRaw {
  const StylistJobRaw({required this.exists, this.status = '', this.result});

  const StylistJobRaw.missing() : exists = false, status = '', result = null;

  final bool exists;
  final String status;
  final Map<String, dynamic>? result;
}

/// Shared lookup / wait / normalize / delete for live recovery and
/// notification hydration. Does not delete on read.
class StylistJobConsumer {
  StylistJobConsumer({
    required Stream<StylistJobRaw> Function(String jobId) watch,
    required Future<void> Function(String jobId) delete,
    required Map<String, dynamic> Function(Map<String, dynamic> raw) normalize,
    this.waitTimeout = const Duration(minutes: 3),
    this.hydrationMissingGrace = const Duration(seconds: 2),
  }) : _watch = watch,
       _delete = delete,
       _normalize = normalize;

  final Stream<StylistJobRaw> Function(String jobId) _watch;
  final Future<void> Function(String jobId) _delete;
  final Map<String, dynamic> Function(Map<String, dynamic> raw) _normalize;

  /// Existing live-recovery ceiling (`awaitJobResult`).
  final Duration waitTimeout;

  /// Short wait when a notification tap races the job write replica.
  final Duration hydrationMissingGrace;

  static StylistJobStatus parseStatus(String raw, {required bool exists}) {
    if (!exists) return StylistJobStatus.missing;
    switch (raw.trim().toLowerCase()) {
      case 'done':
        return StylistJobStatus.done;
      case 'error':
      case 'failed':
      case 'fail':
        return StylistJobStatus.failed;
      default:
        return StylistJobStatus.pending;
    }
  }

  Future<void> deleteJob(String jobId) async {
    final id = jobId.trim();
    if (id.isEmpty) return;
    await _delete(id);
  }

  /// First snapshot only. Missing is terminal (no wait).
  Future<StylistJobSnapshot> readOnce(String jobId) async {
    final id = jobId.trim();
    if (id.isEmpty) {
      return StylistJobSnapshot(jobId: id, status: StylistJobStatus.missing);
    }
    final raw = await _watch(id).first;
    return _fromRaw(id, raw);
  }

  /// Live recovery: keep listening through missing docs until done/failed
  /// or [waitTimeout] (server may still be writing the job).
  Future<StylistJobSnapshot> waitUntilSettled(
    String jobId, {
    Duration? timeout,
    bool treatMissingAsPending = true,
  }) {
    return _listenUntilSettled(
      jobId.trim(),
      timeout: timeout ?? waitTimeout,
      treatMissingAsPending: treatMissingAsPending,
    );
  }

  /// Notification hydration: pending jobs wait up to [waitTimeout]; a missing
  /// doc gets only [hydrationMissingGrace] in case of replica lag.
  Future<StylistJobSnapshot> watchForHydration(String jobId) async {
    final id = jobId.trim();
    if (id.isEmpty) {
      return StylistJobSnapshot(jobId: id, status: StylistJobStatus.missing);
    }

    final completer = Completer<StylistJobSnapshot>();
    StreamSubscription<StylistJobRaw>? sub;
    Timer? timer;
    var seenNonMissing = false;

    void finish(StylistJobSnapshot value) {
      if (completer.isCompleted) return;
      unawaited(sub?.cancel());
      timer?.cancel();
      completer.complete(value);
    }

    timer = Timer(hydrationMissingGrace, () {
      if (seenNonMissing) return;
      finish(
        StylistJobSnapshot(jobId: id, status: StylistJobStatus.missing),
      );
    });

    sub = _watch(id).listen(
      (raw) {
        final mapped = _fromRaw(id, raw);
        if (mapped.status == StylistJobStatus.missing) return;
        seenNonMissing = true;
        if (mapped.status == StylistJobStatus.pending) {
          timer?.cancel();
          timer = Timer(waitTimeout, () {
            finish(
              StylistJobSnapshot(
                jobId: id,
                status: StylistJobStatus.pending,
              ),
            );
          });
          return;
        }
        finish(mapped);
      },
      onError: (_) {
        finish(
          StylistJobSnapshot(
            jobId: id,
            status: StylistJobStatus.failed,
            response: StylistJobConsumer._failedResponse(),
          ),
        );
      },
    );

    return completer.future;
  }

  Future<StylistJobSnapshot> _listenUntilSettled(
    String jobId, {
    required Duration timeout,
    required bool treatMissingAsPending,
  }) async {
    if (jobId.isEmpty) {
      return StylistJobSnapshot(
        jobId: jobId,
        status: StylistJobStatus.missing,
      );
    }
    final completer = Completer<StylistJobSnapshot>();
    StreamSubscription<StylistJobRaw>? sub;
    Timer? timer;

    void finish(StylistJobSnapshot value) {
      if (completer.isCompleted) return;
      unawaited(sub?.cancel());
      timer?.cancel();
      completer.complete(value);
    }

    timer = Timer(timeout, () {
      finish(
        StylistJobSnapshot(
          jobId: jobId,
          status: treatMissingAsPending
              ? StylistJobStatus.pending
              : StylistJobStatus.missing,
        ),
      );
    });

    sub = _watch(jobId).listen(
      (raw) {
        final mapped = _fromRaw(jobId, raw);
        if (mapped.status == StylistJobStatus.missing) {
          if (!treatMissingAsPending) {
            finish(mapped);
          }
          return;
        }
        if (mapped.status == StylistJobStatus.pending) return;
        finish(mapped);
      },
      onError: (_) {
        finish(
          StylistJobSnapshot(
            jobId: jobId,
            status: StylistJobStatus.failed,
            response: const <String, dynamic>{
              'ok': false,
              'offline': false,
              'reply': '',
              'suggestedItems': <Map<String, dynamic>>[],
              'action': 'chat',
            },
          ),
        );
      },
    );

    return completer.future;
  }

  StylistJobSnapshot _fromRaw(String jobId, StylistJobRaw raw) {
    final status = parseStatus(raw.status, exists: raw.exists);
    if (status == StylistJobStatus.done) {
      final result = raw.result;
      if (result == null) {
        return StylistJobSnapshot(
          jobId: jobId,
          status: StylistJobStatus.failed,
          response: _failedResponse(),
        );
      }
      return StylistJobSnapshot(
        jobId: jobId,
        status: StylistJobStatus.done,
        response: _normalize(result),
      );
    }
    if (status == StylistJobStatus.failed) {
      return StylistJobSnapshot(
        jobId: jobId,
        status: StylistJobStatus.failed,
        response: _failedResponse(),
      );
    }
    return StylistJobSnapshot(jobId: jobId, status: status);
  }

  static Map<String, dynamic> _failedResponse() {
    return <String, dynamic>{
      'ok': false,
      'offline': false,
      'reply': '',
      'suggestedItems': const <Map<String, dynamic>>[],
      'action': 'chat',
      'eventContext': null,
      'excludeItemKeywords': const <String>[],
    };
  }
}

/// Apply → persist chat → only then delete the job.
///
/// Returns false when the snapshot is not done, persist fails, or apply throws.
Future<bool> consumeCompletedJobSafely({
  required StylistJobSnapshot snapshot,
  required Future<void> Function(Map<String, dynamic> response) apply,
  required Future<bool> Function() persistChat,
  required Future<void> Function(String jobId) deleteJob,
}) async {
  if (snapshot.status != StylistJobStatus.done) return false;
  final response = snapshot.response;
  if (response == null) return false;
  await apply(response);
  final persisted = await persistChat();
  if (!persisted) return false;
  await deleteJob(snapshot.jobId);
  return true;
}

bool stylistChatAlreadyHasJobResult({
  required Iterable<String?> sourceJobIds,
  required Iterable<String> assistantTexts,
  required String jobId,
  String? replyText,
}) {
  final id = jobId.trim();
  if (id.isNotEmpty && sourceJobIds.any((value) => value == id)) {
    return true;
  }
  final reply = replyText?.trim() ?? '';
  if (reply.isEmpty) return false;
  return assistantTexts.any((text) => text.trim() == reply);
}

String? resolveStylistHydrationChatId({
  String? intentChatId,
  String? resultChatId,
}) {
  final fromIntent = _nonEmpty(intentChatId);
  if (fromIntent != null) return fromIntent;
  return _nonEmpty(resultChatId);
}

String? _nonEmpty(String? raw) {
  final value = raw?.trim() ?? '';
  return value.isEmpty ? null : value;
}
