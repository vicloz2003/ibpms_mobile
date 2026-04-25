enum InstanceStatus { ACTIVE, COMPLETED, CANCELLED }

class ProcessStatus {
  final String processInstanceId;
  final String currentNodeId;
  final String currentNodeLabel;
  final InstanceStatus status;
  final String startedAt;
  final String? clientId;
  final String policyName;

  const ProcessStatus({
    required this.processInstanceId,
    required this.currentNodeId,
    required this.currentNodeLabel,
    required this.status,
    required this.startedAt,
    this.clientId,
    required this.policyName,
  });

  factory ProcessStatus.fromJson(Map<String, dynamic> json) => ProcessStatus(
        processInstanceId: json['processInstanceId'] as String,
        currentNodeId: json['currentNodeId'] as String,
        currentNodeLabel: (json['currentNodeLabel'] as String?) ?? json['currentNodeId'] as String,
        status: InstanceStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => InstanceStatus.ACTIVE,
        ),
        startedAt: (json['startedAt'] as String?) ?? '',
        clientId: json['clientId'] as String?,
        policyName: (json['policyName'] as String?) ?? 'Sin nombre',
      );
}
