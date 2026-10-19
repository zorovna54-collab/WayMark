import 'dart:convert';
import 'dart:typed_data';

import '../../models/route_models.dart';
import 'floor_plan_asset.dart';

class DraftNode {
  const DraftNode(
    this.code,
    this.name,
    this.x,
    this.y,
    this.type, {
    this.wayMarkCode,
    this.sourceNodeId,
  });
  final String code, name, type;
  final String? wayMarkCode;
  final double x, y;
  final int? sourceNodeId;
  DraftNode at(double newX, double newY) => DraftNode(
    code,
    name,
    newX,
    newY,
    type,
    wayMarkCode: wayMarkCode,
    sourceNodeId: sourceNodeId,
  );
  Map<String, dynamic> toJson() => {
    'nodeCode': code,
    'name': name,
    'x': x,
    'y': y,
    'nodeType': type,
    'wayMarkCode': wayMarkCode,
    'sourceNodeId': sourceNodeId,
  };
}

class DraftEdge {
  const DraftEdge(this.from, this.to, this.meters, this.type);
  final String from, to, type;
  final double meters;
  Map<String, dynamic> toJson() => {
    'fromNodeCode': from,
    'toNodeCode': to,
    'distanceMeters': meters,
    'edgeType': type,
    'isActive': true,
    'isAccessible': false,
  };
}

/// Deliberately detached from EF and /routes. No publish/write API is invoked.
class DraftMap {
  DraftMap({
    required this.siteId,
    required this.buildingId,
    required this.floor,
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
  final RouteFloor floor;
  final Map<String, DraftNode> _nodes = {};
  final List<DraftEdge> _edges = [];
  FloorPlanAsset? _image;
  FloorPlanAsset? get image => _image;
  set image(FloorPlanAsset? value) {
    _image = value;
    layoutReviewed = false;
  }

  /// A local alignment check only, never publication/accessibility approval.
  bool layoutReviewed = false;
  List<DraftNode> get nodes => List.unmodifiable(_nodes.values);
  List<DraftEdge> get edges => List.unmodifiable(_edges);

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
    _nodes[node.code] = node;
    layoutReviewed = false;
  }

  void _validateEdge(DraftEdge edge, {DraftEdge? replacing}) {
    if (!_nodes.containsKey(edge.from) ||
        !_nodes.containsKey(edge.to) ||
        edge.from == edge.to ||
        !edge.meters.isFinite ||
        edge.meters <= 0 ||
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

  void addEdge(DraftEdge edge) {
    if (_edges.length >= 10000) {
      throw const FormatException('Bản nháp tối đa 10000 cạnh.');
    }
    _validateEdge(edge);
    _edges.add(edge);
    layoutReviewed = false;
  }

  void updateEdge(DraftEdge old, DraftEdge replacement) {
    final index = _edges.indexOf(old);
    if (index < 0) {
      throw const FormatException('Cạnh cần sửa không còn tồn tại.');
    }
    _validateEdge(replacement, replacing: old);
    _edges[index] = replacement;
    layoutReviewed = false;
  }

  void removeEdge(DraftEdge edge) {
    _edges.remove(edge);
    layoutReviewed = false;
  }

  void removeNode(String code) {
    _nodes.remove(code);
    _edges.removeWhere((e) => e.from == code || e.to == code);
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
        (e) => e.from == current && remaining.contains(e.to),
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
  };

  static const maxFileBytes = 18 * 1024 * 1024;
  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  static Future<DraftMap> decode(
    Uint8List bytes, {
    required int siteId,
    required int buildingId,
    required RouteFloor floor,
  }) async {
    if (bytes.isEmpty || bytes.length > maxFileBytes) {
      throw const FormatException('File bản nháp tối đa 18 MB.');
    }
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
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
      );
      for (final node in json['nodes'] as List) {
        draft.putNode(
          DraftNode(
            node['nodeCode'] as String,
            node['name'] as String,
            (node['x'] as num).toDouble(),
            (node['y'] as num).toDouble(),
            node['nodeType'] as String,
            wayMarkCode: node['wayMarkCode'] as String?,
            sourceNodeId: node['sourceNodeId'] as int?,
          ),
        );
      }
      for (final edge in json['edges'] as List) {
        if (edge['isActive'] != true || edge['isAccessible'] != false) {
          throw const FormatException(
            'Bản nháp chỉ nhận cạnh active, chưa xác minh accessibility.',
          );
        }
        draft.addEdge(
          DraftEdge(
            edge['fromNodeCode'] as String,
            edge['toNodeCode'] as String,
            (edge['distanceMeters'] as num).toDouble(),
            edge['edgeType'] as String,
          ),
        );
      }
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
      return draft; // An imported file cannot approve its own layout/publication.
    } on FormatException {
      rethrow;
    } on TypeError {
      throw const FormatException('Cấu trúc file bản nháp không hợp lệ.');
    }
  }
}

class DraftRoute {
  DraftRoute(List<String> codes, List<DraftEdge> edges, this.meters)
    : nodeCodes = List.unmodifiable(codes),
      edges = List.unmodifiable(edges);
  final List<String> nodeCodes;
  final List<DraftEdge> edges;
  final double meters;
}
