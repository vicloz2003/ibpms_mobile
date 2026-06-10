// Models for the intelligent agent (RF-2): classification result + required docs.

class AgentDocRequirement {
  final String id;
  final String name;
  final String? description;
  final List<String> allowedMimeTypes;
  final bool mandatory;
  final String uploadStage;
  final String uploaderRole;

  const AgentDocRequirement({
    required this.id,
    required this.name,
    this.description,
    this.allowedMimeTypes = const [],
    required this.mandatory,
    required this.uploadStage,
    required this.uploaderRole,
  });

  factory AgentDocRequirement.fromJson(Map<String, dynamic> json) =>
      AgentDocRequirement(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        allowedMimeTypes: (json['allowedMimeTypes'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        mandatory: (json['mandatory'] as bool?) ?? false,
        uploadStage: (json['uploadStage'] as String?) ?? 'PROCESS_START',
        uploaderRole: (json['uploaderRole'] as String?) ?? 'ANY',
      );
}

class PolicyMatch {
  final String policyId;
  final String policyName;
  final double score;

  const PolicyMatch({
    required this.policyId,
    required this.policyName,
    required this.score,
  });

  factory PolicyMatch.fromJson(Map<String, dynamic> json) => PolicyMatch(
        policyId: (json['policyId'] ?? '') as String,
        policyName: (json['policyName'] ?? '') as String,
        score: ((json['score'] ?? 0) as num).toDouble(),
      );
}

class AgentClassifyResult {
  final String? policyId;
  final String? policyName;
  final double confidence;
  final bool confident;
  final List<PolicyMatch> alternatives;
  final String message;
  final List<AgentDocRequirement> requiredDocuments;

  const AgentClassifyResult({
    this.policyId,
    this.policyName,
    required this.confidence,
    required this.confident,
    this.alternatives = const [],
    required this.message,
    this.requiredDocuments = const [],
  });

  factory AgentClassifyResult.fromJson(Map<String, dynamic> json) =>
      AgentClassifyResult(
        policyId: json['policyId'] as String?,
        policyName: json['policyName'] as String?,
        confidence: ((json['confidence'] ?? 0) as num).toDouble(),
        confident: (json['confident'] as bool?) ?? false,
        alternatives: (json['alternatives'] as List?)
                ?.map((e) => PolicyMatch.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        message: (json['message'] as String?) ?? '',
        requiredDocuments: (json['requiredDocuments'] as List?)
                ?.map((e) =>
                    AgentDocRequirement.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}
