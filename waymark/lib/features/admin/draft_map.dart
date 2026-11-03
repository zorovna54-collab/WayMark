import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../models/route_models.dart';
import 'floor_plan_asset.dart';
import 'floor_image_cleanup.dart';

import 'dart:ui' show Offset;

class DraftNode {
  const DraftNode(
    this.code,
    this.name,
    this.x,
    this.y,
    this.type, {
    this.displayName,
    this.searchableAsDestination = false,
    this.landmarkNote,
    this.wayMarkCode,
    this.sourceNodeId,
  });
  final String code, name, type;
  final String? displayName, landmarkNote, wayMarkCode;
  final bool searchableAsDestination;
  final double x, y;
  final int? sourceNodeId;
  String get readableName {
    bool readable(String value) =>
        value.trim().isNotEmpty &&
        value.trim() != code &&
        !RegExp(
          r'^(LOCAL-|DRAFT-)|^[0-9a-f]{8}-[0-9a-f-]{27}$',
          caseSensitive: false,
        ).hasMatch(value.trim());
    if (displayName != null && readable(displayName!)) {
      return displayName!.trim();
    }
    return readable(name) ? name.trim() : 'Node';
  }

  String badge(int index) => 'N${(index + 1).toString().padLeft(2, '0')}';
  String listLabel(int index) => '${badge(index)} · $readableName';
  DraftNode at(double newX, double newY) => DraftNode(
    code,
    name,
    newX,
    newY,
    type,
    displayName: displayName,
    searchableAsDestination: searchableAsDestination,
    landmarkNote: landmarkNote,
    wayMarkCode: wayMarkCode,
    sourceNodeId: sourceNodeId,
  );
  Map<String, dynamic> toJson() => {
    'nodeCode': code,
    'name': name,
    'x': x,
    'y': y,
    'nodeType': type,
    'displayName': displayName,
    'searchableAsDestination': searchableAsDestination,
    'landmarkNote': landmarkNote,
    'wayMarkCode': wayMarkCode,
    'sourceNodeId': sourceNodeId,
  };
}

class DraftEdge {
  const DraftEdge(
    this.from,
    this.to,
    this.meters,
    this.type, {
    this.isActive = true,
    this.isMeasured = true,
  });
  final String from, to, type;
  final double meters;
  final bool isActive, isMeasured;
  Map<String, dynamic> toJson() => {
    'fromNodeCode': from,
    'toNodeCode': to,
    'distanceMeters': isMeasured ? meters : null,
    'edgeType': type,
    'isActive': isActive,
    'isAccessible': false,
  };
}

/// Detached from the published graph and /routes. Server saves are draft-only.
class DraftMap {
  DraftMap({
    required this.siteId,
    required this.buildingId,
    required this.floor,
    this.localWorkspaceId,
    this.localSiteName,
    this.localBuildingName,
  }) {
    if (siteId <= 0 ||
        buildingId <= 0 ||
        floor.id <= 0 ||
        floor.buildingId != buildingId) {
      throw const FormatException(
        'Thông tin Site/Building/Floor bản nháp không hợp lệ.',
      );
    }
  }
  final int siteId, buildingId;
  // Local integer IDs are placeholders, never resolved against SQL/API.
  final String? localWorkspaceId, localSiteName, localBuildingName;
  bool get isLocal => localWorkspaceId != null;
  factory DraftMap.local(
    String site,
    String building,
    String floorName,
    String floorCode,
  ) => DraftMap(
    siteId: 1,
    buildingId: 1,
    localWorkspaceId: newDraftGuid(),
    localSiteName: site,
    localBuildingName: building,
    floor: RouteFloor(
      id: 1,
      buildingId: 1,
      name: floorName,
      floorCode: floorCode,
      sortOrder: 0,
    ),
  );
  final RouteFloor floor;
  final Map<String, DraftNode> _nodes = {};
  final List<DraftEdge> _edges = [];
  // Stable draft-local GUIDs, independent of published integer node IDs.
  final Map<String, String> nodeIds = {}, edgeIds = {};
  final List<Map<String, dynamic>> places = [], transitions = [];
  String nodeId(String code) => nodeIds.putIfAbsent(code, newDraftGuid);
  String edgeId(DraftEdge edge) =>
      edgeIds.putIfAbsent('${edge.from}\u0000${edge.to}', newDraftGuid);
  FloorPlanAsset? _image;
  FloorImageEdit? imageEdit;
  FloorPlanAsset? get image => _image;
  set image(FloorPlanAsset? value) {
    _image = value;
    imageEdit = null;
    layoutReviewed = false;
  }

  ImageTransform cleanupDelta(FloorImageEdit next) =>
      (imageEdit?.transform.inverse() ?? ImageTransform.identity).then(
        next.transform,
      );

  /// Validate every mapped object before committing any state. References/metres stay intact.
  void applyImageCleanup(CleanedFloorImage result) {
    if (!isLocal ||
        image == null ||
        !identical(imageEdit?.original ?? image, result.edit.original)) {
      throw const FormatException('Ảnh/tầng đã thay đổi; hãy mở lại công cụ.');
    }
    final delta = cleanupDelta(result.edit);
    final source = imageEdit?.transform.inverse() ?? ImageTransform.identity;
    final crop = ImageTransform.fromQuad(result.edit.settings.corners);
    Offset mapped(num x, num y) {
      final original = source.map(Offset(x.toDouble(), y.toDouble()));
      final p = delta.map(Offset(x.toDouble(), y.toDouble()));
      if (!ImageTransform.inside(crop.map(original)) ||
          !ImageTransform.inside(p)) {
        throw const FormatException(
          'Crop loại bỏ node/Room. Hãy điều chỉnh khung hoặc hiệu chỉnh đối tượng thủ công trước; bản nháp chưa thay đổi.',
        );
      }
      return Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0));
    }

    final changed = {
      for (final n in nodes)
        n.code: n.at(mapped(n.x, n.y).dx, mapped(n.x, n.y).dy),
    };
    final rooms = (jsonDecode(jsonEncode(places)) as List)
        .cast<Map<String, dynamic>>();
    for (final room in rooms) {
      final points = [room['label'], ...room['polygon'] as List];
      for (final point in points) {
        final p = mapped(point['x'] as num, point['y'] as num);
        point['x'] = p.dx;
        point['y'] = p.dy;
      }
    }
    _nodes.addAll(changed);
    places
      ..clear()
      ..addAll(rooms);
    _image = result.asset;
    imageEdit = result.edit;
    layoutReviewed = false;
  }

  /// A local alignment check only, never publication/accessibility approval.
  bool layoutReviewed = false;
  List<DraftNode> get nodes => List.unmodifiable(_nodes.values);
  List<DraftEdge> get edges => List.unmodifiable(_edges);

  /// Match both entrance GUID and human label. Keep the Room search result
  /// when duplicated, preserving its shortest-of-multiple-entrances behavior.
  bool isLegacyDestinationDuplicate(DraftNode node) => places.any((p) {
    final names = [
      (p['name'] as String? ?? ''),
      (p['placeCode'] as String? ?? ''),
    ].map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toSet();
    final entrances = (p['entranceNodeIds'] as List? ?? [])
        .map((id) => id.toString().toLowerCase())
        .toSet();
    return entrances.contains(nodeIds[node.code]?.toLowerCase()) &&
        [
          node.readableName,
          node.name,
          node.code,
        ].any((s) => names.contains(s.trim().toLowerCase()));
  });
  int get destinationCount =>
      nodes
          .where(
            (n) =>
                n.searchableAsDestination && !isLegacyDestinationDuplicate(n),
          )
          .length +
      places.length;
  String get graphSummary =>
      '${nodes.length} Node • ${edges.length} Edge • $destinationCount điểm đến'
      '${places.isEmpty ? '' : ' • ${places.length} Room (legacy)'}';

  void putNode(DraftNode node, {bool replace = false}) {
    if (!replace && _nodes.length >= 2000) {
      throw const FormatException('Bản nháp tối đa 2000 node.');
    }
    if (node.code.trim().isEmpty ||
        node.code.length > 100 ||
        node.code != node.code.trim() ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(node.code) ||
        node.name.trim().isEmpty ||
        node.name.length > 200 ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(node.name) ||
        ![
          'Entrance',
          'Junction',
          'Destination',
          'Elevator',
          'Stairs',
        ].contains(node.type) ||
        !node.x.isFinite ||
        !node.y.isFinite ||
        node.x < 0 ||
        node.x > 1 ||
        node.y < 0 ||
        node.y > 1) {
      throw const FormatException(
        'Mã, tên, loại node hoặc tọa độ 0–1 không hợp lệ.',
      );
    }
    if (node.wayMarkCode != null &&
        (node.wayMarkCode!.trim().isEmpty ||
            node.wayMarkCode != node.wayMarkCode!.trim() ||
            node.wayMarkCode!.length > 100 ||
            RegExp(r'[\x00-\x1F\x7F]').hasMatch(node.wayMarkCode!))) {
      throw const FormatException('WayMarkCode bản nháp không hợp lệ.');
    }
    if (node.sourceNodeId != null && node.sourceNodeId! <= 0) {
      throw const FormatException('ID node nguồn không hợp lệ.');
    }
    if (_nodes.containsKey(node.code) != replace ||
        _nodes.keys.any(
          (key) =>
              key != node.code && key.toLowerCase() == node.code.toLowerCase(),
        )) {
      throw const FormatException(
        'Node trùng mã hoặc node cần sửa không tồn tại.',
      );
    }
    if (node.wayMarkCode != null &&
        _nodes.values.any(
          (n) =>
              n.code != node.code &&
              n.wayMarkCode?.toLowerCase() == node.wayMarkCode!.toLowerCase(),
        )) {
      throw const FormatException(
        'WayMark đã liên kết một node khác trong bản nháp.',
      );
    }
    if (replace &&
        node.type != 'Entrance' &&
        places.any(
          (p) => (p['entranceNodeIds'] as List).contains(nodeIds[node.code]),
        )) {
      throw const FormatException(
        'Node là cửa vào Room/Place; không thể đổi loại.',
      );
    }
    if (replace &&
        transitions.any((t) => t['fromNodeId'] == nodeIds[node.code]) &&
        _nodes[node.code]!.type != node.type) {
      throw const FormatException(
        'Node có liên kết chuyển tầng; giữ nguyên loại.',
      );
    }
    _nodes[node.code] = node;
    nodeId(node.code);
    layoutReviewed = false;
  }

  void _validateEdge(DraftEdge edge, {DraftEdge? replacing}) {
    if (!_nodes.containsKey(edge.from) ||
        !_nodes.containsKey(edge.to) ||
        edge.from == edge.to ||
        !edge.meters.isFinite ||
        (edge.isMeasured &&
            (edge.meters <= 0 || edge.meters > 999999999.999)) ||
        (!edge.isMeasured && edge.meters != 0) ||
        ![
          'Corridor',
          'Door',
          'Elevator',
          'Stairs',
          'Ramp',
        ].contains(edge.type) ||
        _edges.any(
          (e) =>
              !identical(e, replacing) &&
              e.from == edge.from &&
              e.to == edge.to,
        )) {
      throw const FormatException(
        'Cạnh trùng, tự nối, thiếu node hoặc khoảng cách không hợp lệ.',
      );
    }
  }

  /// Read-only validation for editor forms; never allocates IDs or changes data.
  void checkEdge(DraftEdge edge, {DraftEdge? replacing}) {
    if (replacing == null && _edges.length >= 10000) {
      throw const FormatException('Bản nháp tối đa 10000 cạnh.');
    }
    if (replacing != null && !_edges.contains(replacing)) {
      throw const FormatException('Cạnh cần sửa không còn tồn tại.');
    }
    _validateEdge(edge, replacing: replacing);
  }

  void addEdge(DraftEdge edge) {
    if (_edges.length >= 10000) {
      throw const FormatException('Bản nháp tối đa 10000 cạnh.');
    }
    _validateEdge(edge);
    _edges.add(edge);
    edgeId(edge);
    layoutReviewed = false;
  }

  void updateEdge(DraftEdge old, DraftEdge replacement) {
    final index = _edges.indexOf(old);
    if (index < 0) {
      throw const FormatException('Cạnh cần sửa không còn tồn tại.');
    }
    _validateEdge(replacement, replacing: old);
    final oldKey = '${old.from}\u0000${old.to}';
    final id = edgeIds.remove(oldKey) ?? newDraftGuid();
    edgeIds['${replacement.from}\u0000${replacement.to}'] = id;
    _edges[index] = replacement;
    layoutReviewed = false;
  }

  void removeEdge(DraftEdge edge) {
    _edges.remove(edge);
    edgeIds.remove('${edge.from}\u0000${edge.to}');
    layoutReviewed = false;
  }

  void removeNode(String code) {
    final id = nodeIds[code];
    if (places.any((p) => (p['entranceNodeIds'] as List).contains(id)) ||
        transitions.any((t) => t['fromNodeId'] == id)) {
      throw const FormatException(
        'Node còn được Room/Place hoặc chuyển tầng tham chiếu; chưa thể xóa.',
      );
    }
    _nodes.remove(code);
    for (final edge in edges.where((e) => e.from == code || e.to == code)) {
      removeEdge(edge);
    }
    nodeIds.remove(code);
    layoutReviewed = false;
  }

  /// Local, directed, distance-weighted inspection of THIS draft floor only.
  /// Does not replace, call, or change the production routing service.
  DraftRoute previewRoute(String start, String end) {
    if (image == null || !layoutReviewed) {
      throw const FormatException(
        'Hãy đối chiếu graph với ảnh trước khi xem tuyến nháp.',
      );
    }
    return shortestRoute(start, end);
  }

  /// Pure directed shortest path. Callers must validate the map and clearly
  /// distinguish local inspection from physical passage/safety verification.
  DraftRoute shortestRoute(String start, String end) {
    if (!_nodes.containsKey(start) || !_nodes.containsKey(end)) {
      throw const FormatException(
        'Chọn node xuất phát và điểm đến của bản nháp.',
      );
    }
    final distances = <String, double>{start: 0};
    final previous = <String, DraftEdge>{};
    final remaining = _nodes.keys.toSet();
    while (remaining.isNotEmpty) {
      String? current;
      for (final code in remaining) {
        if (distances.containsKey(code) &&
            (current == null || distances[code]! < distances[current]!)) {
          current = code;
        }
      }
      if (current == null) break;
      if (current == end) {
        final path = <DraftEdge>[];
        var at = end;
        while (at != start) {
          final edge = previous[at]!;
          path.add(edge);
          at = edge.from;
        }
        final ordered = path.reversed.toList();
        return DraftRoute(
          [start, ...ordered.map((e) => e.to)],
          ordered,
          distances[end]!,
        );
      }
      remaining.remove(current);
      for (final edge in _edges.where(
        (e) =>
            e.isActive &&
            e.isMeasured &&
            e.from == current &&
            remaining.contains(e.to),
      )) {
        final candidate = distances[current]! + edge.meters;
        if (!candidate.isFinite) {
          throw const FormatException('Tổng khoảng cách nháp vượt giới hạn.');
        }
        if (candidate < (distances[edge.to] ?? double.infinity)) {
          distances[edge.to] = candidate;
          previous[edge.to] = edge;
        }
      }
    }
    throw const FormatException(
      'Không có tuyến có hướng trong bản nháp tầng này.',
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 2,
    'status': 'draft',
    'verifiedForPatientUse': false,
    if (isLocal)
      'localWorkspace': {
        'id': localWorkspaceId,
        'siteName': localSiteName,
        'buildingName': localBuildingName,
      },
    'siteId': siteId,
    'buildingId': buildingId,
    'floorId': floor.id,
    'floorCode': floor.floorCode,
    'floor': {
      'id': floor.id,
      'buildingId': floor.buildingId,
      'name': floor.name,
      'floorCode': floor.floorCode,
      'sortOrder': floor.sortOrder,
    },
    'imageMime': image?.mime,
    if (imageEdit != null) 'imageCleanup': imageEdit!.toJson(),
    'image': image == null
        ? null
        : {
            'name': image!.name,
            'mime': image!.mime,
            'width': image!.width,
            'height': image!.height,
            'byteLength': image!.bytes.length,
            'dataBase64': base64Encode(image!.bytes),
          },
    'nodes': nodes.map((n) => n.toJson()).toList(),
    'edges': edges.map((e) => e.toJson()).toList(),
    'draftNodeIds': nodeIds,
    'draftEdgeIds': edgeIds,
    'places': places,
    'transitions': transitions,
  };

  static const maxFileBytes = 18 * 1024 * 1024;
  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  static Future<DraftMap> decode(
    Uint8List bytes, {
    required int siteId,
    required int buildingId,
    required RouteFloor floor,
    bool allowLocal = false,
  }) async {
    if (bytes.isEmpty || bytes.length > maxFileBytes) {
      throw const FormatException('File bản nháp tối đa 18 MB.');
    }
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final local = json['localWorkspace'] as Map<String, dynamic>?;
      if (local != null && !allowLocal) {
        throw const FormatException(
          'Bản nháp local không thuộc tầng server. Hãy mở ở chế độ cục bộ.',
        );
      }
      if (![1, 2].contains(json['version']) ||
          json['status'] != 'draft' ||
          json['verifiedForPatientUse'] != false ||
          json['siteId'] != siteId ||
          json['buildingId'] != buildingId ||
          json['floorId'] != floor.id ||
          (json['nodes'] as List).length > 2000 ||
          (json['edges'] as List).length > 10000) {
        throw const FormatException(
          'File không phải bản nháp đúng tầng hoặc vượt giới hạn.',
        );
      }
      if (json['version'] == 2) {
        final savedFloor = RouteFloor.fromJson(
          json['floor'] as Map<String, dynamic>,
        );
        if (savedFloor.id != floor.id ||
            savedFloor.buildingId != buildingId ||
            savedFloor.floorCode != floor.floorCode) {
          throw const FormatException(
            'Metadata tầng không khớp tầng đang chọn.',
          );
        }
      }
      final draft = DraftMap(
        siteId: siteId,
        buildingId: buildingId,
        floor: floor,
        localWorkspaceId: local?['id'] as String?,
        localSiteName: local?['siteName'] as String?,
        localBuildingName: local?['buildingName'] as String?,
      );
      for (final node in json['nodes'] as List) {
        draft.putNode(
          DraftNode(
            node['nodeCode'] as String,
            node['name'] as String,
            (node['x'] as num).toDouble(),
            (node['y'] as num).toDouble(),
            node['nodeType'] as String,
            displayName: node['displayName'] as String?,
            searchableAsDestination:
                node['searchableAsDestination'] as bool? ?? false,
            landmarkNote: node['landmarkNote'] as String?,
            wayMarkCode: node['wayMarkCode'] as String?,
            sourceNodeId: node['sourceNodeId'] as int?,
          ),
        );
      }
      for (final edge in json['edges'] as List) {
        if (edge['isActive'] is! bool || edge['isAccessible'] != false) {
          throw const FormatException(
            'Bản nháp chỉ nhận cạnh active, chưa xác minh accessibility.',
          );
        }
        draft.addEdge(
          DraftEdge(
            edge['fromNodeCode'] as String,
            edge['toNodeCode'] as String,
            (edge['distanceMeters'] as num?)?.toDouble() ?? 0,
            edge['edgeType'] as String,
            isActive: edge['isActive'] as bool,
            isMeasured: edge['distanceMeters'] != null,
          ),
        );
      }
      if (json['draftNodeIds'] != null) {
        draft.nodeIds
          ..clear()
          ..addAll(Map<String, String>.from(json['draftNodeIds'] as Map));
      }
      if (json['draftEdgeIds'] != null) {
        draft.edgeIds
          ..clear()
          ..addAll(Map<String, String>.from(json['draftEdgeIds'] as Map));
      }
      draft.places.addAll(
        (json['places'] as List? ?? []).map(
          (p) => Map<String, dynamic>.from(p as Map),
        ),
      );
      draft.transitions.addAll(
        (json['transitions'] as List? ?? []).map(
          (p) => Map<String, dynamic>.from(p as Map),
        ),
      );
      final image = json['image'] as Map<String, dynamic>?;
      if (image != null || json['imageBase64'] != null) {
        final mime = (image?['mime'] ?? json['imageMime']) as String;
        final asset = await FloorPlanAsset.validate(
          base64Decode((image?['dataBase64'] ?? json['imageBase64']) as String),
          (image?['name'] as String?) ??
              (mime == 'image/png' ? 'plan.png' : 'plan.jpg'),
          mime,
        );
        if (image != null &&
            (asset.width != image['width'] ||
                asset.height != image['height'] ||
                asset.bytes.length != image['byteLength'])) {
          throw const FormatException('Metadata ảnh không khớp dữ liệu ảnh.');
        }
        draft.image = asset;
      }
      if (json['imageCleanup'] != null) {
        if (draft.image == null) {
          throw const FormatException('Thiếu ảnh đã xử lý.');
        }
        draft.imageEdit = await FloorImageEdit.decode(
          json['imageCleanup'] as Map<String, dynamic>,
          draft.image!,
        );
      }
      return draft; // An imported file cannot approve its own layout/publication.
    } on FormatException {
      rethrow;
    } on TypeError {
      throw const FormatException('Cấu trúc file bản nháp không hợp lệ.');
    }
  }
}

/// Open any v2 export detached from server IDs. An existing Web export keeps its
/// floor metadata and GUID references but cannot silently become server-bound.
Future<DraftMap> openLocalDraft(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > DraftMap.maxFileBytes) {
    throw const FormatException('File bản nháp tối đa 18 MB.');
  }
  try {
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final floor = RouteFloor.fromJson(json['floor'] as Map<String, dynamic>);
    final local = json['localWorkspace'] as Map<String, dynamic>?;
    bool text(dynamic value) =>
        value is String && value.trim().isNotEmpty && value.length <= 200;
    if (local != null &&
        (!RegExp(
              r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
            ).hasMatch(local['id'] as String) ||
            !text(local['siteName']) ||
            !text(local['buildingName']))) {
      throw const FormatException('Metadata bản nháp local không hợp lệ.');
    }
    json['localWorkspace'] =
        local ??
        {
          'id': newDraftGuid(),
          'siteName': 'Site nhập từ JSON',
          'buildingName': 'Building nhập từ JSON',
        };
    if (!text(floor.name) || !text(floor.floorCode)) {
      throw const FormatException('Thiếu tên/mã tầng.');
    }
    return await DraftMap.decode(
      Uint8List.fromList(utf8.encode(jsonEncode(json))),
      siteId: json['siteId'] as int,
      buildingId: json['buildingId'] as int,
      floor: floor,
      allowLocal: true,
    );
  } on TypeError {
    throw const FormatException('Cấu trúc JSON bản nháp không hợp lệ.');
  }
}

String newDraftGuid() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class DraftRoute {
  DraftRoute(List<String> codes, List<DraftEdge> edges, this.meters)
    : nodeCodes = List.unmodifiable(codes),
      edges = List.unmodifiable(edges);
  final List<String> nodeCodes;
  final List<DraftEdge> edges;
  final double meters;
}
