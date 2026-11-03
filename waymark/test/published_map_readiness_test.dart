import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/indoor_tracking/map_readiness.dart';
import 'package:waymark/features/indoor_tracking/tracking_graph.dart';
import 'package:waymark/features/admin/draft_map.dart';

import 'fixtures/published_live_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PublishedLiveFixture f;
  setUp(() async {
    f = await PublishedLiveFixture.create();
  });
  MapReadinessReport check(MapReadinessInput i) =>
      MapReadinessValidator.evaluate(i);
  bool has(MapReadinessReport r, String code) =>
      r.issues.any((i) => i.reasonCode == code);

  test('Valid Published snapshot, stable mapping and images are eligible, never surveyed automatically', () {
    final before = base64Encode(f.session.map.trackingSnapshotBytes());
    final r = MapReadinessValidator.evaluate(
      f.input,
      graph: f.graph,
      requireGraph: true,
    );
    expect(r.canStartLive, true);
    expect(r.readyByData, true);
    expect(r.level, MapReadinessLevel.warning);
    expect(
      r.edges
          .where((e) => e.eligibleByData)
          .every((e) => !e.physicallySurveyed),
      true,
    );
    expect(has(r, 'physicalSurveyRequired'), true);
    expect(r.input.pin!.mapId, f.session.mapId);
    expect(base64Encode(f.session.map.trackingSnapshotBytes()), before);
    expect(() => r.input.edges.clear(), throwsUnsupportedError);
  });
  test('Explicit survey is session evidence only and cannot make unsupported geometry eligible', () {
    final i = f.input,
        link = i.edges.firstWhere((e) => e.fromFloor != e.toFloor);
    final r = MapReadinessValidator.evaluate(
      i,
      surveyed: i.edges.map((e) => e.id).toSet(),
    );
    expect(
      r.edges.where((e) => e.eligibleByData).every((e) => e.physicallySurveyed),
      true,
    );
    expect(
      r.edges.singleWhere((e) => e.edge.id == link.id).physicallySurveyed,
      false,
    );
  });
  test('Missing floor blocks inconsistent endpoints', () {
    final r = check(f.copy(floors: f.input.floors.skip(1).toList()));
    expect(has(r, 'nodeFloorMissing'), true);
    expect(has(r, 'edgeEndpointMissing'), true);
    expect(r.canStartLive, false);
  });
  test(
    'Missing image on route gives a clear reason and does not claim ready',
    () {
      final floors = [
        for (final g in f.input.floors)
          (
            id: g.id,
            name: g.name,
            imageReady: false,
            aspect: null,
            uiId: g.uiId,
          ),
      ];
      final r = check(f.copy(floors: floors));
      expect(has(r, 'floorImageMissing'), true);
      expect(r.eligibleRouteEdges, 0);
      expect(r.canStartLive, false);
    },
  );
  for (final meters in [0.0, -1.0, double.nan, double.infinity]) {
    test('Invalid edge distance $meters is blocked without repair', () {
      final original = f.input.edges.first;
      final r = check(
        f.copy(
          edges: [
            changeEdge(original, meters: meters),
            ...f.input.edges.skip(1),
          ],
        ),
      );
      expect(has(r, 'edgeDistance'), true);
      expect(r.canStartLive, false);
      expect(f.input.edges.first.meters, original.meters);
    });
  }
  for (final target in ['floor', 'node', 'edge']) {
    test('Duplicate $target identity is blocked before map conversion', () {
      final r = check(
        f.copy(
          floors: target == 'floor'
              ? [...f.input.floors, f.input.floors.first]
              : null,
          nodes: target == 'node'
              ? [...f.input.nodes, f.input.nodes.first]
              : null,
          edges: target == 'edge'
              ? [...f.input.edges, f.input.edges.first]
              : null,
        ),
      );
      expect(r.canStartLive, false);
      expect(has(r, '${target}Identity'), true);
    });
  }
  test('Invalid map/version and changing current pin block readiness', () {
    expect(
      check(f.copy(pin: const TrackingMapKey('not-a-guid', 0))).canStartLive,
      false,
    );
    final r = check(
      f.copy(
        current: TrackingMapKey(f.input.pin!.mapId, f.input.pin!.version + 1),
      ),
    );
    expect(has(r, 'mapVersionMismatch'), true);
    expect(r.canStartLive, false);
  });
  test('Node GUID, normalized coordinates, absent endpoint and direction are validated', () {
    final n = f.input.nodes.first;
    final badNode = (
      id: n.id,
      floor: n.floor,
      name: n.name,
      point: const Offset(1.2, 0),
      uiId: n.uiId,
    );
    expect(
      has(
        check(f.copy(nodes: [badNode, ...f.input.nodes.skip(1)])),
        'nodeCoordinates',
      ),
      true,
    );
    final e = f.input.edges.first;
    expect(
      has(
        check(
          f.copy(
            edges: [
              changeEdge(e, to: newDraftGuid()),
              ...f.input.edges.skip(1),
            ],
          ),
        ),
        'edgeEndpointMissing',
      ),
      true,
    );
    expect(
      has(
        check(
          f.copy(
            edges: [
              changeEdge(e, id: 'not-guid'),
              ...f.input.edges.skip(1),
            ],
          ),
        ),
        'edgeIdentity',
      ),
      true,
    );
  });
  test(
    'Reverse directed edge retains a distinct stable GUID and is not duplicate',
    () {
      final e = f.input.edges.first;
      final reverse = changeEdge(
        e,
        id: newDraftGuid(),
        from: e.to,
        to: e.from,
        fromFloor: e.toFloor,
        toFloor: e.fromFloor,
      );
      final r = check(f.copy(edges: [...f.input.edges, reverse]));
      expect(has(r, 'duplicateDirection'), false);
      expect(has(r, 'edgeIdentity'), false);
      expect(r.edges.last.edge.id, isNot(e.id));
      expect(r.canStartLive, true);
    },
  );
  test('Route cannot traverse inactive edge or invent an implicit reverse', () {
    final first = f.input.routeNodes.first, second = f.input.routeNodes[1];
    final r = check(
      f.copy(
        edges: f.input.edges
            .map(
              (e) => e.from == first && e.to == second
                  ? changeEdge(e, active: false)
                  : e,
            )
            .toList(),
      ),
    );
    expect(has(r, 'routeDisconnected'), true);
    expect(r.canStartLive, false);
    expect(
      has(check(f.copy(routeNodes: [second, first])), 'routeDisconnected'),
      true,
    );
  });
  test(
    'Disconnected extra component warns without pretending full coverage',
    () {
      final n = f.input.nodes.first;
      final r = check(
        f.copy(
          nodes: [
            ...f.input.nodes,
            (
              id: newDraftGuid(),
              floor: n.floor,
              name: 'Detached test node',
              point: const Offset(.8, .8),
              uiId: 999,
            ),
          ],
        ),
      );
      expect(has(r, 'disconnectedGraph'), true);
      expect(r.canStartLive, true);
    },
  );
  test(
    'Cross-floor link requires confirmation, never horizontal interpolation',
    () {
      final r = check(f.input),
          links = r.edges.where((e) => e.edge.fromFloor != e.edge.toFloor);
      expect(links, isNotEmpty);
      expect(
        links.every(
          (e) => !e.eligibleByData && e.reasonCode == 'floorTransition',
        ),
        true,
      );
      final l = links.first.edge;
      expect(
        has(
          check(
            f.copy(
              edges: f.input.edges
                  .map(
                    (e) => e.id == l.id ? changeEdge(e, type: 'Corridor') : e,
                  )
                  .toList(),
            ),
          ),
          'transitionType',
        ),
        true,
      );
    },
  );
  test(
    'Partially supported route reports supported segments and manual segments',
    () {
      final e = f.input.edges.firstWhere(
        (e) =>
            e.from == f.input.routeNodes.first && e.to == f.input.routeNodes[1],
      );
      final r = check(
        f.copy(
          edges: f.input.edges
              .map((x) => x.id == e.id ? changeEdge(x, type: 'Ramp') : x)
              .toList(),
        ),
      );
      expect(r.canStartLive, true);
      expect(r.readyByData, false);
      expect(r.eligibleRouteEdges, lessThan(r.routeEdges));
      expect(has(r, 'unsupportedEdgeType'), true);
    },
  );
  test('Graph/snapshot coordinate and UI identity mismatch and missing graph are blocked', () {
    final n = f.input.nodes.first;
    final changed = (
      id: n.id,
      floor: n.floor,
      name: n.name,
      point: n.point,
      uiId: 999,
    );
    final r = MapReadinessValidator.evaluate(
      f.copy(nodes: [changed, ...f.input.nodes.skip(1)]),
      graph: f.graph,
      requireGraph: true,
    );
    expect(has(r, 'snapshotGraphMismatch'), true);
    expect(r.canStartLive, false);
    expect(
      MapReadinessValidator.evaluate(f.input, requireGraph: true).canStartLive,
      false,
    );
  });
  test('Invalid start or foreign route never starts tracking', () {
    expect(check(f.copy(routeOwned: false)).canStartLive, false);
    expect(check(f.copy(routeNodes: [newDraftGuid()])).canStartLive, false);
  });
}
