// Explicit offline rehearsal only. Never imported by lib/ or production main.
import 'package:waymark/features/route/demo_floor_plan.dart';
import 'package:waymark/models/route_models.dart';
import 'package:waymark/services/waymark_api_service.dart';

class MobileDemoData extends WayMarkApiService {
  MobileDemoData(this.bundle) {
    var id = 1000; // Fixture IDs, unrelated to SQL identities.
    for (final (index, floor) in bundle.floors.indexed) {
      final f = RouteFloor(
        id: index + 100,
        buildingId: 100,
        name: 'Demo ${floor['code'] == 'G' ? 'Ground Floor' : 'Level 1'}',
        floorCode: floor['code'] as String,
        sortOrder: index,
      );
      final nodes = (floor['nodes'] as List)
          .map(
            (n) => MapNode(
              id: ++id,
              floorId: f.id,
              nodeCode: n['code'] as String,
              name: _label(n['code'] as String),
              x: (n['x'] as num).toDouble(),
              y: (n['y'] as num).toDouble(),
              nodeType: n['type'] as String,
            ),
          )
          .toList();
      for (final n in nodes) {
        coordinates[n.nodeCode] = n;
      }
      graphs[f.id] = FloorMapData(floor: f, nodes: nodes);
    }
    for (final MapEntry(key: id, value: graph) in graphs.entries.toList()) {
      final edges = <MapGraphEdge>[];
      for (final segment in bundle.segments) {
        final from = coordinates[segment['from']]!,
            to = coordinates[segment['to']]!;
        if (from.floorId != id || to.floorId != id) continue;
        for (final pair in [
          [from, to],
          [to, from],
        ]) {
          edges.add(
            MapGraphEdge(
              pair[0].id,
              pair[1].id,
              (segment['meters'] as num).toDouble(),
              segment['type'] as String,
              true,
            ),
          );
        }
      }
      graphs[id] = FloorMapData(
        floor: graph.floor,
        nodes: graph.nodes,
        edges: edges,
      );
    }
  }
  final DemoHospitalMap bundle;
  final graphs = <int, FloorMapData>{};
  final coordinates = <String, MapNode>{};
  static const start = 'WM-DEMO-2A-START', destination = 'WM-DEMO-2A-DEST';
  static String _label(String code) => code.endsWith('ENTRY')
      ? 'Cửa Phòng 001 (Demo)'
      : code.endsWith('LIFT')
      ? 'Thang máy ${code.contains('-G-') ? 'G' : 'L1'}'
      : code.endsWith('DEST')
      ? 'Điểm WayMark L1 (Demo)'
      : code.endsWith('ISOLATED')
      ? 'Node cô lập (Demo)'
      : 'Hành lang ${code.contains('-G-') ? 'G' : 'L1'}';

  WayMarkMapLocation location(String code) {
    final n = switch (code) {
      start => coordinates['WM-DEMO-2A-G-ENTRY'],
      destination => coordinates['WM-DEMO-2A-L1-DEST'],
      _ => null,
    };
    if (n == null) {
      throw const WayMarkApiException(
        'QR không có trong fixture offline.',
        statusCode: 404,
      );
    }
    return WayMarkMapLocation(
      id: code == start ? 1 : 2,
      name: n.name,
      location: graphs[n.floorId]!.floor.name,
      wayMarkCode: code,
      node: n,
    );
  }

  @override
  Future<List<WayMark>> getWayMarks() async => [
    for (final c in [start, destination])
      WayMark(
        id: location(c).id,
        name: location(c).name,
        location: location(c).location,
        wayMarkCode: c,
      ),
  ];
  @override
  Future<WayMarkMapLocation> getMapLocation(String code) async =>
      location(code);
  @override
  Future<FloorMapData> getFloorGraph(int floorId) async {
    if (!graphs.containsKey(floorId)) {
      throw const WayMarkApiException(
        'Không có tầng fixture.',
        statusCode: 404,
      );
    }
    return graphs[floorId]!;
  }

  @override
  Future<WayMarkRoute> findRoute(
    RouteRequest request, {
    bool accessibleOnly = false,
  }) async {
    if (accessibleOnly || !request.options.isDefault) {
      throw const WayMarkApiException(
        'Fixture offline chưa xác minh accessibility hoặc bộ lọc. Dùng API thật để thử.',
        statusCode: 422,
      );
    }
    final from = location(request.startWayMarkCode),
        to = location(request.destinationWayMarkCode);
    var codes = [
      bundle.segments.first['from'] as String,
      ...bundle.segments.map((s) => s['to'] as String),
    ];
    if (from.node!.nodeCode == to.node!.nodeCode) {
      codes = [from.node!.nodeCode];
    } else if (codes.first != from.node!.nodeCode) {
      codes = codes.reversed.toList();
    }
    final nodes = codes.map((code) {
      final n = coordinates[code]!;
      return RouteNode(
        id: n.id,
        nodeCode: code,
        name: n.name,
        nodeType: n.nodeType,
        floor: graphs[n.floorId]!.floor,
      );
    }).toList();
    final edges = <RouteEdge>[];
    for (var i = 0; i < nodes.length - 1; i++) {
      final a = nodes[i], b = nodes[i + 1];
      final s = bundle.segments.singleWhere(
        (s) =>
            (s['from'] == a.nodeCode && s['to'] == b.nodeCode) ||
            (s['to'] == a.nodeCode && s['from'] == b.nodeCode),
      );
      edges.add(
        RouteEdge(
          sequence: i + 1,
          id: 200 + i,
          fromNodeId: a.id,
          toNodeId: b.id,
          fromFloorId: a.floor.id,
          toFloorId: b.floor.id,
          edgeType: s['type'] as String,
          distanceMeters: (s['meters'] as num).toDouble(),
          isAccessible: false,
          movement: a.floor.id == b.floor.id ? 'SameFloor' : 'ChangeFloor',
        ),
      );
    }
    return WayMarkRoute(
      start: from,
      destination: to,
      totalDistanceMeters: edges.fold(0, (sum, e) => sum + e.distanceMeters),
      accessibleOnly: false,
      nodes: nodes,
      edges: edges,
    );
  }
}
