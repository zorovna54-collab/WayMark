import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'auth_session.dart';
import 'waymark_api_service.dart';

class MapDraftApiException implements Exception {
  const MapDraftApiException(this.message, {this.status, this.code});
  final String message;
  final int? status;
  final String? code;
  bool get versionConflict => status == 409 && code == 'draft_version_conflict';
  bool get uncertain =>
      status == null ||
      // Managed provider emits this code before acquiring/writing any object.
      // Other 503s (including metadata/DB failures) still require reconciliation.
      (status == 503 && code != 'image_storage_unavailable') ||
      code == 'invalid_response' ||
      // The old account's request may already have committed on the server.
      code == 'auth_session_changed';
  @override
  String toString() => message;
}

class DraftMetadata {
  DraftMetadata.fromJson(Map<String, dynamic> j)
    : id = draftGuid(j['id']),
      siteId = draftPositive(j['siteId']),
      buildingId = draftPositive(j['buildingId']),
      floorId = draftPositive(j['floorId']),
      version = draftPositive(j['version']),
      updatedAt = DateTime.parse(j['updatedAt'] as String) {
    if (j['status'] != 'Draft') {
      throw const FormatException('Invalid draft status');
    }
  }
  final String id;
  final int siteId, buildingId, floorId, version;
  final DateTime updatedAt;
}

class DraftRevision {
  DraftRevision.fromJson(Map<String, dynamic> j)
    : version = draftPositive(j['version']),
      createdAt = DateTime.parse(j['createdAt'] as String);
  final int version;
  final DateTime createdAt;
}

class DraftImageMetadata {
  DraftImageMetadata.fromJson(Map<String, dynamic> j)
    : id = draftGuid(j['id']),
      floorId = draftPositive(j['floorId']),
      mime = j['mimeType'] as String,
      width = draftPositive(j['width']),
      height = draftPositive(j['height']),
      byteLength = draftPositive(j['byteLength']),
      sha256 = j['sha256'] as String {
    if (!['image/png', 'image/jpeg'].contains(mime) ||
        width > 8192 ||
        height > 8192 ||
        width * height > 32000000 ||
        byteLength > 10 * 1024 * 1024 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('Invalid image metadata');
    }
  }
  final String id, mime, sha256;
  final int floorId, width, height, byteLength;
}

String draftGuid(dynamic value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value) ||
      value == '00000000-0000-0000-0000-000000000000') {
    throw const FormatException('Invalid draft identifier');
  }
  return value.toLowerCase();
}

int draftPositive(dynamic value) {
  if (value is! int || value <= 0 || value > 9007199254740991) {
    throw const FormatException('Invalid positive integer');
  }
  return value;
}

/// Private draft API only. Uses the existing base URL and current AuthSession.
/// The injected HTTP client remains owned by its caller.
class MapDraftApiService {
  MapDraftApiService({this.client, this.timeout = const Duration(seconds: 30)});
  final http.Client? client;
  final Duration timeout;

  Future<http.Response> _request(
    int floor,
    String method,
    String suffix, {
    Object? json,
    Uint8List? bytes,
    String? mime,
  }) async {
    draftPositive(floor);
    AuthSession.checkWorkflow();
    final token = AuthSession.accessToken;
    final revision = AuthSession.revision;
    if (token == null || token.isEmpty || AuthSession.expired) {
      throw const MapDraftApiException(
        'Vui lòng đăng nhập lại để dùng bản nháp server.',
        status: 401,
      );
    }
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };
    final request = http.Request(
      method,
      Uri.parse(
        '${WayMarkApiService.baseUrl}/admin/floors/$floor/map-drafts$suffix',
      ),
    );
    request.headers.addAll(headers);
    if (bytes != null) {
      request.headers['Content-Type'] = mime!;
      request.bodyBytes = bytes;
    } else if (json != null) {
      final encoded = utf8.encode(jsonEncode(json));
      if (encoded.length > 2 * 1024 * 1024) {
        throw const MapDraftApiException(
          'Graph vượt giới hạn tài liệu 2 MiB.',
          status: 413,
        );
      }
      request.headers['Content-Type'] = 'application/json';
      request.bodyBytes = encoded;
    }
    final owned = client == null ? http.Client() : null;
    try {
      final response = await (() async => http.Response.fromStream(
        await (client ?? owned!).send(request),
      ))().timeout(timeout);
      if (!AuthSession.isCurrent(token, revision)) {
        throw const MapDraftApiException(
          'Phiên đăng nhập đã thay đổi. Không áp dụng phản hồi cũ; đối chiếu lần lưu trước khi thử lại.',
          status: 401,
          code: 'auth_session_changed',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401) {
          AuthSession.rejectUnauthorized(token, revision);
        }
        throw _error(response);
      }
      return response;
    } on MapDraftApiException {
      rethrow;
    } on TimeoutException {
      throw const MapDraftApiException(
        'API hết thời gian phản hồi. Bản local còn nguyên; kết quả ghi có thể chưa xác định.',
        code: 'timeout',
      );
    } on http.ClientException {
      throw const MapDraftApiException(
        'Không thể kết nối API. Bản local còn nguyên; hãy kiểm tra mạng.',
        code: 'network',
      );
    } finally {
      owned?.close();
    }
  }

  MapDraftApiException _error(http.Response r) {
    String? code;
    try {
      code = (jsonDecode(r.body) as Map)['code'] as String?;
    } catch (_) {
      /* middleware may return no JSON */
    }
    final message = switch (r.statusCode) {
      503 when code == 'image_storage_unavailable' => 'Backend chưa bật kho ảnh (MapImages). Upload ảnh đã bị từ chối; graph chưa được lưu. Operator cần cấu hình kho ảnh riêng ngoài Git và restart API.',
      503 when code == 'image_storage_configuration' => 'Cấu hình kho ảnh chưa hợp lệ: kiểm tra MapImages:RootPath/quota ngoài Git. Chưa lưu ảnh/graph; không sửa database hoặc quyền Admin để né lỗi.',
      400 => 'Bản nháp/ảnh không hợp lệ. Kiểm tra node, cạnh, Room/Place và liên kết cửa.',
      401 => 'Phiên đăng nhập thiếu hoặc hết hạn. Vui lòng đăng nhập lại.',
      403 => 'Cần quyền tạo bản đồ, Site membership còn hiệu lực và quyền với bản nháp này.',
      404 =>
        'Không tìm thấy bản nháp, phiên bản hoặc ảnh trong tầng được phép.',
      409 when code == 'draft_version_conflict' => 'Phiên bản server đã thay đổi. Giữ local hoặc tải bản mới; không ghi đè tự động.',
      409 =>
        'Server từ chối do quota hoặc xung đột tài nguyên${code == null ? '' : ' ($code)'}. Không phải xác nhận đã lưu.',
      413 => 'Ảnh hoặc tài liệu vượt giới hạn dung lượng server.',
      503 => 'Kho ảnh/dữ liệu bản nháp chưa khả dụng. Chưa xác nhận lưu; bản local được giữ nguyên.',
      _ => 'API bản nháp trả HTTP ${r.statusCode}. Bản local được giữ nguyên.',
    };
    return MapDraftApiException(message, status: r.statusCode, code: code);
  }

  T _parse<T>(http.Response response, T Function(dynamic) parse) {
    try {
      return parse(jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (_) {
      throw const MapDraftApiException(
        'Phản hồi server không hợp lệ; chưa xác nhận lưu hoặc tải.',
        code: 'invalid_response',
      );
    }
  }

  Future<DraftMetadata> metadata(int floor) async => _parse(
    await _request(floor, 'GET', ''),
    (j) => DraftMetadata.fromJson(j as Map<String, dynamic>),
  );
  Future<DraftMetadata> create(int floor, Map<String, dynamic> content) async =>
      _parse(
        await _request(floor, 'POST', '', json: content),
        (j) => DraftMetadata.fromJson(j as Map<String, dynamic>),
      );
  Future<DraftMetadata> save(
    int floor,
    String id,
    int expected,
    Map<String, dynamic> content,
  ) async => _parse(
    await _request(
      floor,
      'PUT',
      '/${draftGuid(id)}',
      json: {'expectedVersion': expected, 'content': content},
    ),
    (j) => DraftMetadata.fromJson(j as Map<String, dynamic>),
  );
  Future<Map<String, dynamic>> graph(int floor, String id, int version) async =>
      _parse(
        await _request(
          floor,
          'GET',
          '/${draftGuid(id)}/graph?version=${draftPositive(version)}',
        ),
        (j) {
          if (j['draftId'] != id ||
              j['floorId'] != floor ||
              j['version'] != version ||
              j['status'] != 'Draft') {
            throw const FormatException();
          }
          return j['content'] as Map<String, dynamic>;
        },
      );
  Future<List<DraftRevision>> revisions(
    int floor,
    String id, {
    int? beforeVersion,
  }) async => _parse(
    await _request(
      floor,
      'GET',
      '/${draftGuid(id)}/versions?take=50${beforeVersion == null ? '' : '&beforeVersion=${draftPositive(beforeVersion)}'}',
    ),
    (j) => (j as List)
        .map((e) => DraftRevision.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
  Future<DraftMetadata> restore(
    int floor,
    String id,
    int expected,
    int source,
  ) async => _parse(
    await _request(
      floor,
      'POST',
      '/${draftGuid(id)}/restore',
      json: {'expectedVersion': expected, 'sourceVersion': source},
    ),
    (j) => DraftMetadata.fromJson(j as Map<String, dynamic>),
  );
  Future<DraftImageMetadata> upload(
    int floor,
    Uint8List bytes,
    String mime,
  ) async => _parse(
    await _request(floor, 'POST', '/images', bytes: bytes, mime: mime),
    (j) {
      final image = DraftImageMetadata.fromJson(j as Map<String, dynamic>);
      if (image.floorId != floor) throw const FormatException();
      return image;
    },
  );
  Future<List<DraftImageMetadata>> images(int floor, {int page = 1}) async =>
      _parse(
        await _request(
          floor,
          'GET',
          '/images?page=${draftPositive(page)}&take=100',
        ),
        (j) => (j as List).map((e) {
          final image = DraftImageMetadata.fromJson(e as Map<String, dynamic>);
          if (image.floorId != floor) throw const FormatException();
          return image;
        }).toList(),
      );
  Future<(Uint8List, String)> download(int floor, String asset) async {
    final r = await _request(floor, 'GET', '/images/${draftGuid(asset)}');
    final mime = r.headers['content-type']?.split(';').first.trim();
    if (!['image/png', 'image/jpeg'].contains(mime) ||
        r.bodyBytes.isEmpty ||
        r.bodyBytes.length > 10 * 1024 * 1024) {
      throw const MapDraftApiException(
        'Phản hồi ảnh không hợp lệ.',
        code: 'invalid_response',
      );
    }
    return (r.bodyBytes, mime!);
  }
}
