import 'dart:convert';
import 'dart:typed_data';

import 'draft_map.dart';

/// v3 wraps unchanged v2 floors. No server identifiers or publication implied.
class LocalMapProject {
  LocalMapProject(DraftMap first) : id = newDraftGuid(), floors = [first];
  LocalMapProject._(this.id, this.floors, this.links);
  final String id;
  final List<DraftMap> floors;
  List<LocalFloorLink> links = [];
  static const maxBytes = 64 * 1024 * 1024;
  static const maxFloors = 12;

  /// Explicit local recovery only. A legacy one-floor backup has no project ID;
  /// it may retain the currently opened project's ID only when its floor GUID
  /// matches exactly. API ownership remains authoritative on every later write.
  static LocalMapProject recoverSingleFloor(
    DraftMap backup,
    LocalMapProject target,
  ) {
    if (target.floors.length != 1 ||
        backup.localWorkspaceId == null ||
        target.floors.single.localWorkspaceId == null ||
        target.links.isNotEmpty ||
        backup.localWorkspaceId?.toLowerCase() !=
            target.floors.single.localWorkspaceId?.toLowerCase()) {
      throw const FormatException(
        'GUID tầng của JSON v2 không khớp bản đồ đang mở; không tự gắn vào server.',
      );
    }
    return LocalMapProject._(target.id, [backup], []);
  }

  Uint8List encode() {
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'version': 3,
          'kind': 'WayMarkLocalProject',
          'id': id,
          'floors': floors
              .map((f) => jsonDecode(utf8.decode(f.encode())))
              .toList(),
          'links': links.map((l) => l.toJson()).toList(),
        }),
      ),
    );
    if (bytes.length > maxBytes) {
      throw const FormatException('Project tối đa 64 MB.');
    }
    return bytes;
  }

  static Future<LocalMapProject> decode(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Project tối đa 64 MB.');
    }
    try {
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (j['version'] != 3) {
        return LocalMapProject(await openLocalDraft(bytes));
      }
      if (j['kind'] != 'WayMarkLocalProject' || !validGuid(j['id'])) {
        throw const FormatException('Project v3 không hợp lệ.');
      }
      final list = j['floors'] as List;
      if (list.isEmpty || list.length > maxFloors) {
        throw const FormatException('Project cần 1–12 tầng.');
      }
      final floors = <DraftMap>[];
      for (final f in list) {
        floors.add(
          await openLocalDraft(Uint8List.fromList(utf8.encode(jsonEncode(f)))),
        );
      }
      final p = LocalMapProject._(
        j['id'] as String,
        floors,
        (j['links'] as List)
            .map((e) => LocalFloorLink.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
      p.checkReferences();
      return p;
    } on TypeError {
      throw const FormatException('Cấu trúc project không hợp lệ.');
    }
  }

  static bool validGuid(dynamic s) =>
      s is String &&
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(s) &&
      s != '00000000-0000-0000-0000-000000000000';
  void checkReferences() {
    if (floors.isEmpty || floors.length > maxFloors || links.length > 1000) {
      throw const FormatException(
        'Project cần 1–12 tầng và tối đa 1000 liên kết.',
      );
    }
    final ids = <String>{}, codes = <String>{};
    for (final f in floors) {
      if (!validGuid(f.localWorkspaceId) ||
          !ids.add(f.localWorkspaceId!.toLowerCase()) ||
          !codes.add(f.floor.floorCode.toLowerCase())) {
        throw const FormatException('ID hoặc mã tầng trùng/không hợp lệ.');
      }
      for (final id in [
        ...f.nodeIds.values,
        ...f.edgeIds.values,
        ...f.places.map((p) => p['id']),
      ]) {
        if (!validGuid(id) || !ids.add((id as String).toLowerCase())) {
          throw const FormatException('GUID trùng giữa các tầng.');
        }
      }
    }
    final pairs = <String>{};
    for (final l in links) {
      if (!validGuid(l.id) ||
          !ids.add(l.id.toLowerCase()) ||
          l.fromFloor == l.toFloor ||
          !l.meters.isFinite ||
          l.meters <= 0 ||
          !['Stairs', 'Elevator'].contains(l.type) ||
          !pairs.add('${l.fromFloor}/${l.fromNode}/${l.toFloor}/${l.toNode}')) {
        throw const FormatException('Liên kết tầng trùng hoặc không hợp lệ.');
      }
      for (final end in [(l.fromFloor, l.fromNode), (l.toFloor, l.toNode)]) {
        final f = floors.where((f) => f.localWorkspaceId == end.$1).firstOrNull;
        final code = f?.nodeIds.entries
            .where((n) => n.value == end.$2)
            .firstOrNull
            ?.key;
        final node = f?.nodes.where((n) => n.code == code).firstOrNull;
        if (node == null || node.type != l.type) {
          throw const FormatException(
            'Liên kết phải nối đúng hai node cầu thang/thang máy thuộc các tầng đã khai báo.',
          );
        }
      }
    }
  }

  void removeFloor(DraftMap floor) {
    if (floors.length == 1) {
      throw const FormatException('Cần giữ ít nhất một tầng.');
    }
    floors.remove(floor);
    links.removeWhere(
      (l) =>
          l.fromFloor == floor.localWorkspaceId ||
          l.toFloor == floor.localWorkspaceId,
    );
  }

  Future<DraftMap> renameFloor(DraftMap floor, String name, String code) async {
    if (name.trim().isEmpty ||
        code.trim().isEmpty ||
        floors.any(
          (f) =>
              f != floor &&
              f.floor.floorCode.toLowerCase() == code.trim().toLowerCase(),
        )) {
      throw const FormatException('Tên/mã tầng thiếu hoặc trùng.');
    }
    final j = jsonDecode(utf8.decode(floor.encode())) as Map<String, dynamic>;
    j['floor']['name'] = name.trim();
    j['floor']['floorCode'] = code.trim();
    final copy = await openLocalDraft(
      Uint8List.fromList(utf8.encode(jsonEncode(j))),
    );
    floors[floors.indexOf(floor)] = copy;
    return copy;
  }
}

class LocalFloorLink {
  LocalFloorLink({
    required this.fromFloor,
    required this.fromNode,
    required this.toFloor,
    required this.toNode,
    required this.meters,
    required this.type,
    this.active = true,
    String? id,
  }) : id = id ?? newDraftGuid();
  final String id, fromFloor, fromNode, toFloor, toNode, type;
  final double meters;
  final bool active;
  Map<String, dynamic> toJson() => {
    'id': id,
    'fromFloor': fromFloor,
    'fromNode': fromNode,
    'toFloor': toFloor,
    'toNode': toNode,
    'distanceMeters': meters,
    'type': type,
    'active': active,
    'accessibility': 'Unknown',
  };
  factory LocalFloorLink.fromJson(Map<String, dynamic> j) {
    if (j['accessibility'] != 'Unknown') {
      throw const FormatException('Tiếp cận liên tầng phải giữ Unknown.');
    }
    return LocalFloorLink(
      id: j['id'] as String,
      fromFloor: j['fromFloor'] as String,
      fromNode: j['fromNode'] as String,
      toFloor: j['toFloor'] as String,
      toNode: j['toNode'] as String,
      meters: (j['distanceMeters'] as num).toDouble(),
      type: j['type'] as String,
      active: j['active'] as bool,
    );
  }
}
