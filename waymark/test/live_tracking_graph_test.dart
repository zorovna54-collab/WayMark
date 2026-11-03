import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/admin/local_map_project.dart';
import 'package:waymark/features/indoor_tracking/indoor_position.dart';
import 'package:waymark/features/indoor_tracking/tracking_graph.dart';
import 'package:waymark/features/navigation/local_map_navigation.dart';

import 'fixtures/multifloor_fixture.dart';
import 'floor_image_cleanup_test.dart' show cleanupTestImage;

Future<({LocalMapProject project, LocalMapNavigation map, TrackingGraph graph})>
trackingFixture() async {
  final p = threeFloorProject();
  for (final f in p.floors) {
    f.image = await cleanupTestImage();
  }
  final map = await LocalMapNavigation.fromProject(p);
  map.publication = (mapId: '11111111-1111-4111-8111-111111111111', version: 3);
  return (project: p, map: map, graph: await TrackingGraph.fromNavigation(map));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Coincident endpoints are not usable straight geometry despite positive stored meters', () async {
    final f = await trackingFixture();
    final floor = f.project.floors.first;
    final node = floor.nodes.singleWhere((n) => n.code == 'STAIR');
    floor.putNode(node.at(.1, .5), replace: true);
    final map = await LocalMapNavigation.fromProject(f.project);
    final graph = await TrackingGraph.fromNavigation(
      map,
      allowLocalPilot: true,
    );
    final edge = graph.edges[floor.edgeIds['START\u0000STAIR']]!;
    expect(edge.meters, greaterThan(0));
    expect(edge.geometryEligible, false);
    expect(() => graph.interpolate(edge.id, 1), throwsFormatException);
  });
  test('Snapshot adapter keeps stable directed edge/node/floor IDs and explicit UI mappings', () async {
    final f = await trackingFixture();
    final d = f.project.floors.first;
    final edge = f.graph.edges[d.edgeIds.values.first]!;
    expect(edge.from, d.nodeIds['START']);
    expect(edge.to, d.nodeIds['STAIR']);
    final n = f.graph.nodes[edge.from]!;
    expect(
      f.map.stableIdentity(n.uiId, f.graph.floors[n.floorKey]!.uiId).nodeId,
      n.id,
    );
    expect(f.graph.key.version, 3);
    expect(() => f.graph.edges.clear(), throwsUnsupportedError);
  });

  test(
    'Reordering floors/nodes/edges never changes stable identities',
    () async {
      final f = await trackingFixture();
      final json = jsonDecode(utf8.decode(f.project.encode())) as Map;
      json['floors'] = (json['floors'] as List).reversed.toList();
      for (final floor in json['floors'] as List) {
        floor['nodes'] = (floor['nodes'] as List).reversed.toList();
        floor['edges'] = (floor['edges'] as List).reversed.toList();
      }
      final p = await LocalMapProject.decode(
        Uint8List.fromList(utf8.encode(jsonEncode(json))),
      );
      final map = await LocalMapNavigation.fromProject(p)
        ..publication = f.map.publication;
      final graph = await TrackingGraph.fromNavigation(map);
      expect(graph.edges.keys.toSet(), f.graph.edges.keys.toSet());
      for (final e in graph.edges.values) {
        expect(e.from, f.graph.edges[e.id]!.from);
        expect(e.to, f.graph.edges[e.id]!.to);
        expect(e.meters, f.graph.edges[e.id]!.meters);
      }
    },
  );

  test('Builder mutation cannot change tracking snapshot', () async {
    final f = await trackingFixture();
    final first = f.graph.nodes.values.first;
    final original = f.project.floors.first.nodes.first;
    f.project.floors.first.putNode(original.at(.2, .3), replace: true);
    expect(f.graph.nodes[first.id]!.point, first.point);
  });

  test('Metric interpolation uses explicit meters, not pixel distance; bounded progress', () async {
    final f = await trackingFixture();
    final e = f.graph.edges.values.first;
    expect(f.graph.interpolate(e.id, 0), f.graph.nodes[e.from]!.point);
    expect(f.graph.interpolate(e.id, e.meters), f.graph.nodes[e.to]!.point);
    expect(f.graph.interpolate(e.id, e.meters / 2), const Offset(.3, .5));
    for (final progress in [-.1, e.meters + .1, double.nan]) {
      expect(() => f.graph.interpolate(e.id, progress), throwsFormatException);
    }
  });

  test('Reverse pairs retain different IDs; stair links cannot interpolate between floors', () async {
    final f = await trackingFixture();
    final d = f.project.floors.first;
    final a = f.graph.edgeBetween(d.nodeIds['STAIR']!, d.nodeIds['DOOR']!)!;
    final b = f.graph.edgeBetween(d.nodeIds['DOOR']!, d.nodeIds['STAIR']!)!;
    expect(a.id, isNot(b.id));
    final link = f.graph.edges.values.firstWhere(f.graph.isTransition);
    expect(link.geometryEligible, false);
    expect(() => f.graph.interpolate(link.id, 1), throwsFormatException);
  });

  test('Missing image frame cannot be assumed suitable geometry', () async {
    final p = threeFloorProject(),
        map = await LocalMapNavigation.fromProject(threeFloorProject());
    expect(p.floors.first.image, isNull);
    final graph = await TrackingGraph.fromNavigation(
      map,
      allowLocalPilot: true,
    );
    expect(graph.edges.values.every((e) => !e.geometryEligible), true);
    expect(graph.localPilot, true);
  });

  test(
    'Local mode requires explicit pilot flag and never becomes Published',
    () async {
      final map = await LocalMapNavigation.fromProject(threeFloorProject());
      await expectLater(
        TrackingGraph.fromNavigation(map),
        throwsFormatException,
      );
      expect(
        (await TrackingGraph.fromNavigation(
          map,
          allowLocalPilot: true,
        )).key.version,
        0,
      );
      expect(map.publication, isNull);
    },
  );

  test(
    'Anchor is a node, no fake edge; mismatch/missing node/floor fails closed',
    () async {
      final f = await trackingFixture(), node = f.graph.nodes.values.first;
      final anchor = VerifiedTrackingAnchor(
        f.graph.key,
        node.id,
        node.floorKey,
        PositionSource.qr,
      );
      final p = anchor.position(f.graph);
      expect(p.edgeId, isNull);
      expect(p.kind, PositionKind.nodeAnchor);
      expect(
        () => VerifiedTrackingAnchor(
          TrackingMapKey(f.graph.key.mapId, 4),
          node.id,
          node.floorKey,
          PositionSource.qr,
        ).position(f.graph),
        throwsFormatException,
      );
      expect(
        () => VerifiedTrackingAnchor(
          f.graph.key,
          node.id,
          'wrong-floor',
          PositionSource.qr,
        ).position(f.graph),
        throwsFormatException,
      );
    },
  );
}
