// lib/Services/try_on_service.dart
//
// A architektúra: Try-On ako job system
// Firestore: users/{uid}/tryon_jobs/{jobId}
// Storage: tryon_results/{uid}/{jobId}.png
// Cloud Function: requestTryOn (callable) vytvorí job, spracuje (zatiaľ fake provider), uloží výsledok,
// a aktualizuje job status.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Firestore dokument model: users/{uid}/tryon_jobs/{jobId}
class TryOnJob {
  final String id;
  final String status; // queued | processing | done | error
  final String? resultUrl;
  final String? errorMessage;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  TryOnJob({
    required this.id,
    required this.status,
    this.resultUrl,
    this.errorMessage,
    this.createdAt,
    this.updatedAt,
  });

  factory TryOnJob.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};

    DateTime? _ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      return null;
    }

    return TryOnJob(
      id: doc.id,
      status: (d['status'] ?? 'queued').toString(),
      resultUrl: (d['resultUrl'] ?? d['result_url'])?.toString(),
      errorMessage: (d['errorMessage'] ?? d['error'] ?? d['message'])?.toString(),
      createdAt: _ts(d['createdAt']),
      updatedAt: _ts(d['updatedAt']),
    );
  }
}

class TryOnService {
  /// Callable Cloud Function name
  static const String _fnName = 'requestTryOn';

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  TryOnService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  })  : _functions = functions ?? FirebaseFunctions.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  /// Vytvorí Try-On job cez Cloud Function a vráti jobId.
  ///
  /// garmentCutoutImageUrl: preferujeme cutoutImageUrl (už bez pozadia)
  /// slot: napr. "torsoMid", "legsMid", "shoes"...
  /// sessionId: jedna session pre skladanie viacerých kusov na backend-e
  /// mannequinGender: "male" alebo "female"
  Future<String> requestTryOnJob({
    required String garmentCutoutImageUrl,
    required String slot,
    required String sessionId,
    required String mannequinGender,
  }) async {
    final callable = _functions.httpsCallable(_fnName);

    final payload = <String, dynamic>{
      'garmentImageUrl': garmentCutoutImageUrl,
      'slot': slot,
      'sessionId': sessionId,
      'mannequinGender': mannequinGender,
    };

    final res = await callable.call(payload);
    final data = res.data;

    if (data is Map) {
      final jobId = (data['jobId'] ?? data['id'] ?? data['job_id'])?.toString();
      if (jobId != null && jobId.trim().isNotEmpty) {
        return jobId.trim();
      }
    }

    throw Exception('requestTryOnJob: backend nevrátil jobId.');
  }

  /// Streamuje stav jobu.
  Stream<TryOnJob?> watchJob({required String uid, required String jobId}) {
    final ref = _firestore.collection('users').doc(uid).collection('tryon_jobs').doc(jobId);
    return ref.snapshots().map((snap) {
      if (!snap.exists) return null;
      return TryOnJob.fromDoc(snap);
    });
  }
}
