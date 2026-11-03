import 'dart:math' as math;

import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/navigation/local_map_navigation.dart';
import 'package:waymark/features/indoor_tracking/indoor_tracking_controller.dart';
import 'package:waymark/features/indoor_tracking/pdr_engine.dart';
import 'package:waymark/features/indoor_tracking/pilot/local_pilot.dart';
import 'package:waymark/features/indoor_tracking/tracking_graph.dart';
import 'package:waymark/features/indoor_tracking/sensors/sensor_models.dart';

import 'fake_sensor_provider.dart';

// Test-only replay: never imported by lib/ or tool/.
class LiveTrackingReplay {
  LiveTrackingReplay(this.map, this.graph, this.fake) {
    controller = IndoorTrackingController(
      graph: graph,
      map: map,
      route: map.routeToNode(
        map.startChoices.first.key,
        node('E').uiId,
        graph.floors[node('E').floorKey]!.uiId,
      ),
      provider: fake,
      now: () => now,
    );
  }
  final LocalMapNavigation map;
  final TrackingGraph graph;
  final FakeSensorProvider fake;
  late final IndoorTrackingController controller;
  DateTime now = DateTime.utc(2026, 10, 28);
  int ns = 1000000000, sequence = 0;
  TrackingNode node(String code) =>
      graph.nodes.values.firstWhere((n) => n.name.split(' •').first == code);
  TrackingEdge edge(String from, String to) =>
      graph.edgeBetween(node(from).id, node(to).id)!;
  static Future<LiveTrackingReplay> create({
    bool ambiguous = false,
    FakeSensorProvider? fake,
  }) async {
    final pilot = await createLocalLivePilot();
    var map = pilot.map;
    if (ambiguous) {
      final g = pilot.project.floors.first;
      g.putNode(
        const DraftNode('K', 'K • nhánh cùng hướng', .8, .5, 'Junction'),
      );
      g.addEdge(const DraftEdge('J', 'K', 10, 'Corridor'));
      map = await LocalMapNavigation.fromProject(pilot.project);
    }
    final graph = await TrackingGraph.fromNavigation(
      map,
      allowLocalPilot: true,
    );
    return LiveTrackingReplay(map, graph, fake ?? FakeSensorProvider());
  }

  Future<void> begin({
    double stride = 1,
    bool manual = false,
    bool nextGeometry = true,
  }) async {
    final c = controller;
    c.manualAnchor(node('A').id);
    c.setStride(StrideCalibration(stride));
    await c.startSensors();
    orientation();
    if (nextGeometry) c.confirmGeometry(edge('J', 'E').id, true);
    c.confirmEdge(
      edge('A', 'J').id,
      straightGeometry: true,
      manualDirection: manual,
    );
  }

  void elapse(Duration duration) {
    now = now.add(duration);
    ns += duration.inMicroseconds * 1000;
  }

  void orientation([double yaw = 0]) {
    fake.emit(
      SensorKind.rotationVector,
      timestamp: ns,
      sequence: ++sequence,
      values: [0, 0, -math.sin(yaw / 2), math.cos(yaw / 2), -1],
    );
  }

  void step({bool withOrientation = true, double yaw = 0}) {
    elapse(const Duration(milliseconds: 100));
    if (withOrientation) orientation(yaw);
    fake.emit(
      SensorKind.stepDetector,
      timestamp: ns + 1000,
      sequence: ++sequence,
    );
  }

  void walk(int count, {bool withOrientation = true, double yaw = 0}) {
    for (var i = 0; i < count; i++) {
      step(withOrientation: withOrientation, yaw: yaw);
    }
  }

  Future<void> close() async {
    await controller.close();
    controller.dispose();
  }
}
