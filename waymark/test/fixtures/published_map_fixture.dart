import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/admin/floor_plan_asset.dart';
import 'package:waymark/features/admin/local_map_project.dart';
import 'package:waymark/services/published_map_api_service.dart';

import 'multifloor_fixture.dart';

/// HTTP fixture only; backend authorization is tested separately with real signed JWTs.
class PublishedMapFixture {
  PublishedMapFixture(FloorPlanAsset image) {
    project = threeFloorProject();
    for (final f in project.floors) {
      f.places.clear();
      f.image = image;
      final old = f.nodes.singleWhere((n) => n.code == 'DOOR');
      f.putNode(
        DraftNode(
          old.code,
          'Clinic ${f.floor.floorCode}',
          old.x,
          old.y,
          old.type,
          displayName: 'Destination ${f.floor.floorCode}',
          searchableAsDestination: true,
          landmarkNote: 'Sign ${f.floor.floorCode}',
        ),
        replace: true,
      );
    }
    content = PublishedMapApiService.content(
      project,
      {
        for (final (i, f) in project.floors.indexed)
          f.localWorkspaceId!: i + 10,
      },
      {for (final f in project.floors) f.localWorkspaceId!: newDraftGuid()},
    );
    document = {
      'mapId': mapId,
      'version': 1,
      'name': 'Fixture map',
      'verifiedForPatientUse': false,
      'content': content,
      'publishedAt': '2026-10-23T00:00:00Z',
    };
    nextFloor = project.floors.first.localWorkspaceId!;
    nextNode = project.floors.first.nodeId('START');
    client = MockClient((r) async {
      calls.add(r);
      if (r.url.path.contains('/public/')) {
        if (r.headers.containsKey('Authorization')) {
          throw StateError('App JWT leaked to public reader');
        }
        if (offline) throw http.ClientException('fixture offline');
        if (r.url.path.contains('/qr/')) {
          if (status != 200) return http.Response('{}', status);
          return jsonResponse({
            'mapId': mapId,
            'version': resolvedVersion,
            'floorKey': nextFloor,
            'nodeId': nextNode,
            'mapName': 'Fixture map',
            'nodeName': 'Fixture start',
          });
        }
        if (r.url.path.contains('/images/')) {
          return http.Response.bytes(
            image.bytes,
            200,
            headers: {'content-type': image.mime},
          );
        }
        return jsonResponse(document);
      }
      lastPrivateBody = r.body.isEmpty ? null : jsonDecode(r.body);
      if (r.headers['Authorization'] != 'Bearer creator-fixture') {
        return http.Response('{}', 401);
      }
      return jsonResponse({
        'id': mapId,
        'version': 1,
        'name': 'Fixture map',
        'siteId': 1,
        'buildingId': 1,
        'updatedAt': '2026-10-23T00:00:00Z',
        'content': content,
      });
    });
    api = PublishedMapApiService(
      client: client,
      baseUrl: 'http://fixture.test/api',
    );
  }
  late final LocalMapProject project;
  late final Map<String, dynamic> content, document;
  late final MockClient client;
  late final PublishedMapApiService api;
  final String mapId = newDraftGuid();
  final token = List.filled(64, 'a').join();
  String get payload => 'WMQR1:$token';
  late String nextFloor, nextNode;
  int status = 200, resolvedVersion = 1;
  bool offline = false;
  Object? lastPrivateBody;
  final calls = <http.Request>[];
  static http.Response jsonResponse(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
