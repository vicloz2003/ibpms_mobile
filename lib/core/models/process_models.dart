enum InstanceStatus { ACTIVE, COMPLETED, CANCELLED }

enum DocumentStatus { PENDING_UPLOAD, CONFIRMED, DELETED }

class NodeProgressItem {
  final String nodeId;
  final String nodeLabel;
  final String? departmentName;
  final String status; // COMPLETED | CURRENT | PENDING
  final String? completedAt;
  final String? assignedToName; // funcionario responsable
  final int documentCount;

  const NodeProgressItem({
    required this.nodeId,
    required this.nodeLabel,
    this.departmentName,
    required this.status,
    this.completedAt,
    this.assignedToName,
    this.documentCount = 0,
  });

  factory NodeProgressItem.fromJson(Map<String, dynamic> json) => NodeProgressItem(
        nodeId: json['nodeId'] as String,
        nodeLabel: json['nodeLabel'] as String,
        departmentName: json['departmentName'] as String?,
        // Backend field is "progressStatus"; tolerate legacy "status".
        status: (json['progressStatus'] ?? json['status'] ?? 'PENDING') as String,
        completedAt: json['completedAt'] as String?,
        assignedToName: json['assignedToName'] as String?,
        documentCount: (json['documentCount'] as int?) ?? 0,
      );
}

class DocumentModel {
  final String id;
  final String? processInstanceId;
  final String businessPolicyId;
  final String? documentRequirementId;
  final String fileName;
  final String mimeType;
  final String uploadedBy;
  final String uploadedByRole;
  final DocumentStatus status;
  final String uploadedAt;
  final String? confirmedAt;
  final String? taskId;

  const DocumentModel({
    required this.id,
    this.processInstanceId,
    required this.businessPolicyId,
    this.documentRequirementId,
    required this.fileName,
    required this.mimeType,
    required this.uploadedBy,
    required this.uploadedByRole,
    required this.status,
    required this.uploadedAt,
    this.confirmedAt,
    this.taskId,
  });

  factory DocumentModel.fromJson(Map<String, dynamic> json) => DocumentModel(
        id: json['id'] as String,
        processInstanceId: json['processInstanceId'] as String?,
        businessPolicyId: json['businessPolicyId'] as String,
        documentRequirementId: json['documentRequirementId'] as String?,
        fileName: json['fileName'] as String,
        mimeType: json['mimeType'] as String,
        uploadedBy: json['uploadedBy'] as String,
        uploadedByRole: json['uploadedByRole'] as String,
        status: DocumentStatus.values.firstWhere(
          (e) => e.name == (json['status'] as String),
          orElse: () => DocumentStatus.PENDING_UPLOAD,
        ),
        uploadedAt: (json['uploadedAt'] as String?) ?? '',
        confirmedAt: json['confirmedAt'] as String?,
        taskId: json['taskId'] as String?,
      );
}

class ProcessStatus {
  final String processInstanceId;
  final String? businessPolicyId;
  final String currentNodeId;
  final String currentNodeLabel;
  final String? currentDepartmentName;
  final InstanceStatus status;
  final String startedAt;
  final String? completedAt;
  final String? clientId;
  final String policyName;
  final List<NodeProgressItem> nodeProgress;
  final int progressPercent;
  final String? pendingClientAction;

  const ProcessStatus({
    required this.processInstanceId,
    this.businessPolicyId,
    required this.currentNodeId,
    required this.currentNodeLabel,
    this.currentDepartmentName,
    required this.status,
    required this.startedAt,
    this.completedAt,
    this.clientId,
    required this.policyName,
    this.nodeProgress = const [],
    this.progressPercent = 0,
    this.pendingClientAction,
  });

  factory ProcessStatus.fromJson(Map<String, dynamic> json) => ProcessStatus(
        processInstanceId: json['processInstanceId'] as String,
        businessPolicyId: json['businessPolicyId'] as String?,
        currentNodeId: json['currentNodeId'] as String,
        currentNodeLabel: (json['currentNodeLabel'] as String?) ?? json['currentNodeId'] as String,
        currentDepartmentName: json['currentDepartmentName'] as String?,
        status: InstanceStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => InstanceStatus.ACTIVE,
        ),
        startedAt: (json['startedAt'] as String?) ?? '',
        completedAt: json['completedAt'] as String?,
        clientId: json['clientId'] as String?,
        policyName: (json['policyName'] as String?) ?? 'Sin nombre',
        nodeProgress: json['nodeProgress'] == null
            ? []
            : (json['nodeProgress'] as List)
                .map((e) => NodeProgressItem.fromJson(e as Map<String, dynamic>))
                .toList(),
        progressPercent: (json['progressPercent'] as int?) ?? 0,
        pendingClientAction: json['pendingClientAction'] as String?,
      );
}
