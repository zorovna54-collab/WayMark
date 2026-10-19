import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_session.dart';
import '../models/route_models.dart';

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
  WayMarkApiService({this.client, Duration? requestTimeout})
    : _timeout = requestTimeout ?? _requestTimeout;

  // Injected clients remain owned by the caller (including tests).
  final http.Client? client;
  final Duration _timeout;
  static const _configuredBaseUrl = String.fromEnvironment(
    'WAYMARK_API_BASE_URL',
  );
  static const _requestTimeout = Duration(seconds: 15);

  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    }
    final host = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : 'localhost';
    return 'http://$host:5121/api';
  }

  Future<List<Map<String, dynamic>>> _mapList(String path) async {
    final uri = Uri.parse('$baseUrl/Maps/$path');
    try {
      final response =
          await (client?.get(uri, headers: _headers()) ??
                  http.get(uri, headers: _headers()))
              .timeout(_timeout);
      if (response.statusCode != 200) {
        throw WayMarkApiException(
          response.statusCode == 401
              ? 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.'
              : 'Không tải được danh sách bản đồ (HTTP ${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
      final items = (jsonDecode(utf8.decode(response.bodyBytes)) as List)
          .map((item) => item as Map<String, dynamic>)
          .toList();
      if (items.any(
        (item) =>
            item['id'] is! int ||
            (item['id'] as int) <= 0 ||
            item['name'] is! String,
      )) {
        throw const FormatException();
      }
      return items;
    } on WayMarkApiException {
      rethrow;
    } on TimeoutException {
      throw const WayMarkApiException('API phản hồi quá lâu.');
    } on FormatException {
      throw const WayMarkApiException('Danh sách bản đồ không hợp lệ.');
    } on TypeError {
      throw const WayMarkApiException('Danh sách bản đồ không hợp lệ.');
    } on Exception {
      throw const WayMarkApiException('Không thể kết nối WayMark API.');
    }
  }

  Future<List<Map<String, dynamic>>> getSites() => _mapList('sites');
  Future<List<Map<String, dynamic>>> getBuildings(int siteId) =>
      _mapList('sites/$siteId/buildings');
  Future<List<Map<String, dynamic>>> getFloors(int buildingId) =>
      _mapList('buildings/$buildingId/floors');

  Future<List<WayMark>> getWayMarks() async {
    late final http.Response response;
    try {
      response =
          await (client?.get(
                    Uri.parse('$baseUrl/WayMarks'),
                    headers: _headers(),
                  ) ??
                  http.get(Uri.parse('$baseUrl/WayMarks'), headers: _headers()))
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

  Future<WayMarkMapLocation> getMapLocation(String code) async {
    final encoded = Uri.encodeComponent(code.trim());
    final uri = Uri.parse('$baseUrl/WayMarks/code/$encoded/map-location');
    final json = await _readRoutingResponse(
      () =>
          client?.get(uri, headers: _headers()) ??
          http.get(uri, headers: _headers()),
      notFoundMessage: 'Không tìm thấy WayMark tương ứng với QR này.',
    );
    try {
      final location = WayMarkMapLocation.fromJson(json);
      if (location.wayMarkCode.toLowerCase() != code.trim().toLowerCase()) {
        throw const FormatException('Mismatched WayMark code.');
      }
      return location;
    } catch (error) {
      if (error is! FormatException && error is! TypeError) rethrow;
      throw const WayMarkApiException('Dữ liệu vị trí từ API không hợp lệ.');
    }
  }

  Future<FloorMapData> getFloorGraph(int floorId) async {
    final uri = Uri.parse('$baseUrl/Maps/floors/$floorId/graph');
    final json = await _readRoutingResponse(
      () =>
          client?.get(uri, headers: _headers()) ??
          http.get(uri, headers: _headers()),
      notFoundMessage: 'Không tìm thấy thông tin tầng trên bản đồ.',
    );
    try {
      final graph = FloorMapData.fromJson(json);
      if (graph.floor.id != floorId ||
          graph.nodes.any((node) => node.floorId != floorId) ||
          graph.nodes.map((node) => node.id).toSet().length !=
              graph.nodes.length) {
        throw const FormatException('Invalid floor graph.');
      }
      return graph;
    } catch (error) {
      if (error is! FormatException && error is! TypeError) rethrow;
      throw const WayMarkApiException(
        'Dữ liệu tọa độ hoặc thông tin tầng không hợp lệ.',
      );
    }
  }

  Future<WayMarkRoute> findRoute(
    RouteRequest request, {
    bool accessibleOnly = false,
  }) async {
    final codes = [
      request.startWayMarkCode.trim(),
      request.destinationWayMarkCode.trim(),
    ];
    if (codes.any(
      (code) =>
          code.isEmpty ||
          code.length > 100 ||
          RegExp(r'[\x00-\x1F\x7F]').hasMatch(code),
    )) {
      throw const WayMarkApiException(
        'Mã WayMark phải có từ 1 đến 100 ký tự hợp lệ.',
        statusCode: 400,
      );
    }
    final uri = Uri.parse('$baseUrl/routes')
        .replace(queryParameters: {'accessibleOnly': '$accessibleOnly'});
    final json = await _readRoutingResponse(
      () =>
          client?.post(
            uri,
            headers: _headers(json: true),
            body: jsonEncode(request.toJson()),
          ) ??
          http.post(
            uri,
            headers: _headers(json: true),
            body: jsonEncode(request.toJson()),
          ),
    );
    try {
      final route = WayMarkRoute.fromJson(json);
      if (route.start.wayMarkCode.toLowerCase() !=
              request.startWayMarkCode.trim().toLowerCase() ||
          route.destination.wayMarkCode.toLowerCase() !=
              request.destinationWayMarkCode.trim().toLowerCase() ||
          route.accessibleOnly != accessibleOnly ||
          !route.options.matches(request.options)) {
        throw const FormatException('Mismatched route response.');
      }
      return route;
    } catch (error) {
      if (error is! FormatException && error is! TypeError) rethrow;
      throw const WayMarkApiException(
        'Dữ liệu tuyến đường từ API không hợp lệ.',
      );
    }
  }

  Future<Map<String, dynamic>> _readRoutingResponse(
    Future<http.Response> Function() send, {
    String? notFoundMessage,
  }) async {
    late final http.Response response;
    try {
      response = await send().timeout(_timeout);
    } on TimeoutException {
      throw const WayMarkApiException(
        'API phản hồi quá lâu. Vui lòng thử lại.',
      );
    } on Exception {
      throw const WayMarkApiException(
        'Không thể kết nối WayMark API. Kiểm tra kết nối mạng và địa chỉ API.',
      );
    }
    if (response.statusCode != 200) {
      // Never display server exception details or raw response bodies in UI.
      final message = switch (response.statusCode) {
        400 => 'Yêu cầu tìm đường không hợp lệ. Hãy kiểm tra mã WayMark.',
        401 => 'Phiên đăng nhập đã hết hạn hoặc chưa đăng nhập. Vui lòng đăng nhập lại.',
        403 => 'Tài khoản không có quyền truy cập bản đồ.',
        404 => notFoundMessage ?? 'Không tìm thấy điểm xuất phát hoặc điểm đến. Hãy quét hoặc chọn lại.',
        409 => 'Điểm xuất phát hoặc điểm đến chưa được liên kết với node bản đồ hợp lệ.',
        422 =>
          _problemCode(response) == 'accessibility_not_verified'
              ? 'Hiện chưa có dữ liệu xác minh cho xe lăn. Cần khảo sát và phê duyệt; không tự chuyển sang tuyến thường.'
              : 'Không có tuyến đường đáp ứng bộ lọc. Không tự bỏ hạn chế để tìm tuyến khác.',
        503 => 'Dữ liệu bản đồ tạm thời không khả dụng. Vui lòng thử lại sau.',
        _ => 'Không thể tải tuyến đường (HTTP ${response.statusCode}).',
      };
      throw WayMarkApiException(message, statusCode: response.statusCode);
    }
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map<String, dynamic>) throw const FormatException();
      return json;
    } on FormatException {
      throw const WayMarkApiException(
        'Phản hồi API không đúng định dạng JSON.',
      );
    }
  }

  String? _problemCode(http.Response response) {
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data is Map && data['code'] is String
          ? data['code'] as String
          : null;
    } on FormatException {
      return null;
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
