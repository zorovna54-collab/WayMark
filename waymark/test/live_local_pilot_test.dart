import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/indoor_tracking/pilot/local_pilot.dart';
import 'package:waymark/features/indoor_tracking/tracking_graph.dart';
import 'package:waymark/features/indoor_tracking/indoor_tracking_controller.dart';
import 'package:waymark/features/indoor_tracking/pdr_engine.dart';
import 'package:waymark/features/indoor_tracking/sensors/sensor_models.dart';

import 'support/fake_sensor_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Full-graph off-route branch remains an estimate until explicit anchor reroute', () async {
    final pilot = await createLocalLivePilot();
    final graph = await TrackingGraph.fromNavigation(
      pilot.map,
      allowLocalPilot: true,
    );
    final fake = FakeSensorProvider();
    final target = pilot.map.destinationNodes.first;
    var reroutes = 0;
    final controller = IndoorTrackingController(
      graph: graph,
      map: pilot.map,
      route: pilot.map.routeToNode(
        pilot.map.startChoices.first.key,
        target.nodeId,
        target.floorId,
      ),
      provider: fake,
      onConfirmedOffRoute: (anchor) async {
        reroutes++;
      },
    );
    final junction = graph.nodes.values.singleWhere(
      (n) => n.name.startsWith('J •'),
    );
    final north = graph.nodes.values.singleWhere(
      (n) => n.name.startsWith('N •'),
    );
    controller.manualAnchor(junction.id);
    controller.setStride(StrideCalibration(.5));
    await controller.startSensors();
    controller.confirmEdge(
      graph.edgeBetween(junction.id, north.id)!.id,
      straightGeometry: true,
      manualDirection: true,
    );
    fake.emit(SensorKind.stepDetector, timestamp: 1000);
    expect(controller.offRoute, true);
    expect(reroutes, 0);
    controller.manualAnchor(north.id);
    await Future<void>.delayed(Duration.zero);
    expect(reroutes, 1);
    await controller.close();
    controller.dispose();
  });
  test('Offline pilot is a local two-floor directed graph with no Published/QR claims', () async {
    final pilot = await createLocalLivePilot();
    expect(pilot.map.publication, isNull);
    expect(pilot.map.resolvePublishedQr, isNull);
    final graph = await TrackingGraph.fromNavigation(
      pilot.map,
      allowLocalPilot: true,
    );
    expect(graph.localPilot, true);
    expect(graph.floors.length, 2);
    final transitions = graph.edges.values.where(graph.isTransition).toList();
    expect(transitions.length, 2);
    expect(transitions.every((e) => !e.geometryEligible), true);
    for (final target in pilot.map.destinationNodes) {
      final route = pilot.map.routeToNode(
        pilot.map.startChoices.first.key,
        target.nodeId,
        target.floorId,
      );
      expect(route.edges, isNotEmpty);
      expect(route.totalDistanceMeters, greaterThan(0));
    }
    expect(pilot.map.imageFor(1), isNotNull);
    expect(pilot.map.imageFor(2), isNotNull);
  });
}
