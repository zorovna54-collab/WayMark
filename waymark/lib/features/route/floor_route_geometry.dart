import 'dart:ui';

import '../../models/route_models.dart';

/// Origin is the top left of the map content rectangle. No meter conversion.
Offset? normalizedMapPoint(double x, double y, Size size) {
  if (!x.isFinite ||
      !y.isFinite ||
      x < 0 ||
      x > 1 ||
      y < 0 ||
      y > 1 ||
      !size.width.isFinite ||
      !size.height.isFinite ||
      size.isEmpty) {
    return null;
  }
  return Offset(x * size.width, y * size.height);
}

class FloorVisit {
  const FloorVisit(this.floor, this.nodeIndices);
  final RouteFloor floor;
  final List<int> nodeIndices;
}

/// Consecutive visits, not a regrouping/sort of the route by floor.
List<FloorVisit> floorVisits(WayMarkRoute route) {
  final visits = <FloorVisit>[];
  for (var i = 0; i < route.nodes.length; i++) {
    final floor = route.nodes[i].floor;
    if (visits.isEmpty || visits.last.floor.id != floor.id) {
      visits.add(FloorVisit(floor, [i]));
    } else {
      visits.last.nodeIndices.add(i);
    }
  }
  return visits;
}

class MapRouteStop {
  const MapRouteStop(this.routeIndex, this.node, this.coordinate);
  final int routeIndex;
  final RouteNode node;
  final MapNode coordinate;
}

class MapRouteSegment {
  const MapRouteSegment(this.edge, this.from, this.to);
  final RouteEdge edge;
  final MapRouteStop from, to;
}

class MapFloorTransition {
  const MapFloorTransition(this.edge, this.at, this.otherFloor, this.departing);
  final RouteEdge edge;
  final MapRouteStop at;
  final RouteFloor otherFloor;
  final bool departing;
}

class FloorRouteGeometry {
  const FloorRouteGeometry(
    this.stops,
    this.segments,
    this.transitions,
    this.issues,
  );
  final List<MapRouteStop> stops;
  final List<MapRouteSegment> segments;
  final List<MapFloorTransition> transitions;
  final List<String> issues;

  factory FloorRouteGeometry.build(WayMarkRoute route, FloorMapData graph) {
    final coordinates = {for (final node in graph.nodes) node.id: node};
    final stops = <int, MapRouteStop>{};
    final segments = <MapRouteSegment>[];
    final transitions = <MapFloorTransition>[];
    final issues = <String>[];
    for (var i = 0; i < route.nodes.length; i++) {
      final node = route.nodes[i];
      if (node.floor.id != graph.floor.id) continue;
      final coordinate = coordinates[node.id];
      if (coordinate == null ||
          coordinate.floorId != graph.floor.id ||
          normalizedMapPoint(coordinate.x, coordinate.y, const Size(1, 1)) ==
              null) {
        issues.add(
          'Thiếu tọa độ hợp lệ cho node ${node.nodeCode} (bước ${i + 1}).',
        );
        continue;
      }
      stops[i] = MapRouteStop(i, node, coordinate);
    }
    for (var i = 0; i < route.edges.length; i++) {
      final edge = route.edges[i];
      // Keep the exact route order and direction, including return visits.
      if (i + 1 >= route.nodes.length ||
          edge.fromNodeId != route.nodes[i].id ||
          edge.toNodeId != route.nodes[i + 1].id ||
          edge.fromFloorId != route.nodes[i].floor.id ||
          edge.toFloorId != route.nodes[i + 1].floor.id) {
        issues.add(
          'Cạnh ${edge.sequence} không khớp thứ tự tuyến; không vẽ cạnh này.',
        );
        continue;
      }
      final from = stops[i];
      final to = stops[i + 1];
      if (edge.fromFloorId == edge.toFloorId) {
        if (from != null && to != null) {
          segments.add(MapRouteSegment(edge, from, to));
        }
      } else {
        if (from != null) {
          transitions.add(
            MapFloorTransition(edge, from, route.nodes[i + 1].floor, true),
          );
        }
        if (to != null) {
          transitions.add(
            MapFloorTransition(edge, to, route.nodes[i].floor, false),
          );
        }
      }
    }
    return FloorRouteGeometry(
      List.unmodifiable(stops.values),
      List.unmodifiable(segments),
      List.unmodifiable(transitions),
      List.unmodifiable(issues),
    );
  }
}
