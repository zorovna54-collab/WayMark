import 'package:waymark/features/indoor_tracking/map_readiness.dart';
import 'package:waymark/features/indoor_tracking/tracking_graph.dart';
import 'package:waymark/services/published_map_api_service.dart';
import 'package:waymark/models/route_models.dart';

import '../floor_image_cleanup_test.dart' show cleanupTestImage;
import 'published_map_fixture.dart';

class PublishedLiveFixture {
  PublishedLiveFixture(this.http, this.session, this.graph, this.route) {
    input = MapReadinessInput.fromNavigation(session.map, route);
  }
  final PublishedMapFixture http;
  final PublishedMapSession session;
  final TrackingGraph graph;
  final WayMarkRoute route;
  late final MapReadinessInput input;
  static Future<PublishedLiveFixture> create() async {
    final http = PublishedMapFixture(await cleanupTestImage());
    final session = await http.api.loadQr(http.payload);
    final target = session.map.destinationNodes.first;
    final route = session.map.routeToNode(
      session.startKey,
      target.nodeId,
      target.floorId,
    );
    return PublishedLiveFixture(
      http,
      session,
      await TrackingGraph.fromNavigation(session.map),
      route,
    );
  }

  MapReadinessInput copy({
    TrackingMapKey? pin,
    TrackingMapKey? current,
    List<ReadinessFloor>? floors,
    List<ReadinessNode>? nodes,
    List<ReadinessEdge>? edges,
    List<String>? routeNodes,
    bool? routeOwned,
  }) => MapReadinessInput(
    pin: pin ?? input.pin,
    current: current ?? input.current,
    floors: floors ?? input.floors,
    nodes: nodes ?? input.nodes,
    edges: edges ?? input.edges,
    routeNodes: routeNodes ?? input.routeNodes,
    routeOwned: routeOwned ?? input.routeOwned,
  );
}

ReadinessEdge changeEdge(
  ReadinessEdge e, {
  String? id,
  String? type,
  double? meters,
  bool? active,
  String? from,
  String? to,
  String? fromFloor,
  String? toFloor,
}) => (
  id: id ?? e.id,
  fromFloor: fromFloor ?? e.fromFloor,
  from: from ?? e.from,
  toFloor: toFloor ?? e.toFloor,
  to: to ?? e.to,
  meters: meters ?? e.meters,
  type: type ?? e.type,
  active: active ?? e.active,
);
