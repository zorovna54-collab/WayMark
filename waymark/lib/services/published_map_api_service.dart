import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../features/admin/local_map_project.dart';
import '../features/admin/draft_server_session.dart';
import '../features/admin/floor_plan_asset.dart';
import '../features/navigation/local_map_navigation.dart';
import '../models/route_models.dart';
import 'auth_session.dart';
import 'map_draft_api_service.dart';
import 'waymark_api_service.dart';
import 'published_read_failure.dart';

/// Public payload contains only a server-generated, opaque locator, never an API URL/JWT.
String? publicQrToken(String raw) {
  final text = raw.trim();
  String? value;
  if (text.startsWith('WMQR1:')) value = text.substring(6);
  final uri = Uri.tryParse(text);
  if (uri != null &&
      ['http', 'https'].contains(uri.scheme) &&
      uri.pathSegments.length == 2 &&
      uri.pathSegments.first == 'q') {
    value = uri
        .pathSegments
        .last; // Never follow this URL/host or forward credentials to it.
  }
  return value != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(value)
      ? value
      : null;
}

class PublishedMapSession {
  PublishedMapSession(
    this.mapId,
    this.version,
    this.floorKey,
    this.nodeId,
    this.project,
    this.map,
    this.startKey,
  );
  final String mapId, floorKey, nodeId, startKey;
  final int version;
  final LocalMapProject project;
  final LocalMapNavigation map;
}

class PublishedMapApiService {
  PublishedMapApiService({
    this.client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 30),
  }) : baseUrl = (baseUrl ?? WayMarkApiService.baseUrl).replaceFirst(
         RegExp(r'/+$'),
         '',
       );
  final http.Client? client;
  final String baseUrl;
  final Duration timeout;

  Future<http.Response> request(
    String path, {
    String method = 'GET',
    Object? body,
    bool private = false,
    int maxBytes = 8 * 1024 * 1024,
  }) async {
    final token = AuthSession.accessToken;
    final revision = AuthSession.revision;
    if (private) AuthSession.checkWorkflow();
    if (private && (token == null || token.isEmpty || AuthSession.expired)) {
      throw const MapDraftApiException(
        'Cần đăng nhập để quản lý bản đồ server.',
        status: 401,
      );
    }
    final owned = client == null ? http.Client() : null;
    try {
      final req = http.Request(method, Uri.parse('$baseUrl/$path'))
        ..followRedirects = false;
      req.headers['Accept'] = 'application/json';
      if (private) req.headers['Authorization'] = 'Bearer $token';
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        if (bytes.length > 8 * 1024 * 1024) {
          throw const FormatException('Project vượt 8 MB (không gồm ảnh).');
        }
        req.headers['Content-Type'] = 'application/json';
        req.bodyBytes = bytes;
      }
      final response = await (() async {
        final stream = await (client ?? owned!).send(req);
        final bytes = <int>[];
        await for (final chunk in stream.stream) {
          if (bytes.length + chunk.length > maxBytes) {
            throw const FormatException('Phản hồi bản đồ quá lớn.');
          }
          bytes.addAll(chunk);
        }
        return http.Response.bytes(
          bytes,
          stream.statusCode,
          headers: stream.headers,
        );
      })().timeout(timeout);
      if (private && !AuthSession.isCurrent(token, revision)) {
        throw const MapDraftApiException(
          'Phiên đăng nhập đã thay đổi. Không áp dụng phản hồi cũ; đối chiếu lần lưu trước khi thử lại.',
          status: 401,
          code: 'auth_session_changed',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (private && response.statusCode == 401) {
          AuthSession.rejectUnauthorized(token, revision);
        }
        String? code;
        String? validation;
        try {
          code =
              (jsonDecode(utf8.decode(response.bodyBytes)) as Map)['code']
                  as String?;
          final title =
              (jsonDecode(utf8.decode(response.bodyBytes)) as Map)['title'];
          const reasons = {
            'Every published floor needs a retrievable floor image': 'Mỗi tầng cần ảnh đã upload và còn truy xuất được. Lưu draft kèm ảnh trước khi Publish.',
            'Image is not an available asset of this floor': 'Ảnh không thuộc đúng tầng hoặc không còn sẵn sàng. Tải lại/đối chiếu ảnh của tầng này.',
            'Create an active QR for a start node of this saved version before publishing': 'Chọn node khởi đầu và tạo QR của đúng phiên bản đã lưu trước khi Publish.',
            'No directed path from a QR start to a searchable destination': 'Không có tuyến có hướng từ QR đến Node đích. Kiểm tra hướng cạnh, cạnh active và liên kết tầng.',
            'At least one searchable destination is required':
                'Chưa có Node được đánh dấu làm điểm đến hoặc cửa Room hợp lệ.',
            'Published navigation needs at least one explicit graph edge':
                'Bản đồ chưa có cạnh nối rõ ràng để dẫn đường.',
            'Measure all edge distances in meters before publication':
                'Cần nhập khoảng cách mét cho tất cả cạnh trước khi Publish.',
            'QR must reference an existing stable node of this floor': 'Node QR không có trong bản đã lưu. Lưu graph trước rồi chọn lại Node QR.',
          };
          if (code == 'invalid_project' && title is String) {
            validation = reasons[title];
          }
        } catch (_) {
          /* No internal body is displayed. */
        }
        final message =
            validation ??
            switch (response.statusCode) {
              400 when code == 'invalid_onboarding' => 'Kiểm tra tên bản đồ, địa điểm, tên/mã tầng và mục đích sử dụng. Không nhập ký tự điều khiển.',
              409 when code == 'personal_map_quota' => 'Bạn đã có 10 workspace cá nhân. Hãy mở bản đồ hiện có trong Bản đồ của tôi.',
              409 when code == 'floor_quota' =>
                'Workspace đã đạt giới hạn 12 tầng.',
              409 when code == 'onboarding_conflict' => 'Yêu cầu tạo trước đã có kết quả. Mở Bản đồ của tôi để đối chiếu; không tự tạo lại bản trùng.',
              503 when code == 'workspace_storage_unavailable' => 'Backend chưa cấu hình Identity và Map dùng chung database cho workspace. Chưa xác nhận tạo bản đồ.',
              400 => 'Bản đồ/QR chưa hợp lệ: kiểm tra ảnh, điểm đến, khoảng cách, liên kết tầng và tuyến từ QR.',
              401 =>
                private
                    ? 'Phiên đăng nhập thiếu hoặc hết hạn. Bản local vẫn được giữ nguyên.'
                    : 'API công khai yêu cầu xác thực ngoài dự kiến. Visitor không cần đăng nhập; kiểm tra cấu hình server.',
              403 => 'Thiếu quyền với bản đồ, Site membership hoặc quyền xuất bản riêng cho Site này.',
              404 => 'Không tìm thấy QR hoặc phiên bản bản đồ đã xuất bản.',
              409 when code == 'map_not_published' =>
                'QR này chưa có bản đồ được xuất bản.',
              409 => 'Phiên bản server thay đổi hoặc bản đồ đã tồn tại. Tải lại; không tự ghi đè.',
              410 => 'QR đã bị thu hồi hoặc node không còn hợp lệ. Không cập nhật vị trí.',
              413 => 'Dữ liệu bản đồ vượt giới hạn dung lượng.',
              _ =>
                'API bản đồ chưa khả dụng (HTTP ${response.statusCode}). Giữ bản nháp/tuyến hiện tại.',
            };
        throw MapDraftApiException(
          message,
          status: response.statusCode,
          code: code,
        );
      }
      return response;
    } on TimeoutException {
      throw MapDraftApiException(
        !private && method == 'GET'
            ? 'Máy chủ phản hồi quá lâu. Chưa xác minh QR mới; tuyến hiện tại được giữ.'
            : 'API timeout. Bản local còn nguyên; kết quả ghi chưa xác định.',
        code: 'timeout',
      );
    } on http.ClientException {
      throw const MapDraftApiException(
        'Không kết nối được API bản đồ. Bản local/tuyến hiện tại còn nguyên.',
        code: 'network',
      );
    } finally {
      owned?.close();
    }
  }

  Future<dynamic> json(
    String path, {
    String method = 'GET',
    Object? body,
    bool private = false,
  }) async {
    final r = await request(path, method: method, body: body, private: private);
    try {
      return jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      throw const FormatException('Phản hồi bản đồ không đúng JSON.');
    }
  }

  Future<List<Map<String, dynamic>>> list() async =>
      (await json('admin/map-projects', private: true) as List)
          .cast<Map<String, dynamic>>();
  Future<Map<String, dynamic>> get(String id) async =>
      await json('admin/map-projects/${draftGuid(id)}', private: true)
          as Map<String, dynamic>;
  Future<Map<String, dynamic>> readiness(String id) async => await json(
    'admin/map-projects/${draftGuid(id)}/publish-readiness',
    private: true,
  ) as Map<String, dynamic>;
  Future<Map<String, dynamic>> startPersonal(Map<String, dynamic> form) async =>
      await json('me/map-workspaces', method: 'POST', body: form, private: true)
          as Map<String, dynamic>;
  Future<Map<String, dynamic>> addPersonalFloor(
    String mapId,
    String name,
    String code,
  ) async => await json(
    'me/map-workspaces/${draftGuid(mapId)}/floors',
    method: 'POST',
    body: {'name': name, 'code': code},
    private: true,
  ) as Map<String, dynamic>;
  Future<Map<String, dynamic>> save(
    String name,
    Map<String, dynamic> content, {
    String? id,
    int? version,
  }) async => await json(
    'admin/map-projects${id == null ? '' : '/${draftGuid(id)}'}',
    method: id == null ? 'POST' : 'PUT',
    private: true,
    body: {
      'name': name,
      'content': content,
      if (id != null) 'expectedVersion': version,
    },
  ) as Map<String, dynamic>;
  Future<Map<String, dynamic>> createQr(
    String id,
    int version,
    String floorKey,
    String nodeId,
  ) async => await json(
    'admin/map-projects/${draftGuid(id)}/qrs',
    method: 'POST',
    private: true,
    body: {
      'expectedVersion': version,
      'floorKey': draftGuid(floorKey),
      'nodeId': draftGuid(nodeId),
    },
  ) as Map<String, dynamic>;
  Future<List<Map<String, dynamic>>> qrs(String id) async => (await json(
    'admin/map-projects/${draftGuid(id)}/qrs',
    private: true,
  ) as List).cast<Map<String, dynamic>>();
  Future<void> revoke(String id, String qrId) async {
    await json(
      'admin/map-projects/${draftGuid(id)}/qrs/${draftGuid(qrId)}/revoke',
      method: 'POST',
      private: true,
    );
  }

  Future<void> publish(String id, int version) async {
    await json(
      'admin/map-projects/${draftGuid(id)}/publish',
      method: 'POST',
      private: true,
      body: {'expectedVersion': version, 'confirmPublic': true},
    );
  }

  static Map<String, dynamic> content(
    LocalMapProject p,
    Map<String, int> floors,
    Map<String, String> assets,
  ) {
    p.checkReferences();
    return {
      'id': p.id,
      'floors': [
        for (final f in p.floors)
          {
            'id': f.localWorkspaceId,
            'floorId':
                floors[f.localWorkspaceId] ??
                (throw const FormatException(
                  'Cần ghép mỗi tầng với một tầng server.',
                )),
            'name': f.floor.name,
            'code': f.floor.floorCode,
            'content': DraftServerMapper.content(f, assets[f.localWorkspaceId]),
          },
      ],
      'links': p.links.map((l) => l.toJson()).toList(),
    };
  }

  Future<LocalMapProject> project(
    Map<String, dynamic> document, {
    required bool public,
  }) async {
    final c = document['content'] as Map<String, dynamic>;
    final ownerToken = AuthSession.accessToken;
    final ownerRevision = AuthSession.revision;
    void checkOwner() {
      if (!public && !AuthSession.isCurrent(ownerToken, ownerRevision)) {
        throw const MapDraftApiException(
          'Phiên đã thay đổi. Không tải tiếp ảnh private bằng tài khoản mới.',
          status: 401,
          code: 'auth_session_changed',
        );
      }
    }

    final floors = <Map<String, dynamic>>[];
    for (final raw in c['floors'] as List) {
      final f = raw as Map<String, dynamic>;
      final fc = f['content'] as Map<String, dynamic>;
      final serverFloor = draftPositive(f['floorId']);
      final d = DraftServerMapper.fromContent(
        fc,
        siteId: document['siteId'] as int? ?? 1,
        buildingId: document['buildingId'] as int? ?? 1,
        floor: RouteFloor(
          id: serverFloor,
          buildingId: document['buildingId'] as int? ?? 1,
          name: f['name'] as String,
          floorCode: f['code'] as String,
          sortOrder: floors.length,
        ),
      );
      final asset = fc['imageAssetId'];
      if (asset != null) {
        final path = public
            ? 'public/maps/${draftGuid(document['mapId'])}/versions/${draftPositive(document['version'])}/images/${draftGuid(asset)}'
            : 'admin/floors/$serverFloor/map-drafts/images/${draftGuid(asset)}';
        try {
          checkOwner();
          final image = await request(
            path,
            private: !public,
            maxBytes: FloorPlanAsset.maxBytes,
          );
          final mime = image.headers['content-type']?.split(';').first ?? '';
          d.image = await FloorPlanAsset.validate(
            Uint8List.fromList(image.bodyBytes),
            mime == 'image/png' ? 'server.png' : 'server.jpg',
            mime,
          );
          checkOwner();
        } catch (error) {
          if (!public ||
              error is MapDraftApiException &&
                  ['network', 'timeout'].contains(error.code)) {
            rethrow;
          }
          throw const PublishedReadException(
            PublishedReadCode.imageUnavailable,
          );
        }
      }
      final j = d.toJson();
      j['localWorkspace'] = {
        'id': draftGuid(f['id']),
        'siteName': public ? 'Published map' : 'Server draft',
        'buildingName': document['name'] as String,
      };
      floors.add(j);
    }
    final project = await LocalMapProject.decode(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'version': 3,
            'kind': 'WayMarkLocalProject',
            'id': draftGuid(c['id']),
            'floors': floors,
            'links': c['links'],
          }),
        ),
      ),
    );
    checkOwner();
    return project;
  }

  Future<Map<String, dynamic>> resolve(String payload) async {
    if (publishedEndpoint(baseUrl) == null) {
      throw const PublishedReadException(PublishedReadCode.invalidEndpoint);
    }
    final token = publicQrToken(payload);
    if (token == null) {
      throw const PublishedReadException(PublishedReadCode.invalidQr);
    }
    try {
      return await json('public/qr/$token') as Map<String, dynamic>;
    } catch (error) {
      if (error is MapDraftApiException) rethrow;
      throw publishedReadFailure(error);
    }
  }

  Future<PublishedMapSession> loadQr(String payload) async {
    try {
      return await _loadQr(payload);
    } catch (error) {
      if (error is MapDraftApiException) rethrow;
      throw publishedReadFailure(error);
    }
  }

  Future<PublishedMapSession> _loadQr(String payload) async {
    final resolved = await resolve(payload);
    final id = draftGuid(resolved['mapId']),
        version = draftPositive(resolved['version']);
    final doc =
        await json('public/maps/$id/versions/$version') as Map<String, dynamic>;
    if (doc['mapId'] != id ||
        doc['version'] != version ||
        doc['verifiedForPatientUse'] != false) {
      throw PublishedReadException(
        doc['mapId'] != id
            ? PublishedReadCode.mapMismatch
            : doc['version'] != version
            ? PublishedReadCode.versionMismatch
            : PublishedReadCode.snapshotInvalid,
      );
    }
    final p = await project(doc, public: true);
    final map = await LocalMapNavigation.fromProject(p);
    final floor = draftGuid(resolved['floorKey']),
        node = draftGuid(resolved['nodeId']);
    String start;
    try {
      start = map.stableStartKey(floor, node);
    } on FormatException {
      throw const PublishedReadException(PublishedReadCode.anchorMissing);
    }
    map.bindPublishedOrigin(id, version);
    map.publicationQrPayload = payload;
    map.personalPublication =
        ((doc['content'] as Map)['info'] as Map?)?['kind'] == 'PersonalDemo';
    map.resolvePublishedQr = (payload) async {
      final r = await resolve(payload);
      if (r['mapId'] != id || r['version'] != version) {
        throw PublishedReadException(
          r['mapId'] != id
              ? PublishedReadCode.mapMismatch
              : PublishedReadCode.versionMismatch,
        );
      }
      try {
        return map.stableLocation(
          draftGuid(r['floorKey']),
          draftGuid(r['nodeId']),
          payload,
        );
      } catch (_) {
        throw const PublishedReadException(PublishedReadCode.anchorMissing);
      }
    };
    return PublishedMapSession(id, version, floor, node, p, map, start);
  }
}
