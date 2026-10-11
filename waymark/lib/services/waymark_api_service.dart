import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_session.dart';

class WayMarkApiException implements Exception {
  const WayMarkApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class WayMark {
  const WayMark({
    required this.id,
    required this.name,
    required this.location,
    required this.wayMarkCode,
  });

  final int? id;
  final String name;
  final String location;
  final String wayMarkCode;

  factory WayMark.fromJson(Map<String, dynamic> json) => WayMark(
    id: int.tryParse('${json['id'] ?? json['Id'] ?? ''}'),
    name: '${json['name'] ?? json['Name'] ?? ''}',
    location: '${json['location'] ?? json['Location'] ?? ''}',
    wayMarkCode: '${json['wayMarkCode'] ?? json['WayMarkCode'] ?? ''}',
  );
}

class WayMarkApiService {
  static const _configuredBaseUrl = String.fromEnvironment(
    'WAYMARK_API_BASE_URL',
  );
  static const _requestTimeout = Duration(seconds: 15);

  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    final host = defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : 'localhost';
    return 'http://$host:5121/api';
  }

  Future<List<WayMark>> getWayMarks() async {
    late final http.Response response;
    try {
      response = await http
          .get(Uri.parse('$baseUrl/WayMarks'), headers: _headers())
          .timeout(_requestTimeout);
    } on Exception catch (error) {
      throw Exception(
        'Không thể kết nối WayMark API tại $baseUrl. '
        'Hãy kiểm tra API đang chạy và địa chỉ kết nối. Chi tiết: $error',
      );
    }

    if (response.statusCode != 200) throw _httpError(response);

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const FormatException('Phản hồi API không phải danh sách.');
      }
      return decoded
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException('WayMark không đúng định dạng.');
            }
            return WayMark.fromJson(item);
          })
          .toList(growable: false);
    } on FormatException catch (error) {
      throw Exception('Dữ liệu WayMark API không hợp lệ: ${error.message}');
    }
  }

  Future<WayMark?> getWayMarkByCode(String code) async {
    final encodedCode = Uri.encodeComponent(code.trim());
    late final http.Response response;
    try {
      response = await http
          .get(
            Uri.parse('$baseUrl/WayMarks/code/$encodedCode'),
            headers: _headers(),
          )
          .timeout(_requestTimeout);
    } on Exception catch (error) {
      throw Exception(
        'Không thể kết nối WayMark API tại $baseUrl. Chi tiết: $error',
      );
    }

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw _httpError(response);

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Phản hồi API không phải một WayMark.');
      }
      return WayMark.fromJson(decoded);
    } on FormatException catch (error) {
      throw Exception('Dữ liệu WayMark API không hợp lệ: ${error.message}');
    }
  }

  Future<void> createWayMark({
    required String name,
    required String location,
    required String wayMarkCode,
  }) async {
    final response = await _sendCrudRequest(
      () => http.post(
        Uri.parse('$baseUrl/WayMarks'),
        headers: _headers(json: true),
        body: jsonEncode(_wayMarkBody(name, location, wayMarkCode)),
      ),
    );
    _ensureCrudSuccess(response, const {201});
  }

  Future<void> updateWayMark({
    required int id,
    required String name,
    required String location,
    required String wayMarkCode,
  }) async {
    final response = await _sendCrudRequest(
      () => http.put(
        Uri.parse('$baseUrl/WayMarks/$id'),
        headers: _headers(json: true),
        body: jsonEncode(_wayMarkBody(name, location, wayMarkCode)),
      ),
    );
    _ensureCrudSuccess(response, const {200, 204});
  }

  Future<void> deleteWayMark(int id) async {
    final response = await _sendCrudRequest(
      () =>
          http.delete(Uri.parse('$baseUrl/WayMarks/$id'), headers: _headers()),
    );
    _ensureCrudSuccess(response, const {200, 204});
  }

  Map<String, String> _wayMarkBody(
    String name,
    String location,
    String wayMarkCode,
  ) => {
    'Name': name.trim(),
    'Location': location.trim(),
    'WayMarkCode': wayMarkCode.trim(),
  };

  Map<String, String> _headers({bool json = false}) {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';

    final token = AuthSession.accessToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<http.Response> _sendCrudRequest(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request().timeout(_requestTimeout);
    } on Exception catch (error) {
      throw WayMarkApiException(
        'Không thể kết nối WayMark API tại $baseUrl. '
        'Hãy kiểm tra API đang chạy và địa chỉ kết nối. Chi tiết: $error',
      );
    }
  }

  void _ensureCrudSuccess(http.Response response, Set<int> acceptedStatuses) {
    if (acceptedStatuses.contains(response.statusCode)) return;
    throw _httpError(response);
  }

  WayMarkApiException _httpError(http.Response response) {
    final message = switch (response.statusCode) {
      400 => 'Dữ liệu không hợp lệ. Tên tối đa 200, vị trí 300 và mã WayMark 100 ký tự.',
      404 => 'WayMark không tồn tại hoặc đã bị xóa.',
      409 => 'Mã WayMark đã tồn tại. Hãy chọn mã khác.',
      401 => 'Bạn cần đăng nhập để truy cập dữ liệu WayMark.',
      403 => 'Tài khoản không có quyền truy cập thao tác này.',
      _ => 'WayMark API trả về lỗi HTTP ${response.statusCode}.',
    };
    return WayMarkApiException(message, statusCode: response.statusCode);
  }
}
