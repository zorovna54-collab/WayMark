import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/services/published_map_api_service.dart';

// Fixed IDs, geometry, pixels and ordering. No production/private map data.
String benchmarkGuid(int value) =>
    '10000000-0000-4000-8000-${value.toRadixString(16).padLeft(12, '0')}';

class PublishedBenchmarkFixture {
  PublishedBenchmarkFixture(
    this.floors,
    this.nodesPerFloor,
    this.image,
    this.document,
  ) {
    final encoded = utf8.encode(jsonEncode(document));
    snapshotBytes = Uint8List.fromList(encoded);
    api = PublishedMapApiService(
      baseUrl: 'https://benchmark.invalid/api',
      client: MockClient((r) async {
        if (r.method != 'GET' || r.headers.containsKey('Authorization')) {
          throw StateError('Benchmark is public read-only');
        }
        if (r.url.path.contains('/images/')) {
          imageRequests++;
          return http.Response.bytes(
            image,
            200,
            headers: {'content-type': 'image/png'},
          );
        }
        if (r.url.path.contains('/qr/')) {
          return http.Response(
            jsonEncode({
              'mapId': document['mapId'],
              'version': 1,
              'floorKey': benchmarkGuid(100),
              'nodeId': benchmarkGuid(10000),
            }),
            200,
          );
        }
        return http.Response.bytes(
          snapshotBytes,
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  }
  final int floors, nodesPerFloor;
  final Uint8List image;
  final Map<String, dynamic> document;
  late final Uint8List snapshotBytes;
  late final PublishedMapApiService api;
  int imageRequests = 0;
  int get expectedNodes => floors * nodesPerFloor;
  int get expectedEdges => floors * (nodesPerFloor - 1) * 2 + (floors - 1) * 2;
  String get payload => 'WMQR1:${List.filled(64, 'b').join()}';

  static Future<PublishedBenchmarkFixture> create(
    int floors,
    int perFloor, {
    int imageWidth = 512,
  }) async {
    if (floors < 1 || floors > 8 || perFloor < 4 || perFloor > 200) {
      throw ArgumentError('Fixed benchmark limits');
    }
    final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
    final height = imageWidth ~/ 2;
    for (var y = 0; y < height; y += 32) {
      for (var x = 0; x < imageWidth; x += 32) {
        final k = (x ~/ 32 * 17 + y ~/ 32 * 37) % 256;
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 32, 32),
          Paint()..color = Color.fromARGB(255, k, (k * 3) % 256, (k * 7) % 256),
        );
      }
    }
    final picture = recorder.endRecording(),
        rendered = await picture.toImage(imageWidth, height);
    final bytes = (await rendered.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    rendered.dispose();
    picture.dispose();
    String node(int f, int n) => benchmarkGuid(10000 + f * 1000 + n);
    final document = <String, dynamic>{
      'mapId': benchmarkGuid(1),
      'version': 1,
      'name': 'Synthetic published benchmark',
      'verifiedForPatientUse': false,
      'publishedAt': '2026-10-28T00:00:00Z',
      'content': {
        'id': benchmarkGuid(2),
        'floors': [
          for (var f = 0; f < floors; f++)
            {
              'id': benchmarkGuid(100 + f),
              'floorId': 10 + f,
              'name': 'Synthetic floor $f',
              'code': 'B$f',
              'content': {
                'schemaVersion': 1,
                'imageAssetId': benchmarkGuid(500 + f),
                'nodes': [
                  for (var n = 0; n < perFloor; n++)
                    {
                      'id': node(f, n),
                      'nodeCode': 'N$n',
                      'name': 'Point $n',
                      'x': .05 + .9 * n / (perFloor - 1),
                      'y': .5,
                      'nodeType': n == 0 || n == perFloor - 2
                          ? 'Stairs'
                          : 'Entrance',
                      'sourceNodeId': null,
                      'existingWayMarkCode': null,
                      'displayName': null,
                      'searchableAsDestination': n == perFloor - 1,
                      'landmarkNote': null,
                    },
                ],
                'edges': [
                  for (var n = 0; n + 1 < perFloor; n++)
                    for (final reverse in [false, true])
                      {
                        'id': benchmarkGuid(
                          100000 + f * 1000 + n * 2 + (reverse ? 1 : 0),
                        ),
                        'fromNodeId': node(f, reverse ? n + 1 : n),
                        'toNodeId': node(f, reverse ? n : n + 1),
                        'edgeType': 'Corridor',
                        'distanceMeters': 1.0,
                        'isActive': true,
                        'accessibility': 'Unknown',
                        'passageVerification': 'Unknown',
                      },
                ],
                'places': [],
                'transitions': [],
              },
            },
        ],
        'links': [
          for (var f = 0; f + 1 < floors; f++)
            for (final reverse in [false, true])
              {
                'id': benchmarkGuid(500000 + f * 2 + (reverse ? 1 : 0)),
                'fromFloor': benchmarkGuid(100 + (reverse ? f + 1 : f)),
                'fromNode': node(
                  reverse ? f + 1 : f,
                  reverse ? 0 : perFloor - 2,
                ),
                'toFloor': benchmarkGuid(100 + (reverse ? f : f + 1)),
                'toNode': node(reverse ? f : f + 1, reverse ? perFloor - 2 : 0),
                'distanceMeters': 3.0,
                'type': 'Stairs',
                'active': true,
                'accessibility': 'Unknown',
              },
        ],
      },
    };
    return PublishedBenchmarkFixture(floors, perFloor, bytes, document);
  }
}
