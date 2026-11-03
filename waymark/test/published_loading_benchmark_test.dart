import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/indoor_tracking/map_readiness.dart';
import 'package:waymark/features/indoor_tracking/tracking_graph.dart';

import 'fixtures/published_benchmark_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Synthetic benchmark fixture IDs/bytes/order are deterministic and load as valid Published data', () async {
    final a = await PublishedBenchmarkFixture.create(2, 8, imageWidth: 128),
        b = await PublishedBenchmarkFixture.create(2, 8, imageWidth: 128);
    expect(a.snapshotBytes, b.snapshotBytes);
    expect(a.image, b.image);
    final session = await a.api.loadQr(a.payload),
        graph = await TrackingGraph.fromNavigation(session.map);
    expect(graph.nodes.length, 16);
    expect(graph.edges.length, a.expectedEdges);
    expect(graph.key.mapId, benchmarkGuid(1));
    for (final n in graph.nodes.values) {
      final floor = graph.floors[n.floorKey]!;
      final mapped = session.map.routeIdentity(
        n.floorKey.toUpperCase(),
        n.id.toUpperCase(),
      );
      expect(mapped.nodeId, n.uiId);
      expect(
        session.map.stableIdentity(n.uiId, floor.uiId).nodeId.toLowerCase(),
        n.id,
      );
    }
    final first = graph.nodes.values.first;
    expect(
      () => session.map.stableIdentity(first.uiId, 999),
      throwsFormatException,
    );
    expect(
      () => session.map.stableStartKey(benchmarkGuid(999999), first.id),
      throwsFormatException,
    );
    final target = session.map.destinationNodes.last;
    final route = session.map.routeToNode(
      session.startKey,
      target.nodeId,
      target.floorId,
    );
    final input = MapReadinessInput.fromNavigation(session.map, route);
    final report = MapReadinessValidator.evaluate(
      input,
      graph: graph,
      requireGraph: true,
    );
    expect(report.canStartLive, true);
    final before = jsonEncode(a.document);
    await a.api.loadQr(a.payload);
    expect(
      a.imageRequests,
      4,
    ); // Fresh load has no persistent image-download cache.
    expect(jsonEncode(a.document), before);
    expect(a.snapshotBytes, jsonEncode(a.document).codeUnits);
  });
}
