import 'dart:math' as math;
import 'dart:ui';

import '../admin/local_map_project.dart';
import '../navigation/local_map_navigation.dart';
import '../../models/route_models.dart';

class TrackingMapKey {
  const TrackingMapKey(this.mapId, this.version);
  final String mapId;
  final int version;
  @override
  bool operator ==(Object other) =>
      other is TrackingMapKey &&
      mapId == other.mapId &&
      version == other.version;
  @override
  int get hashCode => Object.hash(mapId, version);
}

class TrackingFloor {
  const TrackingFloor(this.key, this.uiId, this.name, this.aspectRatio);
  final String key, name;
  final int uiId;
  final double? aspectRatio;
}

class TrackingNode {
  const TrackingNode(
    this.id,
    this.floorKey,
    this.uiId,
    this.name,
    this.point,
    this.type,
  );
  final String id, floorKey, name, type;
  final int uiId;
  final Offset point;
}

class TrackingEdge {
  const TrackingEdge({
    required this.id,
    required this.from,
    required this.to,
    required this.meters,
    required this.type,
    required this.active,
    required this.geometryEligible,
    this.bearing,
  });
  final String id, from, to, type;
  final double meters;
  final bool active, geometryEligible;
  final double? bearing;
}

/// Immutable copied snapshot. "geometryEligible" only means non-degenerate
/// endpoints; the user must still confirm straight geometry per edge/session.
class TrackingGraph {
  TrackingGraph._(
    this.key,
    this.localPilot,
    Map<String, TrackingFloor> floors,
    Map<String, TrackingNode> nodes,
    Map<String, TrackingEdge> edges,
  ) : floors = Map.unmodifiable(floors),
      nodes = Map.unmodifiable(nodes),
      edges = Map.unmodifiable(edges);
  final TrackingMapKey key;
  final bool localPilot;
  final Map<String, TrackingFloor> floors;
  final Map<String, TrackingNode> nodes;
  final Map<String, TrackingEdge> edges;

  static Future<TrackingGraph> fromNavigation(
    LocalMapNavigation map, {
    bool allowLocalPilot = false,
  }) async {
    final publication = map.publication;
    if (publication == null && !allowLocalPilot) {
      throw const FormatException(
        'Live cần snapshot Published hoặc local pilot rõ ràng.',
      );
    }
    final key = TrackingMapKey(
      publication?.mapId ?? 'local:${map.workspaceId}',
      publication?.version ?? 0,
    );
    final copy = await LocalMapProject.decode(map.trackingSnapshotBytes());
    if (map.publication != publication) {
      throw const FormatException('Snapshot thay đổi khi khởi tạo tracking.');
    }
    final floors = <String, TrackingFloor>{}, nodes = <String, TrackingNode>{};
    final edges = <String, TrackingEdge>{};
    for (final f in copy.floors) {
      final floorKey = f.localWorkspaceId!.toLowerCase();
      final image = f.image;
      final first = f.nodes.firstOrNull;
      final uiFloor = first == null
          ? null
          : map.routeIdentity(floorKey, f.nodeIds[first.code]!).floorId;
      if (uiFloor == null) continue;
      floors[floorKey] = TrackingFloor(
        floorKey,
        uiFloor,
        f.floor.name,
        image == null ? null : image.width / image.height,
      );
      for (final n in f.nodes) {
        final id = f.nodeIds[n.code]!.toLowerCase();
        final ui = map.routeIdentity(floorKey, id);
        if (nodes.containsKey(id) ||
            ui.floorId != uiFloor ||
            !n.x.isFinite ||
            !n.y.isFinite ||
            n.x < 0 ||
            n.x > 1 ||
            n.y < 0 ||
            n.y > 1) {
          throw const FormatException('Identity/tọa độ tracking không hợp lệ.');
        }
        nodes[id] = TrackingNode(
          id,
          floorKey,
          ui.nodeId,
          n.readableName,
          Offset(n.x, n.y),
          n.type,
        );
      }
    }
    void add(
      String id,
      String from,
      String to,
      double meters,
      String type,
      bool active,
    ) {
      id = id.toLowerCase();
      from = from.toLowerCase();
      to = to.toLowerCase();
      final a = nodes[from], b = nodes[to];
      if (edges.containsKey(id) ||
          a == null ||
          b == null ||
          !meters.isFinite ||
          meters <= 0) {
        throw const FormatException('Cạnh tracking không hợp lệ.');
      }
      final sameFloor = a.floorKey == b.floorKey;
      final aspect = floors[a.floorKey]?.aspectRatio;
      final delta = b.point - a.point;
      final eligible =
          sameFloor &&
          aspect != null &&
          delta.distance > 0.000001 &&
          (type == 'Corridor' || type == 'Door');
      edges[id] = TrackingEdge(
        id: id,
        from: from,
        to: to,
        meters: meters,
        type: type,
        active: active,
        geometryEligible: eligible,
        bearing: eligible ? math.atan2(delta.dy, delta.dx * aspect) : null,
      );
    }

    for (final f in copy.floors) {
      for (final e in f.edges) {
        add(
          f.edgeIds['${e.from}\u0000${e.to}']!,
          f.nodeIds[e.from]!,
          f.nodeIds[e.to]!,
          e.meters,
          e.type,
          e.isActive && e.isMeasured,
        );
      }
    }
    for (final link in copy.links) {
      add(
        link.id,
        link.fromNode,
        link.toNode,
        link.meters,
        link.type,
        link.active,
      );
    }
    return TrackingGraph._(key, publication == null, floors, nodes, edges);
  }

  List<TrackingEdge> outgoing(String nodeId) => List.unmodifiable(
    edges.values.where((e) => e.active && e.from == nodeId),
  );
  bool isTransition(TrackingEdge edge) =>
      nodes[edge.from]!.floorKey != nodes[edge.to]!.floorKey;
  TrackingEdge? edgeBetween(String from, String to) => edges.values
      .where((e) => e.from == from && e.to == to && e.active)
      .firstOrNull;
  String? floorKeyForUi(int id) =>
      floors.values.where((f) => f.uiId == id).firstOrNull?.key;

  Offset interpolate(String edgeId, double progressMeters) {
    final edge = edges[edgeId];
    if (edge == null ||
        !edge.geometryEligible ||
        !progressMeters.isFinite ||
        progressMeters < 0 ||
        progressMeters > edge.meters) {
      throw const FormatException('Không thể nội suy cạnh/tầng/tiến độ này.');
    }
    return Offset.lerp(
      nodes[edge.from]!.point,
      nodes[edge.to]!.point,
      progressMeters / edge.meters,
    )!;
  }

  List<String> routeNodes(LocalMapNavigation map, WayMarkRoute route) =>
      List.unmodifiable(
        route.nodes.map(
          (n) => map.stableIdentity(n.id, n.floor.id).nodeId.toLowerCase(),
        ),
      );
}
