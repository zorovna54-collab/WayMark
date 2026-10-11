import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_session.dart';
import 'waymark_api_service.dart';

class AuthApiException implements Exception {
  const AuthApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AuthApiService {
  static String get baseUrl => WayMarkApiService.baseUrl;

  Future<void> register({
    required String username,
    required String password,
  }) async {
    final response = await _post('register', {
      'username': username.trim(),
      'password': password,
    });

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _responseError(response, registering: true);
    }
  }

  Future<String> login({
    required String username,
    required String password,
  }) async {
    final response = await _post('login', {
      'username': username.trim(),
      'password': password,
    });

    if (response.statusCode != 200) {
      throw _responseError(response);
    }

    try {
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Phản hồi đăng nhập không hợp lệ.');
      }
      final token = data['accessToken'];
      if (token is! String || token.isEmpty) {
        throw const FormatException('API không trả về JWT hợp lệ.');
      }

      AuthSession.accessToken = token;
      AuthSession.username = data['username'] as String? ?? username.trim();
      return token;
    } on FormatException catch (error) {
      throw AuthApiException(error.message, statusCode: response.statusCode);
    }
  }

  Future<http.Response> _post(String action, Map<String, String> body) async {
    try {
      return await http
          .post(
            Uri.parse('$baseUrl/Auth/$action'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } on Exception catch (error) {
      throw AuthApiException(
        'Không thể kết nối API tại $baseUrl. '
        'Kiểm tra API, CORS và địa chỉ kết nối. Chi tiết: $error',
      );
    }
  }

  AuthApiException _responseError(
    http.Response response, {
    bool registering = false,
  }) {
    final statusCode = response.statusCode;
    final message = switch (statusCode) {
      401 => 'Tên đăng nhập hoặc mật khẩu không đúng.',
      409 => 'Tên đăng nhập đã tồn tại. Hãy chọn tên khác.',
      400 when registering => 'Thông tin đăng ký chưa hợp lệ. Username cần 3–50 ký tự; password cần ít nhất 8 ký tự, có chữ hoa, chữ thường và chữ số.',
      400 => 'Vui lòng nhập username và password hợp lệ.',
      _ => _messageFromBody(response) ?? 'API trả về lỗi HTTP $statusCode.',
    };
    return AuthApiException(message, statusCode: statusCode);
  }

  String? _messageFromBody(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;
      if (data['message'] is String) return data['message'] as String;
      if (data['title'] is String) return data['title'] as String;

      final errors = data['errors'];
      if (errors is List) {
        return errors.map(_errorDescription).whereType<String>().join('; ');
      }
      if (errors is Map<String, dynamic>) {
        final descriptions = <String>[];
        for (final value in errors.values) {
          if (value is List) {
            descriptions.addAll(value.whereType<String>());
          } else if (value is String) {
            descriptions.add(value);
          }
        }
        if (descriptions.isNotEmpty) return descriptions.join('; ');
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  String? _errorDescription(Object? error) {
    if (error is String) return error;
    if (error is Map<String, dynamic> && error['description'] is String) {
      return error['description'] as String;
    }
    return null;
  }
}
