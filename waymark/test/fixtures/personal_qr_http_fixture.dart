import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/admin/floor_plan_asset.dart';
import 'package:waymark/features/admin/local_map_project.dart';
import 'package:waymark/services/published_map_api_service.dart';

/// Real HTTP/JSON client boundary, not an override returning a prefilled saved graph.
/// In-memory server simulation only. Backend/SQL authorization is tested separately.
class PersonalQrHttpFixture {
  PersonalQrHttpFixture(this.image) {
    final f = DraftMap.local('Personal test', 'Building', 'Floor G', 'G')
      ..image = image;
    f.putNode(
      const DraftNode('QR-JUNCTION', 'Start junction', .1, .5, 'Junction'),
    );
    f.putNode(const DraftNode('MID', 'Corridor', .5, .5, 'Junction'));
    f.putNode(
      const DraftNode(
        'DEST',
        'Clinic destination',
        .9,
        .5,
        'Destination',
        searchableAsDestination: true,
      ),
    );
    f.addEdge(const DraftEdge('QR-JUNCTION', 'MID', 5, 'Corridor'));
    f.addEdge(const DraftEdge('MID', 'DEST', 7, 'Corridor'));
    project = LocalMapProject(f);
    document = {
      'id': mapId,
      'name': 'Personal test',
      'siteId': 1,
      'buildingId': 1,
      'version': 1,
      'canPublish': true,
      'publicationKind': 'PersonalDemo',
      'content': {
        'id': project.id,
        'info': {
          'purpose': 'PersonalDemo',
          'placeName': 'Test',
          'description': null,
          'kind': 'PersonalDemo',
        },
        'floors': [
          {
            'id': f.localWorkspaceId,
            'floorId': 10,
            'name': f.floor.name,
            'code': 'G',
            'content': {
              'schemaVersion': 1,
              'imageAssetId': null,
              'nodes': [],
              'edges': [],
              'places': [],
              'transitions': [],
            },
          },
        ],
        'links': [],
      },
    };
    client = MockClient(handle);
    api = PublishedMapApiService(client: client);
  }
  final FloorPlanAsset image;
  final mapId = newDraftGuid(),
      imageId = newDraftGuid(),
      headId = newDraftGuid();
  final payload = 'WMQR1:${List.filled(64, 'b').join()}';
  late final LocalMapProject project;
  late final MockClient client;
  late final PublishedMapApiService api;
  late Map<String, dynamic> document;
  Map<String, dynamic>? publication, qr;
  bool headExists = false, failUpload = false, storageConfigured = true;
  int uploads = 0, saves = 0, gets = 0, readinessGets = 0;
  final calls = <http.Request>[];
  Map<String, dynamic> copyDocument() =>
      jsonDecode(jsonEncode(document)) as Map<String, dynamic>;
  Map<String, dynamic> get content =>
      Map<String, dynamic>.from(document['content'] as Map);
  List get savedNodes => content['floors'][0]['content']['nodes'] as List;
  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
  Map<String, dynamic> get metadata => {
    'id': headId,
    'siteId': 1,
    'buildingId': 1,
    'floorId': 10,
    'version': 1,
    'status': 'Draft',
    'updatedAt': '2026-10-25T00:00:00Z',
  };
  Future<http.Response> handle(http.Request r) async {
    calls.add(r);
    final p = r.url.path;
    if (p.contains('/public/')) {
      if (r.headers.containsKey('Authorization')) {
        throw StateError('JWT sent to public endpoint');
      }
      if (p.contains('/qr/')) {
        if (qr == null || qr!['publishedVersion'] == null) {
          return json({'code': 'map_not_published'}, 409);
        }
        if (qr!['isActive'] != true) return json({'code': 'qr_revoked'}, 410);
        return json({
          'mapId': mapId,
          'version': qr!['publishedVersion'],
          'floorKey': qr!['floorKey'],
          'nodeId': qr!['nodeId'],
          'mapName': 'Personal test',
          'nodeName': 'Start junction',
        });
      }
      if (p.contains('/images/')) {
        return http.Response.bytes(
          image.bytes,
          200,
          headers: {'content-type': image.mime},
        );
      }
      return publication == null ? json({}, 404) : json(publication!);
    }
    if (r.headers['Authorization'] != 'Bearer personal-test-user') {
      return json({}, 401);
    }
    if (p.endsWith('/sites')) {
      return json([
        {'id': 1, 'name': 'Personal test'},
      ]);
    }
    if (p.endsWith('/floors')) {
      return json([
        {'id': 10, 'name': 'Floor G', 'buildingId': 1},
      ]);
    }
    if (p.endsWith('/map-projects')) {
      return json([
        {'id': mapId, 'name': 'Personal test', 'version': document['version']},
      ]);
    }
    if (p.endsWith('/publish-readiness')) {
      readinessGets++;
      return json({
        'mapId': mapId,
        'version': document['version'],
        'savedNodes': savedNodes.length,
        'checks': [
          {
            'code': storageConfigured
                ? 'image_storage_configuration'
                : 'image_storage_unavailable',
            'passed': storageConfigured,
            'message': storageConfigured ? 'Cấu hình kho ảnh hợp lệ.' : 'Backend chưa bật kho ảnh. Chưa thể lưu ảnh/graph để Publish.',
          },
          {
            'code': 'saved_nodes',
            'passed': savedNodes.isNotEmpty,
            'message': savedNodes.isEmpty
                ? 'Chưa có Node được lưu trên Server.'
                : 'Đã lưu 3 node.',
          },
          {
            'code': 'qr_start',
            'passed': qr != null && qr!['draftVersion'] == document['version'],
            'message': qr != null && qr!['draftVersion'] == document['version']
                ? 'Có QR active đúng phiên bản đã lưu.'
                : 'Tạo QR cho ít nhất một node xuất phát của phiên bản đã lưu trước khi xuất bản.',
          },
        ],
      });
    }
    if (p.endsWith('/map-drafts')) {
      if (r.method == 'POST') {
        headExists = true;
        return json(metadata, 201);
      }
      return headExists
          ? json(metadata)
          : json({'code': 'draft_resource_not_found'}, 404);
    }
    if (p.endsWith('/images') && r.method == 'POST') {
      uploads++;
      if (failUpload) return json({'code': 'image_storage_unavailable'}, 503);
      return json({
        'id': imageId,
        'floorId': 10,
        'mimeType': image.mime,
        'width': image.width,
        'height': image.height,
        'byteLength': image.bytes.length,
        'sha256': List.filled(64, 'a').join(),
      }, 201);
    }
    if (p.endsWith('/qrs')) {
      if (r.method == 'POST') {
        final b = jsonDecode(r.body) as Map;
        if (b['expectedVersion'] != document['version'] ||
            !savedNodes.any((n) => n['id'] == b['nodeId']) ||
            b['floorKey'] != content['floors'][0]['id']) {
          return json({}, 409);
        }
        qr = {
          'id': newDraftGuid(),
          'mapId': mapId,
          'nodeId': b['nodeId'],
          'floorKey': b['floorKey'],
          'draftVersion': document['version'],
          'publishedVersion': null,
          'isActive': true,
          'payload': payload,
        };
        return json(qr!, 201);
      }
      return json(qr == null ? [] : [qr!]);
    }
    if (p.endsWith('/publish')) {
      if (qr == null || savedNodes.length != 3) {
        return json({'code': 'invalid_project'}, 400);
      }
      publication = {
        'mapId': mapId,
        'version': document['version'],
        'name': document['name'],
        'content': jsonDecode(jsonEncode(content)),
        'verifiedForPatientUse': false,
        'publishedAt': '2026-10-25T00:00:00Z',
      };
      qr!['publishedVersion'] = document['version'];
      return json(publication!);
    }
    if (p.endsWith('/$mapId')) {
      if (r.method == 'PUT') {
        saves++;
        final b = jsonDecode(r.body) as Map;
        if (b['expectedVersion'] != document['version']) {
          return json({'code': 'project_version_conflict'}, 409);
        }
        document = {
          ...document,
          'version': (document['version'] as int) + 1,
          'name': b['name'],
          'content': {...b['content'] as Map, 'info': content['info']},
        };
      } else {
        gets++;
      }
      return json(document);
    }
    return json({}, 404);
  }
}
