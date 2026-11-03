import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_session.dart';
import '../models/account_profile.dart';
import 'waymark_api_service.dart';

class AuthApiException implements Exception {
  const AuthApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AuthApiService {
  AuthApiService({this.client});
  final http.Client? client;
  static String get baseUrl => WayMarkApiService.baseUrl;
  static int _loginAttempt = 0;
  int? _ownedLoginAttempt;

  void cancelPendingLogin() {
    if (_ownedLoginAttempt == _loginAttempt) _loginAttempt++;
  }

  Future<void> register({
    required String username,
    required String password,
    String? email,
  }) async {
    final body = <String, String>{
      'username': username.trim(),
      'password': password,
    };
    if (email != null && email.trim().isNotEmpty) {
      body['email'] = email.trim();
    }

    final response = await _post('register', body);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _responseError(response, registering: true);
    }
  }

  Future<String> login({
    required String username,
    required String password,
  }) async {
    final attempt = ++_loginAttempt;
    _ownedLoginAttempt = attempt;
    final revision = AuthSession.revision;
    final response = await _post('login', {
      'username': username.trim(),
      'password': password,
    });

    if (attempt != _loginAttempt || AuthSession.revision != revision) {
      throw const AuthApiException('Phiên đăng nhập đã thay đổi.');
    }

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

      final name = data['username'];
      if (name != null && name is! String) {
        throw const FormatException('Phản hồi đăng nhập không hợp lệ.');
      }
      AuthSession.establish(token, name as String? ?? username.trim());
      return token;
    } on FormatException catch (error) {
      throw AuthApiException(error.message, statusCode: response.statusCode);
    }
  }

  Future<AccountProfile> getProfile() => _profile();
  Future<void> accountAction(String action, Map<String, String> body) async {
    AuthSession.checkWorkflow();
    final token = AuthSession.accessToken;
    final revision = AuthSession.revision;
    if (token == null || AuthSession.expired) {
      throw const AuthApiException('Hãy đăng nhập lại.', statusCode: 401);
    }
    try {
      final uri = Uri.parse('$baseUrl/Auth/me/$action');
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final response =
          await (client?.post(uri, headers: headers, body: jsonEncode(body)) ??
                  http.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(const Duration(seconds: 25));
      if (!AuthSession.isCurrent(token, revision)) {
        throw const AuthApiException(
          'Phiên đăng nhập đã thay đổi.',
          statusCode: 401,
        );
      }
      if (response.statusCode != 200) {
        if (response.statusCode == 401) {
          AuthSession.rejectUnauthorized(token, revision);
        }
        throw AuthApiException(
          _messageFromBody(response) ??
              'Không hoàn tất yêu cầu (HTTP ${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
    } on AuthApiException {
      rethrow;
    } on Exception {
      throw const AuthApiException(
        'Không kết nối được API. Chưa xác nhận thay đổi tài khoản.',
      );
    }
  }

  Future<String> checkConnection() async {
    try {
      final uri = Uri.parse('$baseUrl/WayMarks');
      // No token or data mutation is needed to probe this protected endpoint.
      final response = await (client?.get(uri) ?? http.get(uri)).timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode == 200 || response.statusCode == 401) {
        return response.statusCode == 401
            ? 'Đã kết nối API (HTTP 401). Dữ liệu riêng cần đăng nhập; đây không phải lỗi mạng.'
            : 'Đã kết nối API (HTTP 200).';
      }
      throw AuthApiException(
        'API phản hồi HTTP ${response.statusCode}. Kiểm tra cấu hình/backend.',
      );
    } on AuthApiException {
      rethrow;
    } on Exception {
      throw const AuthApiException(
        'Không kết nối được API. Kiểm tra mạng và địa chỉ server.',
      );
    }
  }

  Future<AccountProfile> updateProfile(String displayName) =>
      _profile(displayName: displayName);

  Future<AccountProfile> _profile({String? displayName}) async {
    AuthSession.checkWorkflow();
    final token = AuthSession.accessToken;
    final revision = AuthSession.revision;
    if (token == null || token.isEmpty || AuthSession.expired) {
      throw const AuthApiException(
        'Vui lòng đăng nhập để xem hồ sơ.',
        statusCode: 401,
      );
    }
    try {
      final uri = Uri.parse('$baseUrl/Auth/me');
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final response =
          await (displayName == null
                  ? (client?.get(uri, headers: headers) ??
                        http.get(uri, headers: headers))
                  : (client?.put(
                          uri,
                          headers: headers,
                          body: jsonEncode({'displayName': displayName.trim()}),
                        ) ??
                        http.put(
                          uri,
                          headers: headers,
                          body: jsonEncode({'displayName': displayName.trim()}),
                        )))
              .timeout(const Duration(seconds: 15));
      if (!AuthSession.isCurrent(token, revision)) {
        throw const AuthApiException(
          'Phiên đăng nhập đã thay đổi.',
          statusCode: 401,
        );
      }
      if (response.statusCode != 200) {
        if (response.statusCode == 401) {
          AuthSession.rejectUnauthorized(token, revision);
        }
        throw AuthApiException(
          response.statusCode == 401
              ? 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.'
              : _messageFromBody(response) ??
                    'Không tải/lưu được hồ sơ (HTTP ${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Dữ liệu hồ sơ không hợp lệ.');
      }
      final profile = AccountProfile.fromJson(data);
      AuthSession.profile = profile;
      return profile;
    } on AuthApiException {
      rethrow;
    } on FormatException {
      throw const AuthApiException('API trả về hồ sơ không hợp lệ.');
    } on Exception {
      throw const AuthApiException(
        'Không kết nối được API. Kiểm tra mạng và thử lại.',
      );
    }
  }

  Future<void> requestPasswordReset({required String usernameOrEmail}) async {
    final response = await _post('forgot-password', {
      'usernameOrEmail': usernameOrEmail.trim(),
    });

    if (response.statusCode != 200) {
      throw _responseError(response, resetting: true);
    }
  }

  Future<void> resetPassword({
    required String usernameOrEmail,
    required String token,
    required String newPassword,
  }) async {
    final response = await _post('reset-password', {
      'usernameOrEmail': usernameOrEmail.trim(),
      'token': token.trim(),
      'newPassword': newPassword,
    });

    if (response.statusCode != 200) {
      throw _responseError(response, resetting: true);
    }
  }

  Future<http.Response> _post(String action, Map<String, String> body) async {
    try {
      return await (client?.post(
                Uri.parse('$baseUrl/Auth/$action'),
                headers: const {'Content-Type': 'application/json'},
                body: jsonEncode(body),
              ) ??
              http.post(
                Uri.parse('$baseUrl/Auth/$action'),
                headers: const {'Content-Type': 'application/json'},
                body: jsonEncode(body),
              ))
          .timeout(const Duration(seconds: 15));
    } on Exception {
      throw AuthApiException(
        'Không thể kết nối API tại $baseUrl. '
        'Kiểm tra máy chủ và kết nối mạng rồi thử lại.',
      );
    }
  }

  AuthApiException _responseError(
    http.Response response, {
    bool registering = false,
    bool resetting = false,
  }) {
    final statusCode = response.statusCode;
    final message = switch (statusCode) {
      403 when resetting => 'Máy chủ đang từ chối yêu cầu đặt lại mật khẩu (403). Chức năng này không cần đăng nhập; kiểm tra đúng địa chỉ API và phiên bản backend.',
      429 => 'Bạn đã gửi quá nhiều yêu cầu. Vui lòng chờ 10 phút rồi thử lại.',
      401 => 'Tên đăng nhập hoặc mật khẩu không đúng.',
      409 => 'Tên đăng nhập đã tồn tại. Hãy chọn tên khác.',
      400 when registering => 'Thông tin đăng ký chưa hợp lệ. Username cần 3–50 ký tự; password cần ít nhất 8 ký tự, có chữ hoa, chữ thường và chữ số.',
      400 =>
        _messageFromBody(response) ??
            'Thông tin chưa hợp lệ. Vui lòng kiểm tra lại.',
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
