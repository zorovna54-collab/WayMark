import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/models/route_models.dart';

import 'routing_fixture.dart';

const draftId = '11111111-1111-4111-8111-111111111111';
const imageId = '22222222-2222-4222-8222-222222222222';
const entranceId = '33333333-3333-4333-8333-333333333333';
const liftId = '44444444-4444-4444-8444-444444444444';
const edgeId = '55555555-5555-4555-8555-555555555555';
const placeId = '66666666-6666-4666-8666-666666666666';

RouteFloor draftFloor([int id = 1]) =>
    RouteFloor.fromJson(floorGraphJson(id)['floor']);
DraftMap localDraft() {
  final d = DraftMap(siteId: 1, buildingId: 1, floor: draftFloor());
  d.putNode(const DraftNode('DOOR', 'Door', .1, .2, 'Entrance'));
  d.putNode(const DraftNode('LIFT', 'Lift', .7, .8, 'Elevator'));
  d.nodeIds.addAll({'DOOR': entranceId, 'LIFT': liftId});
  d.addEdge(const DraftEdge('DOOR', 'LIFT', 12.125, 'Corridor'));
  d.edgeIds['DOOR\u0000LIFT'] = edgeId;
  d.places.add({
    'id': placeId,
    'placeCode': 'EXAM',
    'name': 'Exam room',
    'label': {'x': .4, 'y': .3},
    'polygon': [],
    'entranceNodeIds': [entranceId],
    'accessibility': 'Unknown',
  });
  d.transitions.add({
    'id': '77777777-7777-4777-8777-777777777777',
    'fromNodeId': liftId,
    'targetDraftId': '88888888-8888-4888-8888-888888888888',
    'targetVersion': 3,
    'targetNodeId': '99999999-9999-4999-8999-999999999999',
    'edgeType': 'Elevator',
    'distanceMeters': null,
    'accessibility': 'Unknown',
    'passageVerification': 'Unknown',
  });
  return d;
}

Map<String, dynamic> draftMetadata([int version = 1, int floor = 1]) => {
  'id': draftId,
  'siteId': 1,
  'buildingId': 1,
  'floorId': floor,
  'version': version,
  'status': 'Draft',
  'createdAt': '2026-10-20T01:00:00Z',
  'updatedAt': '2026-10-20T02:00:00Z',
  'createdBy': 'test-operator',
  'updatedBy': 'test-operator',
};
http.Response jsonResponse(Object j, [int status = 200]) => http.Response(
  jsonEncode(j),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// In-memory HTTP fixture. No SQL Server, file storage or real authorization.
class DraftHttpFixture {
  Map<String, dynamic>? content;
  int version = 0, uploads = 0, saves = 0, restores = 0;
  String? failureCode;
  int failureStatus = 503;
  bool failUpload = false, failDownload = false;
  Uint8List? image;
  final requests = <http.Request>[];
  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    if (!r.url.path.contains('/admin/floors/1/map-drafts')) {
      throw StateError('No production writes/route requests in draft workflow');
    }
    if (r.url.path.endsWith('/images') && r.method == 'GET') {
      return jsonResponse(image == null ? [] : [imageMetadata]);
    }
    if (r.url.path.endsWith('/images') && r.method == 'POST') {
      uploads++;
      image = r.bodyBytes;
      if (failUpload) {
        // Asset was already allocated above: this simulates an ambiguous
        // metadata response, not the managed provider's pre-write disabled guard.
        return jsonResponse({'code': 'draft_storage_unavailable'}, 503);
      }
      return jsonResponse(imageMetadata, 201);
    }
    if (r.url.path.endsWith('/images/$imageId')) {
      if (failDownload) {
        return jsonResponse({'code': 'image_integrity_failure'}, 503);
      }
      return http.Response.bytes(
        image!,
        200,
        headers: {'content-type': 'image/png'},
      );
    }
    if (r.url.path.endsWith('/graph')) {
      return jsonResponse({
        'draftId': draftId,
        'floorId': 1,
        'version': version,
        'status': 'Draft',
        'content': content,
      });
    }
    if (r.url.path.endsWith('/versions')) {
      return jsonResponse([
        for (var i = version; i > 0; i--)
          {
            'version': i,
            'createdAt': '2026-10-20T02:00:00Z',
            'createdBy': 'test-operator',
          },
      ]);
    }
    if (r.url.path.endsWith('/restore')) {
      restores++;
      final j = jsonDecode(r.body) as Map;
      if (j['expectedVersion'] != version) {
        return jsonResponse({'code': 'draft_version_conflict'}, 409);
      }
      version++;
      return jsonResponse(draftMetadata(version));
    }
    if (r.method == 'GET') {
      if (version == 0) {
        return jsonResponse({'code': 'draft_resource_not_found'}, 404);
      }
      return jsonResponse(draftMetadata(version));
    }
    if (r.method == 'POST') {
      if (version != 0) {
        return jsonResponse({'code': 'draft_version_conflict'}, 409);
      }
      content = jsonDecode(r.body) as Map<String, dynamic>;
      version = 1;
      return jsonResponse(draftMetadata(), 201);
    }
    if (r.method == 'PUT') {
      saves++;
      if (failureCode != null) {
        return jsonResponse({'code': failureCode}, failureStatus);
      }
      final j = jsonDecode(r.body) as Map;
      if (j['expectedVersion'] != version) {
        return jsonResponse({'code': 'draft_version_conflict'}, 409);
      }
      content = j['content'] as Map<String, dynamic>;
      version++;
      return jsonResponse(draftMetadata(version));
    }
    throw StateError('Unexpected request');
  }

  Map<String, dynamic> get imageMetadata => {
    'id': imageId,
    'floorId': 1,
    'mimeType': 'image/png',
    'width': 2,
    'height': 1,
    'byteLength': image!.length,
    'sha256': List.filled(64, 'a').join(),
  };
}
