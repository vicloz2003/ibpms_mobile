import 'package:dio/dio.dart';
import '../models/process_models.dart';
import '../network/dio_client.dart';
import '../offline/connectivity_service.dart';
import '../offline/local_store.dart';
import '../offline/pending_operation.dart';
import '../offline/sync_queue.dart';

/// Trámite data access with offline support (RNF-6).
///
/// Reads are cached to [LocalStore] on every successful fetch and served from cache
/// when offline or on network failure (stale-while-offline). Mutations go through the
/// [SyncQueue]: when offline they are enqueued and replayed on reconnect.
class ProcessService {
  final Dio _dio = DioClient.create();

  static const _myProcessesKey = 'cache_my_processes';

  /// My trámites. Falls back to the last cached snapshot when the network is unavailable.
  Future<List<ProcessStatus>> getMyProcesses() async {
    try {
      final response = await _dio.get('/processes/my');
      final list = response.data as List;
      // Cache the raw JSON so an offline launch can still render the list.
      await LocalStore.instance.write(_myProcessesKey, list);
      return list
          .map((json) => ProcessStatus.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      if (_isNetworkError(e)) {
        final cached = await _readCachedProcesses();
        if (cached != null) return cached;
      }
      rethrow;
    }
  }

  /// Whether the last [getMyProcesses] would have come from cache (offline + cache present).
  Future<bool> hasCachedProcesses() async =>
      (await LocalStore.instance.read(_myProcessesKey)) != null;

  Future<List<ProcessStatus>?> _readCachedProcesses() async {
    final cached = await LocalStore.instance.read(_myProcessesKey);
    if (cached is List) {
      return cached
          .whereType<Map>()
          .map((e) => ProcessStatus.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return null;
  }

  /// Full, authoritative status for a single trámite (rich nodeProgress + percent).
  /// Used to refresh the detail screen when a lightweight WebSocket change-ping arrives.
  Future<ProcessStatus> getStatus(String processInstanceId) async {
    final response = await _dio.get('/processes/$processInstanceId/status');
    return ProcessStatus.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<DocumentModel>> getDocuments(String processInstanceId) async {
    final response = await _dio.get('/processes/$processInstanceId/documents');
    return (response.data as List)
        .map((json) => DocumentModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> getDownloadUrl(String documentId) async {
    final response = await _dio.get('/documents/$documentId/download');
    return response.data as Map<String, dynamic>;
  }

  /// Complete a task. Works offline: if there is no connectivity the operation is queued
  /// and synced on reconnect (CU-Offline). Returns `true` if sent now, `false` if queued.
  Future<bool> completeTask(
    String taskId, {
    Map<String, dynamic> formData = const {},
    int? baseVersion,
  }) async {
    final path = '/tasks/$taskId/complete';
    if (!ConnectivityService.instance.isOnline) {
      await _enqueueComplete(taskId, path, formData, baseVersion);
      return false;
    }
    try {
      await _dio.post(path, data: formData);
      return true;
    } on DioException catch (e) {
      if (_isNetworkError(e)) {
        await _enqueueComplete(taskId, path, formData, baseVersion);
        return false;
      }
      rethrow;
    }
  }

  Future<void> _enqueueComplete(
    String taskId,
    String path,
    Map<String, dynamic> formData,
    int? baseVersion,
  ) {
    return SyncQueue.instance.enqueue(PendingOperation(
      id: '${DateTime.now().microsecondsSinceEpoch}_$taskId',
      method: 'POST',
      path: path,
      body: formData,
      entityType: 'task',
      entityId: taskId,
      baseVersion: baseVersion,
      createdAt: DateTime.now(),
      description: 'Completar tarea $taskId',
    ));
  }

  bool _isNetworkError(DioException e) {
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.response == null;
  }
}
