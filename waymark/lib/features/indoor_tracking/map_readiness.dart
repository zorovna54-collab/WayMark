import 'dart:convert';
import 'dart:ui';

import '../navigation/local_map_navigation.dart';
import '../../models/route_models.dart';
import 'tracking_graph.dart';

enum MapReadinessLevel { readyByData, warning, blocked }

typedef ReadinessFloor = ({
  String id,
  String name,
  bool imageReady,
  double? aspect,
  int? uiId,
});
typedef ReadinessNode = ({
  String id,
  String floor,
  String name,
  Offset point,
  int? uiId,
});
typedef ReadinessEdge = ({
  String id,
  String fromFloor,
  String from,
  String toFloor,
  String to,
  double meters,
  String type,
  bool active,
});

class MapReadinessIssue {
  const MapReadinessIssue(
    this.level,
    this.reasonCode,
    this.message,
    this.suggestedAction, {
    this.floor,
    this.node,
    this.edge,
    this.blocksSession = false,
  });
  final MapReadinessLevel level;
  final String reasonCode, message, suggestedAction;
  final String? floor, node, edge;
  final bool blocksSession;
}

class EdgeReadiness {
  const EdgeReadiness(
    this.edge,
    this.eligibleByData,
    this.physicallySurveyed,
    this.reasonCode,
  );
  final ReadinessEdge edge;
  final bool eligibleByData, physicallySurveyed;
  final String reasonCode;
}

class MapReadinessInput {
  MapReadinessInput({
    required this.pin,
    required this.current,
    required List<ReadinessFloor> floors,
    required List<ReadinessNode> nodes,
    required List<ReadinessEdge> edges,
    required List<String> routeNodes,
    required this.routeOwned,
  }) : floors = List.unmodifiable(floors),
       nodes = List.unmodifiable(nodes),
       edges = List.unmodifiable(edges),
       routeNodes = List.unmodifiable(routeNodes);
  final TrackingMapKey? pin, current;
  final List<ReadinessFloor> floors;
  final List<ReadinessNode> nodes;
  final List<ReadinessEdge> edges;
  final List<String> routeNodes;
  final bool routeOwned;
  // Reads this session's detached snapshot without authoring/ID repair.
  factory MapReadinessInput.fromNavigation(
    LocalMapNavigation map,
    WayMarkRoute route,
  ) {
    final p = map.publication;
    final key = p == null ? null : TrackingMapKey(p.mapId, p.version);
    final origin = map.publishedOrigin;
    final pin = origin == null
        ? key
        : TrackingMapKey(origin.mapId, origin.version);
    final raw = jsonDecode(
      utf8.decode(map.trackingSnapshotBytes()),
    ) as Map<String, dynamic>;
    final floors = <ReadinessFloor>[],
        nodes = <ReadinessNode>[],
        edges = <ReadinessEdge>[];
    String id(Object? v) => v is String ? v.toLowerCase() : '';
    double number(Object? v) => v is num ? v.toDouble() : double.nan;
    for (final f in raw['floors'] as List) {
      final floor = id((f['localWorkspace'] as Map?)?['id']);
      final ids = f['draftNodeIds'] as Map;
      int? uiFloor;
      for (final n in f['nodes'] as List) {
        final guid = id(ids[n['nodeCode']]);
        int? ui;
        try {
          final pair = map.routeIdentity(floor, guid);
          ui = pair.nodeId;
          uiFloor = pair.floorId;
        } on FormatException {
          // Leave the UI identity absent for consistency checks below.
        }
        nodes.add((
          id: guid,
          floor: floor,
          name: n['displayName'] as String? ?? n['name'] as String? ?? 'Điểm',
          point: Offset(number(n['x']), number(n['y'])),
          uiId: ui,
        ));
      }
      final image = f['image'] as Map?;
      final w = number(image?['width']), h = number(image?['height']);
      final ready =
          image != null &&
          w.isFinite &&
          h.isFinite &&
          w > 0 &&
          h > 0 &&
          image['dataBase64'] is String &&
          (image['dataBase64'] as String).isNotEmpty &&
          uiFloor != null &&
          map.imageFor(uiFloor) != null;
      floors.add((
        id: floor,
        name: (f['floor'] as Map)['name'] as String,
        imageReady: ready,
        aspect: ready ? w / h : null,
        uiId: uiFloor,
      ));
      for (final e in f['edges'] as List) {
        edges.add((
          id: id(
            (f['draftEdgeIds']
                as Map)['${e['fromNodeCode']}\u0000${e['toNodeCode']}'],
          ),
          fromFloor: floor,
          from: id(ids[e['fromNodeCode']]),
          toFloor: floor,
          to: id(ids[e['toNodeCode']]),
          meters: number(e['distanceMeters']),
          type: e['edgeType'] as String? ?? '',
          active: e['isActive'] == true,
        ));
      }
    }
    for (final l in raw['links'] as List) {
      edges.add((
        id: id(l['id']),
        fromFloor: id(l['fromFloor']),
        from: id(l['fromNode']),
        toFloor: id(l['toFloor']),
        to: id(l['toNode']),
        meters: number(l['distanceMeters']),
        type: l['type'] as String? ?? '',
        active: l['active'] == true,
      ));
    }
    final routeNodes = <String>[];
    var owned = map.owns(route);
    try {
      for (final n in route.nodes) {
        routeNodes.add(
          map.stableIdentity(n.id, n.floor.id).nodeId.toLowerCase(),
        );
      }
    } on FormatException {
      owned = false;
    }
    return MapReadinessInput(
      pin: pin,
      current: key,
      floors: floors,
      nodes: nodes,
      edges: edges,
      routeNodes: routeNodes,
      routeOwned: owned,
    );
  }
}

class MapReadinessReport {
  MapReadinessReport(
    this.input,
    List<MapReadinessIssue> issues,
    List<EdgeReadiness> edges,
    this.routeEdges,
  ) : issues = List.unmodifiable(issues),
      edges = List.unmodifiable(edges);
  final MapReadinessInput input;
  final List<MapReadinessIssue> issues;
  final List<EdgeReadiness> edges;
  final int routeEdges;
  late final List<EdgeReadiness> onRoute = _routeSequence();
  List<EdgeReadiness> _routeSequence() {
    final byPair = {for (final e in edges) '${e.edge.from}/${e.edge.to}': e};
    return List.unmodifiable([
      for (var i = 0; i + 1 < input.routeNodes.length; i++)
        if (byPair['${input.routeNodes[i]}/${input.routeNodes[i + 1]}'] != null)
          byPair['${input.routeNodes[i]}/${input.routeNodes[i + 1]}']!,
    ]);
  }

  int get eligibleRouteEdges => onRoute.where((e) => e.eligibleByData).length;
  bool get canStartLive =>
      !issues.any((i) => i.blocksSession) && eligibleRouteEdges > 0;
  bool get readyByData => canStartLive && eligibleRouteEdges == routeEdges;
  MapReadinessLevel get level => !canStartLive
      ? MapReadinessLevel.blocked
      : issues.any((i) => i.level != MapReadinessLevel.readyByData)
      ? MapReadinessLevel.warning
      : MapReadinessLevel.readyByData;
  bool eligible(String id) =>
      edges.any((e) => e.edge.id == id && e.eligibleByData);
}

class MapReadinessValidator {
  static final _guid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static bool validGuid(String? id) =>
      id != null &&
      _guid.hasMatch(id) &&
      id != '00000000-0000-0000-0000-000000000000';
  static MapReadinessReport evaluate(
    MapReadinessInput input, {
    TrackingGraph? graph,
    bool requireGraph = false,
    Set<String> surveyed = const {},
  }) {
    final issues = <MapReadinessIssue>[], results = <EdgeReadiness>[];
    void issue(
      String code,
      String message, {
      String? floor,
      String? node,
      String? edge,
      bool fatal = false,
    }) {
      issues.add(
        MapReadinessIssue(
          fatal ? MapReadinessLevel.blocked : MapReadinessLevel.warning,
          code,
          message,
          fatal
              ? 'Mở lại snapshot hợp lệ; vẫn có thể dùng chỉ đường thủ công.'
              : 'Đối chiếu dữ liệu/thực tế hoặc dùng manual/QR ở đoạn chưa phù hợp.',
          floor: floor,
          node: node,
          edge: edge,
          blocksSession: fatal,
        ),
      );
    }

    if (!validGuid(input.pin?.mapId) || (input.pin?.version ?? 0) <= 0) {
      issue(
        'invalidMapIdentity',
        'Thiếu map ID hoặc Published version hợp lệ.',
        fatal: true,
      );
    }
    if (input.pin != input.current) {
      issue(
        'mapVersionMismatch',
        'Bản đồ đã thay đổi phiên bản. Vui lòng mở lại hành trình.',
        fatal: true,
      );
    }
    final ids = <String>{};
    bool identity(String id) => validGuid(id) && ids.add(id.toLowerCase());
    final floors = <String, ReadinessFloor>{},
        nodes = <String, ReadinessNode>{};
    for (final f in input.floors) {
      if (!identity(f.id)) {
        issue(
          'floorIdentity',
          'Định danh tầng thiếu hoặc trùng.',
          floor: f.id,
          fatal: true,
        );
      }
      floors[f.id] = f;
      if (!f.imageReady ||
          f.aspect == null ||
          !f.aspect!.isFinite ||
          f.aspect! <= 0) {
        issue(
          'floorImageMissing',
          'Không tìm thấy ảnh tầng cần hiển thị.',
          floor: f.id,
        );
      }
    }
    if (floors.isEmpty) {
      issue('floorsMissing', 'Bản đồ chưa có tầng hợp lệ.', fatal: true);
    }
    for (final n in input.nodes) {
      if (!identity(n.id)) {
        issue(
          'nodeIdentity',
          'Định danh điểm thiếu hoặc trùng.',
          node: n.id,
          fatal: true,
        );
      }
      if (!floors.containsKey(n.floor)) {
        issue(
          'nodeFloorMissing',
          'Điểm tham chiếu tầng không tồn tại.',
          node: n.id,
          fatal: true,
        );
      }
      if (!n.point.dx.isFinite ||
          !n.point.dy.isFinite ||
          n.point.dx < 0 ||
          n.point.dx > 1 ||
          n.point.dy < 0 ||
          n.point.dy > 1) {
        issue(
          'nodeCoordinates',
          'Tọa độ điểm không hợp lệ.',
          node: n.id,
          fatal: true,
        );
      }
      nodes[n.id] = n;
    }
    final pairs = <String>{};
    for (final e in input.edges) {
      var code = 'readyByData';
      if (!identity(e.id)) {
        code = 'edgeIdentity';
        issue(
          code,
          'Định danh cạnh thiếu hoặc trùng.',
          edge: e.id,
          fatal: true,
        );
      }
      final a = nodes[e.from], b = nodes[e.to];
      if (a == null ||
          b == null ||
          a.floor != e.fromFloor ||
          b.floor != e.toFloor ||
          !floors.containsKey(e.fromFloor) ||
          !floors.containsKey(e.toFloor)) {
        code = 'edgeEndpointMissing';
        issue(
          code,
          'Hành lang tham chiếu điểm hoặc tầng không tồn tại.',
          edge: e.id,
          fatal: true,
        );
      }
      if (!pairs.add('${e.from}/${e.to}')) {
        code = 'duplicateDirection';
        issue(code, 'Trùng cạnh cùng chiều.', edge: e.id, fatal: true);
      }
      if (!e.meters.isFinite || e.meters <= 0) {
        code = 'edgeDistance';
        issue(
          code,
          'Khoảng cách hành lang phải hữu hạn và lớn hơn 0.',
          edge: e.id,
          fatal: true,
        );
      }
      if (!e.active) code = 'edgeInactive';
      if (e.fromFloor != e.toFloor) {
        if (!['Stairs', 'Elevator'].contains(e.type)) {
          code = 'transitionType';
          issue(
            code,
            'Liên kết tầng không đúng loại.',
            edge: e.id,
            fatal: true,
          );
        } else if (code == 'readyByData') {
          code = 'floorTransition';
        }
      } else if (!['Corridor', 'Door'].contains(e.type) &&
          code == 'readyByData') {
        code = 'unsupportedEdgeType';
      }
      final floor = floors[e.fromFloor];
      if (code == 'readyByData' &&
          (floor == null ||
              !floor.imageReady ||
              floor.aspect == null ||
              !floor.aspect!.isFinite ||
              floor.aspect! <= 0)) {
        code = 'floorImageMissing';
      }
      if (code == 'readyByData' &&
          a != null &&
          b != null &&
          (b.point - a.point).distance <= .000001) {
        code = 'degenerateGeometry';
      }
      final eligible = code == 'readyByData';
      results.add(
        EdgeReadiness(e, eligible, eligible && surveyed.contains(e.id), code),
      );
      if (!eligible) {
        issue(code, switch (code) {
          'floorTransition' => 'Chuyển tầng cần xác nhận ở tầng mới; không định vị như hành lang ngang.',
          'floorImageMissing' => 'Hành lang thiếu ảnh tầng để hiển thị Live.',
          'edgeInactive' => 'Hành lang đang tắt, không chọn làm hướng đi.',
          _ => 'Đoạn này chưa đủ điều kiện dữ liệu cho Live; dùng manual/QR.',
        }, edge: e.id);
      } else if (!surveyed.contains(e.id)) {
        issue(
          'physicalSurveyRequired',
          'Hành lang này chưa được xác nhận chiều dài và hình học thực tế.',
          edge: e.id,
        );
      }
    }
    if (!input.routeOwned ||
        input.routeNodes.isEmpty ||
        input.routeNodes.any((id) => !nodes.containsKey(id))) {
      issue(
        'routeStartOrIdentity',
        'Điểm bắt đầu hoặc route không thuộc snapshot này.',
        fatal: true,
      );
    }
    final activePairs = {
      for (final e in input.edges)
        if (e.active) (e.from, e.to),
    };
    for (var i = 0; i + 1 < input.routeNodes.length; i++) {
      if (!activePairs.contains((
        input.routeNodes[i],
        input.routeNodes[i + 1],
      ))) {
        issue(
          'routeDisconnected',
          'Tuyến thiếu kết nối có hướng đang hoạt động.',
          fatal: true,
        );
      }
    }
    if (input.routeNodes.isNotEmpty) {
      final reached = <String>{input.routeNodes.first},
          pending = [input.routeNodes.first];
      final outgoing = <String, List<String>>{};
      for (final e in input.edges.where((e) => e.active)) {
        outgoing.putIfAbsent(e.from, () => []).add(e.to);
      }
      while (pending.isNotEmpty) {
        for (final to in outgoing[pending.removeLast()] ?? const <String>[]) {
          if (reached.add(to)) pending.add(to);
        }
      }
      if (nodes.keys.any((id) => !reached.contains(id))) {
        issue(
          'disconnectedGraph',
          'Một số điểm không có đường có hướng từ điểm bắt đầu.',
        );
      }
    }
    if (graph == null && requireGraph) {
      issue(
        'trackingGraphUnavailable',
        'Không tạo được graph tracking nhất quán từ snapshot.',
        fatal: true,
      );
    }
    if (graph != null) {
      var same =
          graph.key == input.pin &&
          !graph.localPilot &&
          graph.nodes.length == input.nodes.length &&
          graph.edges.length == input.edges.length &&
          graph.floors.length == input.floors.length;
      for (final n in input.nodes) {
        final g = graph.nodes[n.id];
        same =
            same &&
            g != null &&
            g.floorKey == n.floor &&
            g.uiId == n.uiId &&
            g.point == n.point;
      }
      for (final e in input.edges) {
        final g = graph.edges[e.id];
        same =
            same &&
            g != null &&
            g.from == e.from &&
            g.to == e.to &&
            g.meters == e.meters &&
            g.type == e.type &&
            g.active == e.active;
      }
      for (final f in input.floors) {
        final g = graph.floors[f.id];
        same =
            same && g != null && g.uiId == f.uiId && g.aspectRatio == f.aspect;
      }
      if (!same) {
        issue(
          'snapshotGraphMismatch',
          'Snapshot đã pin và graph đang dùng không nhất quán.',
          fatal: true,
        );
      }
    }
    final count = input.routeNodes.isEmpty ? 0 : input.routeNodes.length - 1;
    final report = MapReadinessReport(input, issues, results, count);
    if (report.eligibleRouteEdges == 0) {
      issue(
        'noEligibleRouteEdges',
        'Bản đồ chưa có đủ dữ liệu để định vị theo bước chân trên tuyến này.',
      );
    }
    return MapReadinessReport(input, issues, results, count);
  }
}
