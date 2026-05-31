/// A mutating API call captured while offline, to be replayed on reconnect (RNF-6).
///
/// Operations are stored FIFO and carry enough context for conflict resolution:
/// [entityType]/[entityId] identify the target and [baseVersion] (when known) lets
/// the server reject a stale write (HTTP 409) instead of clobbering newer data.
class PendingOperation {
  final String id;
  final String method; // POST | PUT | PATCH | DELETE
  final String path; // relative to Dio baseUrl, e.g. /tasks/123/complete
  final Map<String, dynamic>? body;
  final String entityType; // e.g. "task"
  final String entityId;
  final int? baseVersion; // optimistic-concurrency hint, if the entity exposes one
  final DateTime createdAt;
  final String description; // human label for the pending-actions UI

  PendingOperation({
    required this.id,
    required this.method,
    required this.path,
    this.body,
    required this.entityType,
    required this.entityId,
    this.baseVersion,
    required this.createdAt,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method,
        'path': path,
        'body': body,
        'entityType': entityType,
        'entityId': entityId,
        'baseVersion': baseVersion,
        'createdAt': createdAt.toIso8601String(),
        'description': description,
      };

  factory PendingOperation.fromJson(Map<String, dynamic> json) => PendingOperation(
        id: json['id'] as String,
        method: json['method'] as String,
        path: json['path'] as String,
        body: (json['body'] as Map?)?.cast<String, dynamic>(),
        entityType: json['entityType'] as String,
        entityId: json['entityId'] as String,
        baseVersion: json['baseVersion'] as int?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        description: (json['description'] as String?) ?? 'Operación pendiente',
      );
}
