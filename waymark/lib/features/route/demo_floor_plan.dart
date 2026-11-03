import 'dart:convert';

import 'package:flutter/services.dart';

import '../../models/route_models.dart';

/// An explicitly synthetic, versioned schematic. Never a published draft or a
/// fallback route. API IDs are resolved by codes, not assumed from seed identity.
class DemoHospitalMap {
  DemoHospitalMap._(this.data);
  final Map<String, dynamic> data;
  static DemoHospitalMap? _loaded;
  static Future<DemoHospitalMap> load() async {
    if (_loaded != null) return _loaded!;
    final text = await rootBundle.loadString(
      'assets/demo_maps/hospital_2a.json',
    );
    return _loaded = fromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  static DemoHospitalMap fromJson(Map<String, dynamic> data) {
    if (data['version'] != 1) throw const FormatException('Unknown demo map.');
    return DemoHospitalMap._(data);
  }

  List<Map<String, dynamic>> get floors =>
      (data['floors'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get segments =>
      (data['segments'] as List).cast<Map<String, dynamic>>();
  List<DemoRoom> get rooms => (data['rooms'] as List)
      .map((room) => DemoRoom(room as Map<String, dynamic>))
      .toList();
  Map<String, dynamic>? node(String code) {
    for (final floor in floors) {
      for (final item
          in (floor['nodes'] as List).cast<Map<String, dynamic>>()) {
        if (item['code'] == code) return item;
      }
    }
    return null;
  }

  bool _edgeMatches(String from, String to, String type, double distance) =>
      segments.any(
        (edge) =>
            ((edge['from'] == from && edge['to'] == to) ||
                (edge['from'] == to && edge['to'] == from)) &&
            edge['type'] == type &&
            ((edge['meters'] as num).toDouble() - distance).abs() < 0.000001,
      );

  DemoFloorPlan? match(FloorMapData graph, {WayMarkRoute? route}) {
    final candidates = floors.where(
      (floor) => floor['code'] == graph.floor.floorCode,
    );
    if (candidates.length != 1 || graph.floor.id <= 0) return null;
    final floor = candidates.single;
    final expected = (floor['nodes'] as List).cast<Map<String, dynamic>>();
    if (graph.nodes.length != expected.length ||
        graph.nodes.map((n) => n.nodeCode).toSet().length != expected.length ||
        graph.nodes.any((n) => n.id <= 0) ||
        graph.nodes.map((n) => n.id).toSet().length != expected.length) {
      return null;
    }
    for (final n in graph.nodes) {
      final matches = expected.where((item) => item['code'] == n.nodeCode);
      if (matches.length != 1 ||
          n.floorId != graph.floor.id ||
          n.nodeType != matches.single['type'] ||
          !n.x.isFinite ||
          !n.y.isFinite ||
          (n.x - (matches.single['x'] as num)).abs() > 0.000001 ||
          (n.y - (matches.single['y'] as num)).abs() > 0.000001) {
        return null;
      }
    }
    final byId = {for (final n in graph.nodes) n.id: n};
    final localCodes = graph.nodes.map((n) => n.nodeCode).toSet();
    final expectedEdges =
        segments
            .where(
              (s) =>
                  localCodes.contains(s['from']) &&
                  localCodes.contains(s['to']),
            )
            .length *
        2;
    final pairs = <String>{};
    if (graph.edges.length != expectedEdges) return null;
    for (final edge in graph.edges) {
      final from = byId[edge.fromNodeId], to = byId[edge.toNodeId];
      if (from == null ||
          to == null ||
          !edge.isActive ||
          !pairs.add('${from.id}:${to.id}') ||
          !_edgeMatches(
            from.nodeCode,
            to.nodeCode,
            edge.edgeType,
            edge.distanceMeters,
          )) {
        return null;
      }
    }
    if (route != null) {
      for (final n in route.nodes.where((n) => n.floor.id == graph.floor.id)) {
        final coordinate = byId[n.id];
        if (coordinate == null ||
            n.floor.floorCode != graph.floor.floorCode ||
            n.floor.buildingId != graph.floor.buildingId ||
            coordinate.nodeCode != n.nodeCode ||
            coordinate.nodeType != n.nodeType) {
          return null;
        }
      }
      for (var i = 0; i < route.edges.length; i++) {
        final edge = route.edges[i];
        if (edge.fromFloorId != graph.floor.id &&
            edge.toFloorId != graph.floor.id) {
          continue;
        }
        if (i + 1 >= route.nodes.length ||
            !_edgeMatches(
              route.nodes[i].nodeCode,
              route.nodes[i + 1].nodeCode,
              edge.edgeType,
              edge.distanceMeters,
            )) {
          return null;
        }
      }
    }
    return DemoFloorPlan(
      floor['image'] as String,
      rooms.where((r) => r.floorCode == graph.floor.floorCode).toList(),
    );
  }

  VerifiedDemoRoom? verifyRoom(
    DemoRoom room,
    WayMarkMapLocation location,
    FloorMapData graph,
  ) {
    final n = location.node;
    if (match(graph) == null ||
        n == null ||
        n.nodeType != 'Entrance' ||
        n.nodeCode != room.entranceCode ||
        n.floorId != graph.floor.id ||
        graph.floor.floorCode != room.floorCode ||
        location.wayMarkCode != room.wayMarkCode) {
      return null;
    }
    final candidates = graph.nodes.where(
      (item) =>
          item.id == n.id &&
          item.nodeCode == n.nodeCode &&
          item.x == n.x &&
          item.y == n.y,
    );
    if (candidates.length != 1) return null;
    return VerifiedDemoRoom(room, n.id, n.floorId);
  }
}

class DemoFloorPlan {
  const DemoFloorPlan(this.asset, this.rooms);
  final String asset;
  final List<DemoRoom> rooms;
}

class DemoRoom {
  const DemoRoom(this.data);
  final Map<String, dynamic> data;
  String get name => data['name'] as String;
  String get number => data['number'] as String;
  String get floorCode => data['floor'] as String;
  String get entranceCode => data['entrance'] as String;
  String get wayMarkCode => data['wayMarkCode'] as String;
  bool matches(String query) => [
    name,
    ...(data['aliases'] as List).cast<String>(),
  ].any((text) => text.toLowerCase().contains(query.trim().toLowerCase()));
}

class VerifiedDemoRoom {
  const VerifiedDemoRoom(this.room, this.nodeId, this.floorId);
  final DemoRoom room;
  final int nodeId, floorId;
  bool matchesRoute(WayMarkRoute route) =>
      route.nodes.isNotEmpty &&
      route.destination.wayMarkCode == room.wayMarkCode &&
      route.nodes.last.id == nodeId &&
      route.nodes.last.floor.id == floorId &&
      route.nodes.last.nodeCode == room.entranceCode &&
      route.nodes.last.nodeType == 'Entrance';
}
