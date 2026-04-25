import 'package:dio/dio.dart';
import '../models/process_models.dart';
import '../network/dio_client.dart';

class ProcessService {
  final Dio _dio = DioClient.create();

  Future<List<ProcessStatus>> getMyProcesses() async {
    final response = await _dio.get('/processes/my');
    return (response.data as List)
        .map((json) => ProcessStatus.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
