import 'dart:io';
import 'package:dio/dio.dart';
import '../models/agent_models.dart';
import '../network/dio_client.dart';
import '../storage/secure_storage.dart';

/// Client for the intelligent agent flow (RF-2):
/// classify → (optional) upload required docs → start process.
class AgentService {
  final Dio _dio = DioClient.create();

  /// RF-2.1: classify the client's free-text request into a business policy.
  Future<AgentClassifyResult> classify(String text) async {
    final response = await _dio.post('/agent/classify', data: {'text': text});
    return AgentClassifyResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// RF-2.2: send a recorded audio file and get back the transcribed text.
  Future<String> transcribe(String audioPath) async {
    final fileName = audioPath.split(Platform.pathSeparator).last;
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(audioPath, filename: fileName),
    });
    final response = await _dio.post('/agent/transcribe', data: form);
    return (response.data['text'] as String?) ?? '';
  }

  /// RF-2.5: full pre-process upload of one required document:
  /// initiate → PUT to S3 → confirm. Returns the confirmed document id.
  Future<String> uploadRequiredDocument({
    required String policyId,
    required String requirementId,
    required File file,
    required String mimeType,
  }) async {
    final clientId = await SecureStorageService.getUserId();
    final fileName = file.path.split(Platform.pathSeparator).last;

    // 1) initiate → presigned PUT URL
    final initRes = await _dio.post('/documents/pre-process', data: {
      'policyId': policyId,
      'documentRequirementId': requirementId,
      'fileName': fileName,
      'mimeType': mimeType,
      'clientId': clientId,
    });
    final documentId = initRes.data['documentId'] as String;
    final presignedUrl = initRes.data['presignedUrl'] as String;

    // 2) PUT bytes straight to S3 — use a clean Dio (NO auth interceptor,
    //    the Bearer header would break the S3 signature).
    //    The presigned URL signs `content-type;host`, so the PUT MUST send exactly
    //    the same Content-Type that was signed. Set it via Options.contentType
    //    (Dio's canonical field) — putting it only in the headers map lets Dio's
    //    default application/json leak through and S3 rejects with
    //    SignatureDoesNotMatch. contentLengthHeader avoids chunked transfer encoding
    //    (which S3 presigned PUT does not accept).
    final bytes = await file.readAsBytes();
    await Dio().put(
      presignedUrl,
      data: Stream.fromIterable([bytes]),
      options: Options(
        contentType: mimeType,
        headers: {
          Headers.contentLengthHeader: bytes.length,
        },
      ),
    );

    // 3) confirm
    await _dio.post('/documents/$documentId/confirm');
    return documentId;
  }

  /// Starts the process for the recommended policy on behalf of the logged-in client.
  Future<String> startProcess({
    required String policyId,
    required List<String> confirmedDocumentIds,
  }) async {
    final clientId = await SecureStorageService.getUserId();
    final response = await _dio.post('/processes', data: {
      'policyId': policyId,
      'initialData': <String, dynamic>{},
      'clientId': clientId,
      'confirmedDocumentIds': confirmedDocumentIds,
    });
    return (response.data['processInstanceId'] as String?) ?? '';
  }
}
