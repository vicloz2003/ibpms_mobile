import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../network/dio_client.dart';
import 'connectivity_service.dart';
import 'local_store.dart';
import 'pending_operation.dart';

/// Result of a flush attempt, surfaced to the UI.
class SyncResult {
  final int synced;
  final int conflicts;
  final int remaining;
  const SyncResult({required this.synced, required this.conflicts, required this.remaining});
}

/// Persistent FIFO queue of offline mutations, replayed when connectivity returns (RNF-6).
///
/// Conflict policy (server-authoritative): a replayed op that the backend rejects with
/// **409 Conflict** (stale [PendingOperation.baseVersion]) is dropped rather than retried —
/// the server's state wins and the user is notified. Transient/network failures keep the op
/// queued for the next flush. 4xx other than 409 are treated as permanent and dropped to avoid
/// poison-message loops.
class SyncQueue extends ChangeNotifier {
  SyncQueue._() {
    _connectivity.onStatusChange.listen((online) {
      if (online) flush();
    });
    _restore();
  }
  static final SyncQueue instance = SyncQueue._();

  static const _storeKey = 'sync_queue';

  final Dio _dio = DioClient.create();
  final ConnectivityService _connectivity = ConnectivityService.instance;

  final List<PendingOperation> _queue = [];
  bool _restored = false;
  bool _flushing = false;

  List<PendingOperation> get pending => List.unmodifiable(_queue);
  int get pendingCount => _queue.length;
  bool get isFlushing => _flushing;

  Future<void> _restore() async {
    if (_restored) return;
    final raw = await LocalStore.instance.read(_storeKey);
    if (raw is List) {
      _queue
        ..clear()
        ..addAll(raw.whereType<Map>().map((e) => PendingOperation.fromJson(e.cast<String, dynamic>())));
    }
    _restored = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    await LocalStore.instance.write(_storeKey, _queue.map((o) => o.toJson()).toList());
  }

  /// Enqueue a mutation. Returns immediately; the op is flushed now (if online) or later.
  Future<void> enqueue(PendingOperation op) async {
    await _restore();
    _queue.add(op);
    await _persist();
    notifyListeners();
    if (_connectivity.isOnline) {
      // Fire-and-forget; UI already reflects the optimistic state.
      unawaited(flush());
    }
  }

  /// Replay every queued op in order. Safe to call repeatedly; re-entrancy guarded.
  Future<SyncResult> flush() async {
    await _restore();
    if (_flushing || _queue.isEmpty) {
      return SyncResult(synced: 0, conflicts: 0, remaining: _queue.length);
    }
    _flushing = true;
    notifyListeners();

    int synced = 0;
    int conflicts = 0;
    try {
      // Snapshot to iterate; FIFO so a failed transient op stops the run to preserve order.
      while (_queue.isNotEmpty) {
        final op = _queue.first;
        final outcome = await _send(op);
        if (outcome == _Outcome.success) {
          _queue.removeAt(0);
          synced++;
          await _persist();
          notifyListeners();
        } else if (outcome == _Outcome.permanent) {
          _queue.removeAt(0);
          conflicts++;
          await _persist();
          notifyListeners();
        } else {
          // transient — stop and keep order; will retry on next connectivity event
          break;
        }
      }
    } finally {
      _flushing = false;
      notifyListeners();
    }
    return SyncResult(synced: synced, conflicts: conflicts, remaining: _queue.length);
  }

  Future<_Outcome> _send(PendingOperation op) async {
    try {
      final headers = <String, dynamic>{};
      if (op.baseVersion != null) headers['If-Match'] = '"${op.baseVersion}"';
      await _dio.request(
        op.path,
        data: op.body,
        options: Options(method: op.method, headers: headers.isEmpty ? null : headers),
      );
      return _Outcome.success;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == null) return _Outcome.transient; // no response → network/server down
      if (status == 409) return _Outcome.permanent; // stale write, server wins
      if (status >= 400 && status < 500) return _Outcome.permanent; // bad request → don't loop
      return _Outcome.transient; // 5xx → retry later
    } catch (_) {
      return _Outcome.transient;
    }
  }

  /// Discard a queued op the user chose not to retry (e.g. after a conflict review).
  Future<void> discard(String id) async {
    _queue.removeWhere((o) => o.id == id);
    await _persist();
    notifyListeners();
  }
}

enum _Outcome { success, transient, permanent }
