import '../admin/draft_map.dart';

import 'dart:typed_data';

import '../admin/local_map_project.dart';
import '../admin/draft_server_session.dart';
import '../../models/route_models.dart';
import '../../services/navigation_history_service.dart';

import 'package:flutter/painting.dart' show MemoryImage;

class LocalMapValidation {
  const LocalMapValidation(this.errors, this.warnings);
  final List<String> errors, warnings;
  bool get canRoute => errors.isEmpty;
  static LocalMapValidation check(DraftMap draft, {bool allowEmpty = false}) {
    final errors = <String>[],
        warnings = <String>[
          'Chỉ kiểm tra dữ liệu. Lối đi, vị trí thực và khả năng tiếp cận xe lăn chưa được xác minh.',
        ];
    if (!draft.isLocal) {
      errors.add('Hãy mở bản sao JSON cục bộ trước khi thử Navigation.');
    }
    if (!allowEmpty && draft.nodes.isEmpty) errors.add('Bản đồ chưa có node.');
    if (!allowEmpty && draft.edges.isEmpty) {
      errors.add('Bản đồ chưa có cạnh có hướng.');
    }
    if (!allowEmpty &&
        draft.places.isEmpty &&
        !draft.nodes.any((node) => node.searchableAsDestination)) {
      errors.add(
        'Chưa có điểm đến. Hãy đánh dấu một Node làm điểm đến hoặc thêm Room/Place.',
      );
    }
    if (draft.image == null) {
      warnings.add('Chưa có ảnh tầng; chỉ hiển thị sơ đồ canvas.');
    }
    if (draft.transitions.isNotEmpty) {
      errors.add(
        'JSON v2 hiện là một tầng. Có liên kết liên tầng chưa tải/đối chiếu được; không dùng các liên kết này để dẫn đường.',
      );
    }
    final ids = <String>{};
    final guid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    void id(String? value) {
      if (value == null ||
          !guid.hasMatch(value) ||
          value == '00000000-0000-0000-0000-000000000000' ||
          !ids.add(value.toLowerCase())) {
        errors.add(
          'GUID thiếu, không hợp lệ hoặc bị trùng giữa các đối tượng.',
        );
      }
    }

    final codes = <String>{};
    for (final node in draft.nodes) {
      if (!codes.add(node.code.toLowerCase())) {
        errors.add('NodeCode trùng: ${node.code}');
      }
      id(draft.nodeIds[node.code]);
      if (!node.x.isFinite ||
          !node.y.isFinite ||
          node.x < 0 ||
          node.x > 1 ||
          node.y < 0 ||
          node.y > 1) {
        errors.add('Tọa độ node ngoài 0–1: ${node.code}');
      }
    }
    for (final edge in draft.edges) {
      id(draft.edgeIds['${edge.from}\u0000${edge.to}']);
      if (!edge.isMeasured || !edge.meters.isFinite || edge.meters <= 0) {
        errors.add(
          'Cạnh ${edge.from} → ${edge.to} phải có khoảng cách mét > 0 đã nhập.',
        );
      }
      if (!codes.contains(edge.from.toLowerCase()) ||
          !codes.contains(edge.to.toLowerCase())) {
        errors.add('Cạnh tham chiếu node không thuộc tầng này.');
      }
    }
    for (final place in draft.places) {
      id(place['id'] is String ? place['id'] as String : null);
    }
    if (draft.edgeIds.keys
        .toSet()
        .difference(draft.edges.map((e) => '${e.from}\u0000${e.to}').toSet())
        .isNotEmpty) {
      errors.add('Có GUID cạnh không thuộc graph tầng này.');
    }
    if (draft.nodeIds.keys
        .toSet()
        .difference(draft.nodes.map((n) => n.code).toSet())
        .isNotEmpty) {
      errors.add('Có GUID node không thuộc graph tầng này.');
    }
    // Check without repairing/mutating IDs. Mapper's nodeId/edgeId helpers
    // cannot generate IDs here once the preconditions above have succeeded.
    if (errors.isEmpty) {
      try {
        DraftServerMapper.content(draft, null);
      } on FormatException catch (e) {
        errors.add(e.message);
      } on TypeError {
        errors.add('Room/Place hoặc tham chiếu cửa không đúng cấu trúc.');
      }
    }
    final isolated = draft.nodes
        .where(
          (n) => !draft.edges.any(
            (e) => e.isActive && (e.from == n.code || e.to == n.code),
          ),
        )
        .length;
    if (isolated > 0) {
      warnings.add(
        '$isolated node cô lập/không có cạnh active; có thể không tìm được tuyến.',
      );
    }
    if (draft.edges.any((e) => !e.isActive)) {
      warnings.add('Cạnh inactive sẽ không được dùng.');
    }
    return LocalMapValidation(
      List.unmodifiable(errors.toSet()),
      List.unmodifiable(warnings),
    );
  }
}

class LocalRoom {
  const LocalRoom(
    this.id,
    this.code,
    this.name,
    this.entrances,
    this.x,
    this.y, {
    this.floorId = 1,
  });
  final String id, code, name;
  final int floorId;
  final List<String> entrances;
  final double x, y;
  bool matches(String text) =>
      '$code $name'.toLowerCase().contains(text.trim().toLowerCase());
}

/// Immutable-in-practice, detached snapshot. It has no HTTP client, JWT,
/// WayMark lookup or SQL identifiers. Integer route IDs are session-local only.
class LocalMapNavigation {
  NavigationHistorySession? historySession;
  LocalMapNavigation._(this._project, {required this.multi}) {
    var nextId = 1;
    _routing = DraftMap.local('Local', 'Local', 'Graph', 'GRAPH');
    for (final (index, d) in _project.floors.indexed) {
      final floor = RouteFloor(
        id: index + 1,
        buildingId: 1,
        name: d.floor.name,
        floorCode: d.floor.floorCode,
        sortOrder: index,
      );
      final nodes = <MapNode>[];
      for (final n in d.nodes) {
        final key = _key(d, n.code), id = nextId++;
        _ids[key] = id;
        _nodeFloors[key] = floor;
        _originalCodes[key] = n.code;
        final stable = (
          floorKey: d.localWorkspaceId!,
          nodeId: d.nodeIds[n.code]!,
        );
        _stableByUi[(id, floor.id)] = stable;
        _keyByStable[(
              stable.floorKey.toLowerCase(),
              stable.nodeId.toLowerCase(),
            )] =
            key;
        _routing.putNode(DraftNode(key, n.readableName, n.x, n.y, n.type));
        nodes.add(
          MapNode(
            id: id,
            floorId: floor.id,
            nodeCode: n.code,
            name: n.readableName,
            x: n.x,
            y: n.y,
            nodeType: n.type,
          ),
        );
      }
      _drafts[floor.id] = d;
      _graphs[floor.id] = FloorMapData(
        floor: floor,
        nodes: List.unmodifiable(nodes),
        edges: List.unmodifiable([
          for (final e in d.edges)
            MapGraphEdge(
              _ids[_key(d, e.from)]!,
              _ids[_key(d, e.to)]!,
              e.meters,
              e.type,
              e.isActive,
            ),
        ]),
      );
      for (final e in d.edges) {
        _routing.addEdge(
          DraftEdge(
            _key(d, e.from),
            _key(d, e.to),
            e.meters,
            e.type,
            isActive: e.isActive,
            isMeasured: e.isMeasured,
          ),
        );
      }
      for (final p in d.places) {
        _rooms.add(
          LocalRoom(
            (p['id'] as String).toLowerCase(),
            p['placeCode'] as String,
            p['name'] as String,
            List.unmodifiable(
              (p['entranceNodeIds'] as List).cast<String>().map(
                (s) => s.toLowerCase(),
              ),
            ),
            (p['label']['x'] as num).toDouble(),
            (p['label']['y'] as num).toDouble(),
            floorId: floor.id,
          ),
        );
      }
    }
    for (final l in _project.links) {
      _routing.addEdge(
        DraftEdge(
          l.fromNode.toLowerCase(),
          l.toNode.toLowerCase(),
          l.meters,
          l.type,
          isActive: l.active,
        ),
      );
    }
  }
  final LocalMapProject _project;

  /// A detached serialized copy for read-only consumers such as live tracking.
  /// Never exposes the mutable Builder or this session's private graph.
  Uint8List trackingSnapshotBytes() => _project.encode();
  final bool multi;

  /// Only set after loading and validating an explicit public snapshot.
  ({String mapId, int version})? publication;
  ({String mapId, int version})? _publishedOrigin;
  ({String mapId, int version})? get publishedOrigin => _publishedOrigin;

  /// Loading provenance, bound once by the Published reader. Never inferred
  /// from a mutable editor project or a later publication field assignment.
  void bindPublishedOrigin(String mapId, int version) {
    if (_publishedOrigin != null) {
      throw const FormatException('Snapshot Published đã được pin.');
    }
    _publishedOrigin = (mapId: mapId, version: version);
    publication = _publishedOrigin;
  }

  bool personalPublication = false;
  String? publicationQrPayload;
  ({String floorKey, String nodeId}) stableIdentity(int nodeId, int floorId) {
    final identity = _stableByUi[(nodeId, floorId)];
    if (identity == null) {
      throw const FormatException('Node không thuộc snapshot.');
    }
    return identity;
  }

  ({int nodeId, int floorId}) routeIdentity(String floorKey, String nodeId) {
    final key = stableStartKey(floorKey, nodeId);
    return (nodeId: _ids[key]!, floorId: _nodeFloors[key]!.id);
  }

  Future<WayMarkMapLocation> Function(String payload)? resolvePublishedQr;
  late final DraftMap _routing;
  final _ids = <String, int>{};
  final _stableByUi = <(int, int), ({String floorKey, String nodeId})>{};
  final _keyByStable = <(String, String), String>{};
  final _nodeFloors = <String, RouteFloor>{};
  final _originalCodes = <String, String>{};
  final _graphs = <int, FloorMapData>{};
  final _drafts = <int, DraftMap>{};
  final _rooms = <LocalRoom>[];
  final _routes = Expando<bool>('local-map-routes');
  final _roomTargets = Expando<String>('local-room-targets');
  bool owns(WayMarkRoute route) => _routes[route] == true;
  String _key(DraftMap d, String code) =>
      multi ? d.nodeIds[code]!.toLowerCase() : code;
  RouteFloor get floor => _graphs.values.first.floor;
  FloorMapData get graph => _graphs.values.first;
  FloorMapData graphFor(int id) =>
      _graphs[id] ??
      (throw const FormatException('Tầng không thuộc project này.'));
  MemoryImage? get image => imageFor(floor.id);
  MemoryImage? imageFor(int id) => _drafts[id]?.image?.imageProvider;
  String? landmarkNoteForNode(int nodeId, int floorId) {
    final entry = _ids.entries
        .where(
          (entry) =>
              entry.value == nodeId && _nodeFloors[entry.key]?.id == floorId,
        )
        .firstOrNull;
    if (entry == null) return null;
    final code = _originalCodes[entry.key]!;
    final note = _drafts[floorId]!.nodes
        .singleWhere((node) => node.code == code)
        .landmarkNote
        ?.trim();
    return note == null || note.isEmpty ? null : note;
  }

  List<LocalRoom> get rooms => List.unmodifiable(_rooms);
  List<LocalRoom> get searchableRooms => rooms;
  List<LocalRoom> roomsFor(int id) =>
      List.unmodifiable(_rooms.where((r) => r.floorId == id));
  List<LocalRoom> routeRoomLabels(WayMarkRoute route, int floorId) =>
      roomsFor(floorId)
          .where((r) => r.id == _roomTargets[route])
          .toList(growable: false);
  List<
    ({
      int nodeId,
      int floorId,
      String nodeCode,
      String name,
      String displayName,
      String floorName,
      String badge,
    })
  >
  get destinationNodes => [
    for (final entry in _drafts.entries)
      for (final (i, n) in entry.value.nodes.indexed)
        if (n.searchableAsDestination &&
            !entry.value.isLegacyDestinationDuplicate(n))
          (
            nodeId: _ids[_key(entry.value, n.code)]!,
            floorId: entry.key,
            nodeCode: n.code,
            name: n.name,
            displayName: n.readableName,
            floorName: _graphs[entry.key]!.floor.name,
            badge: n.badge(i),
          ),
  ];
  List<({String key, String label, String badge})> get startChoices => [
    for (final entry in _drafts.entries)
      for (final (i, n) in entry.value.nodes.indexed)
        (
          key: _key(entry.value, n.code),
          label:
              '${n.readableName}${n.code.startsWith('LOCAL-') || n.code.startsWith('DRAFT-') ? '' : ' (${n.code})'}${multi ? ' • ${_graphs[entry.key]!.floor.name}' : ''}',
          badge: n.badge(i),
        ),
  ];
  String get workspaceId => _project.id;
  String stableStartKey(String floorKey, String nodeId) {
    final key = _keyByStable[(floorKey.toLowerCase(), nodeId.toLowerCase())];
    if (key == null) {
      throw const FormatException('QR không thuộc node/tầng của snapshot này.');
    }
    return key;
  }

  WayMarkMapLocation stableLocation(
    String floorKey,
    String nodeId,
    String payload,
  ) {
    final key = stableStartKey(floorKey, nodeId),
        floor = _nodeFloors[stableStartKey(floorKey, nodeId)]!;
    final n = _graphs[floor.id]!.nodes.singleWhere((n) => n.id == _ids[key]);
    return WayMarkMapLocation(
      id: n.id,
      name: n.name,
      location: floor.name,
      wayMarkCode: payload,
      node: n,
    );
  }

  WayMarkRoute rerouteFromStable(
    String floorKey,
    String nodeId,
    WayMarkRoute previous,
  ) {
    if (!owns(previous)) {
      throw const FormatException('Tuyến không thuộc snapshot này.');
    }
    final key = stableStartKey(floorKey, nodeId), room = _roomTargets[previous];
    return room != null
        ? routeToRoom(key, room)
        : routeToNode(
            key,
            previous.nodes.last.id,
            previous.nodes.last.floor.id,
          );
  }

  WayMarkRoute rerouteFromLocation(
    WayMarkMapLocation location,
    WayMarkRoute previous,
  ) {
    if (!owns(previous) || location.node == null) {
      throw const FormatException('Vị trí không thuộc snapshot.');
    }
    final n = location.node!;
    final key = _ids.entries
        .where((e) => e.value == n.id && _nodeFloors[e.key]?.id == n.floorId)
        .firstOrNull
        ?.key;
    if (key == null) {
      throw const FormatException('Node/tầng QR không thuộc snapshot.');
    }
    final room = _roomTargets[previous];
    return room != null
        ? routeToRoom(key, room)
        : routeToNode(
            key,
            previous.nodes.last.id,
            previous.nodes.last.floor.id,
          );
  }

  static LocalMapValidation validateProject(LocalMapProject project) {
    final errors = <String>[], warnings = <String>{};
    if (project.floors.fold<int>(0, (n, f) => n + f.nodes.length) > 2000 ||
        project.floors.fold<int>(
              project.links.length,
              (n, f) => n + f.edges.length,
            ) >
            10000) {
      errors.add('Project tối đa 2000 node và 10000 cạnh để xem trước cục bộ.');
    }
    try {
      project.checkReferences();
    } on FormatException catch (e) {
      errors.add(e.message);
    }
    for (final f in project.floors) {
      final v = LocalMapValidation.check(f, allowEmpty: true);
      errors.addAll(v.errors.map((e) => '${f.floor.name}: $e'));
      warnings.addAll(v.warnings.map((e) => '${f.floor.name}: $e'));
    }
    if (project.floors.every((f) => f.nodes.isEmpty)) {
      errors.add('Project chưa có node.');
    }
    if (project.floors.every((f) => f.edges.isEmpty) && project.links.isEmpty) {
      errors.add('Project chưa có cạnh.');
    }
    final hasRoomDestination = project.floors.any((f) => f.places.isNotEmpty);
    final hasNodeDestination = project.floors.any(
      (f) => f.nodes.any((node) => node.searchableAsDestination),
    );
    if (!hasRoomDestination && !hasNodeDestination) {
      errors.add(
        'Chưa có điểm đến. Hãy đánh dấu một Node làm điểm đến hoặc thêm Room/Place.',
      );
    }
    return LocalMapValidation(
      List.unmodifiable(errors),
      List.unmodifiable(warnings),
    );
  }

  static Future<LocalMapNavigation> fromDraft(DraftMap draft) async {
    final v = LocalMapValidation.check(draft);
    if (!v.canRoute) throw FormatException(v.errors.join('\n'));
    return LocalMapNavigation._(
      LocalMapProject(await openLocalDraft(draft.encode())),
      multi: false,
    );
  }

  static Future<LocalMapNavigation> fromProject(LocalMapProject project) async {
    final v = validateProject(project);
    if (!v.canRoute) throw FormatException(v.errors.join('\n'));
    final copy = await LocalMapProject.decode(project.encode());
    return LocalMapNavigation._(copy, multi: true);
  }

  WayMarkRoute routeToRoom(String startCode, String placeId) {
    final room = rooms.where((r) => r.id == placeId.toLowerCase()).firstOrNull;
    if (room == null || !_ids.containsKey(startCode)) {
      throw const FormatException(
        'Điểm bắt đầu hoặc Room không thuộc bản đồ này.',
      );
    }
    DraftRoute? best;
    final d = _drafts[room.floorId]!;
    for (final entrance in room.entrances) {
      final code = d.nodeIds.entries
          .singleWhere((e) => e.value.toLowerCase() == entrance)
          .key;
      try {
        final path = _routing.shortestRoute(startCode, _key(d, code));
        if (best == null || path.meters < best.meters) best = path;
      } on FormatException {
        /* No artificial connection. Try other entrances. */
      }
    }
    if (best == null) {
      throw const FormatException(
        'Không có đường có hướng từ điểm bắt đầu tới cửa của phòng này.',
      );
    }
    final route = _routeToTarget(startCode, best, room.name);
    _roomTargets[route] = room.id;
    return route;
  }

  WayMarkRoute routeToNode(
    String startCode,
    int destinationNodeId,
    int destinationFloorId,
  ) {
    if (!_ids.containsKey(startCode)) {
      throw const FormatException('Điểm bắt đầu không thuộc bản đồ này.');
    }
    final destinationKey = _ids.entries
        .where(
          (entry) =>
              entry.value == destinationNodeId &&
              _nodeFloors[entry.key]?.id == destinationFloorId,
        )
        .map((entry) => entry.key)
        .firstOrNull;
    if (destinationKey == null) {
      throw const FormatException('Điểm đến Node không thuộc tầng/bản đồ này.');
    }
    final destinationCode = _originalCodes[destinationKey]!;
    final destinationDraft = _drafts[destinationFloorId]!.nodes.singleWhere(
      (node) => node.code == destinationCode,
    );
    if (!destinationDraft.searchableAsDestination) {
      throw const FormatException('Node này không được đánh dấu làm điểm đến.');
    }
    final destinationName = destinationDraft.readableName;
    late final DraftRoute path;
    try {
      path = _routing.shortestRoute(startCode, destinationKey);
    } on FormatException {
      throw const FormatException(
        'Không có tuyến có hướng từ điểm bắt đầu tới Node đích.',
      );
    }
    return _routeToTarget(
      startCode,
      path,
      destinationName,
      routeNodeDestinationName: destinationName,
    );
  }

  WayMarkRoute _routeToTarget(
    String startCode,
    DraftRoute path,
    String destinationName, {
    String? routeNodeDestinationName,
  }) {
    final byCode = {for (final n in _routing.nodes) n.code: n};
    RoutePoint point(String code, String name) => RoutePoint(
      id: _ids[code]!,
      name: name,
      location: _nodeFloors[code]!.name,
      wayMarkCode: '',
    );
    final route = WayMarkRoute(
      start: point(startCode, byCode[startCode]!.name),
      destination: point(path.nodeCodes.last, destinationName),
      totalDistanceMeters: path.meters,
      accessibleOnly: false,
      nodes: List.unmodifiable([
        for (final key in path.nodeCodes)
          RouteNode(
            id: _ids[key]!,
            nodeCode: _originalCodes[key]!,
            name: key == path.nodeCodes.last
                ? routeNodeDestinationName ?? byCode[key]!.name
                : byCode[key]!.name,
            nodeType: byCode[key]!.type,
            floor: _nodeFloors[key]!,
          ),
      ]),
      edges: List.unmodifiable([
        for (final (i, e) in path.edges.indexed)
          RouteEdge(
            sequence: i + 1,
            id: _routing.edges.indexOf(e) + 1,
            fromNodeId: _ids[e.from]!,
            toNodeId: _ids[e.to]!,
            fromFloorId: _nodeFloors[e.from]!.id,
            toFloorId: _nodeFloors[e.to]!.id,
            edgeType: e.type,
            distanceMeters: e.meters,
            isAccessible: false,
            movement: _nodeFloors[e.from]!.id == _nodeFloors[e.to]!.id
                ? 'SameFloor'
                : 'ChangeFloor',
          ),
      ]),
    );
    _routes[route] = true;
    return route;
  }
}
