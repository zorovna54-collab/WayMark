import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/ai_config.dart';

class LmStudioException implements Exception {
  const LmStudioException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LmStudioService {
  static const _configuredBaseUrl = String.fromEnvironment('LM_STUDIO_URL');
  static const _configuredApiToken = String.fromEnvironment(
    'LM_STUDIO_API_TOKEN',
  );

  LmStudioService({
    http.Client? client,
    String? baseUrl,
    String? apiToken,
    this.timeout = const Duration(seconds: 45),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _baseUrl =
           (baseUrl ??
                   (_configuredBaseUrl.isEmpty
                       ? AIConfig.baseUrl
                       : _configuredBaseUrl))
               .replaceFirst(RegExp(r'/+$'), ''),
       _apiToken = apiToken ?? _configuredApiToken;

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;
  final String _apiToken;
  final Duration timeout;

  String get baseUrl => _baseUrl;

  Future<List<String>> getModels() async {
    final response = await _send(
      () => _client.get(Uri.parse('$_baseUrl/models'), headers: _headers()),
    );
    final decoded = _decodeJson(response);
    if (decoded is! Map<String, dynamic> || decoded['data'] is! List) {
      throw const LmStudioException(
        'Phản hồi danh sách model từ LM Studio không đúng định dạng.',
      );
    }

    final models = <String>[];
    for (final item in decoded['data'] as List) {
      if (item is Map<String, dynamic> && item['id'] is String) {
        final id = (item['id'] as String).trim();
        if (id.isNotEmpty) models.add(id);
      }
    }
    return models;
  }

  Future<String> ask({
    required String model,
    required String question,
    double temperature = 0.7,
    int maxTokens = 512,
  }) async {
    final response = await _send(
      () => _client.post(
        Uri.parse('$_baseUrl/chat/completions'),
        headers: _headers(json: true),
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'user', 'content': question},
          ],
          'temperature': temperature,
          'max_tokens': maxTokens,
          'stream': false,
        }),
      ),
    );

    final decoded = _decodeJson(response);
    if (decoded is! Map<String, dynamic> || decoded['choices'] is! List) {
      throw const LmStudioException(
        'Phản hồi chat từ LM Studio không có danh sách choices hợp lệ.',
      );
    }

    final choices = decoded['choices'] as List;
    if (choices.isEmpty || choices.first is! Map<String, dynamic>) {
      throw const LmStudioException(
        'LM Studio chưa trả về câu trả lời nào. Hãy thử gửi lại.',
      );
    }

    final message = (choices.first as Map<String, dynamic>)['message'];
    if (message is! Map<String, dynamic> || message['content'] is! String) {
      throw const LmStudioException(
        'Nội dung câu trả lời từ LM Studio không đúng định dạng.',
      );
    }

    final answer = (message['content'] as String).trim();
    if (answer.isEmpty) {
      throw const LmStudioException('LM Studio trả về câu trả lời rỗng.');
    }
    return answer;
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    late final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw const LmStudioException(
        'LM Studio phản hồi quá thời gian chờ. Hãy kiểm tra model và thử lại.',
      );
    } on http.ClientException catch (error) {
      throw LmStudioException(
        'Không thể kết nối LM Studio tại $_baseUrl (${error.message}). '
        'Kiểm tra server; nếu chạy Flutter Web, kiểm tra CORS trong LM Studio.',
      );
    } on FormatException {
      throw const LmStudioException('URL LM Studio không hợp lệ.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const LmStudioException(
          'LM Studio yêu cầu xác thực. Nếu server bật API token, chạy Flutter '
          'với --dart-define=LM_STUDIO_API_TOKEN=<token>.',
        );
      }
      throw LmStudioException(
        'LM Studio trả về HTTP ${response.statusCode}. '
        'Kiểm tra trạng thái server và cấu hình model.',
      );
    }
    return response;
  }

  Map<String, String> _headers({bool json = false}) => {
    if (json) 'Content-Type': 'application/json',
    if (_apiToken.isNotEmpty) 'Authorization': 'Bearer $_apiToken',
  };

  dynamic _decodeJson(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const LmStudioException(
        'LM Studio trả về JSON không hợp lệ hoặc không phải UTF-8.',
      );
    }
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
