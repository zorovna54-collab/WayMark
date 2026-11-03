import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals;

import '../../models/route_models.dart';
import '../../services/map_draft_api_service.dart';
import 'draft_map.dart';
import 'floor_plan_asset.dart';

/// Explicit translation: local JSON v2 code references -> server v1 GUIDs.
/// Room labels never become destinations; entrance/transition IDs stay intact.
class DraftServerMapper {
  static Map<String, dynamic> content(DraftMap draft, String? imageAssetId) {
    final result = <String, dynamic>{
      'schemaVersion': 1, 'imageAssetId': imageAssetId,
      'nodes': [
        for (final n in draft.nodes)
          {
            'id': draft.nodeId(n.code),
            'nodeCode': n.code,
            'name': n.name,
            'x': n.x,
            'y': n.y,
            'nodeType': n.type,
            'sourceNodeId': n.sourceNodeId,
            'existingWayMarkCode': n.wayMarkCode,
            'displayName': n.displayName,
            'searchableAsDestination': n.searchableAsDestination,
            'landmarkNote': n.landmarkNote,
          },
      ],
      'edges': [
        for (final e in draft.edges)
          {
            'id': draft.edgeId(e),
            'fromNodeId': draft.nodeId(e.from),
            'toNodeId': draft.nodeId(e.to),
            'edgeType': e.type,
            'distanceMeters': e.isMeasured ? e.meters : null,
            'isActive': e.isActive,
            'accessibility': 'Unknown',
            'passageVerification': 'Unknown',
          },
      ],
      // Deep copies prevent requests/history documents sharing mutable local state.
      'places': jsonDecode(jsonEncode(draft.places)),
      'transitions': jsonDecode(jsonEncode(draft.transitions)),
    };
    validate(result);
    return result;
  }

  static void validate(Map<String, dynamic> c) {
    if (c['schemaVersion'] != 1) {
      throw const FormatException('Phiên bản graph chưa hỗ trợ.');
    }
    _fields(c, [
      'schemaVersion',
      'imageAssetId',
      'nodes',
      'edges',
      'places',
      'transitions',
    ]);
    if (c['imageAssetId'] != null) draftGuid(c['imageAssetId']);
    final nodes = (c['nodes'] as List).cast<Map<String, dynamic>>();
    final edges = (c['edges'] as List).cast<Map<String, dynamic>>();
    final places = (c['places'] as List).cast<Map<String, dynamic>>();
    final transitions = (c['transitions'] as List).cast<Map<String, dynamic>>();
    if (nodes.length > 2000 ||
        edges.length > 10000 ||
        places.length > 2000 ||
        transitions.length > 1000) {
      throw const FormatException('Graph vượt giới hạn bản nháp.');
    }
    final byId = <String, Map<String, dynamic>>{};
    for (final node in nodes) {
      _fields(node, [
        'id',
        'nodeCode',
        'name',
        'x',
        'y',
        'nodeType',
        'sourceNodeId',
        'existingWayMarkCode',
        'displayName',
        'searchableAsDestination',
        'landmarkNote',
      ]);
      final id = draftGuid(node['id']);
      if (byId.containsKey(id)) {
        throw const FormatException('ID node bị trùng.');
      }
      byId[id] = node;
      if (node['displayName'] != null && !_text(node['displayName'], 200) ||
          node['landmarkNote'] != null && !_text(node['landmarkNote'], 1000) ||
          node['searchableAsDestination'] != null &&
              node['searchableAsDestination'] is! bool) {
        throw const FormatException('Tên điểm đến/Landmark không hợp lệ.');
      }
    }
    final edgeIds = <String>{};
    for (final e in edges) {
      _fields(e, [
        'id',
        'fromNodeId',
        'toNodeId',
        'edgeType',
        'distanceMeters',
        'isActive',
        'accessibility',
        'passageVerification',
      ]);
      if (!edgeIds.add(draftGuid(e['id'])) ||
          !byId.containsKey(draftGuid(e['fromNodeId'])) ||
          !byId.containsKey(draftGuid(e['toNodeId'])) ||
          e['isActive'] is! bool) {
        throw const FormatException('Cạnh thiếu node hoặc trùng ID.');
      }
      _safety(e);
      _meters(e['distanceMeters']);
    }
    final placeIds = <String>{}, codes = <String>{};
    for (final p in places) {
      _fields(p, [
        'id',
        'placeCode',
        'name',
        'label',
        'polygon',
        'entranceNodeIds',
        'accessibility',
      ]);
      if (!placeIds.add(draftGuid(p['id'])) ||
          !_text(p['placeCode'], 100) ||
          !codes.add((p['placeCode'] as String).toLowerCase()) ||
          !_text(p['name'], 200) ||
          p['accessibility'] != 'Unknown') {
        throw const FormatException('Room/Place không hợp lệ.');
      }
      _point(p['label']);
      final polygon = p['polygon'] as List;
      if (polygon.isNotEmpty && (polygon.length < 3 || polygon.length > 100)) {
        throw const FormatException('Polygon không hợp lệ.');
      }
      for (final point in polygon) {
        _point(point);
      }
      final entrances = (p['entranceNodeIds'] as List).map(draftGuid).toList();
      if (entrances.isEmpty ||
          entrances.length > 100 ||
          entrances.toSet().length != entrances.length ||
          entrances.any((id) => byId[id]?['nodeType'] != 'Entrance')) {
        throw const FormatException(
          'Room/Place phải giữ ít nhất một Entrance node hợp lệ.',
        );
      }
    }
    final transitionIds = <String>{};
    for (final t in transitions) {
      _fields(t, [
        'id',
        'fromNodeId',
        'targetDraftId',
        'targetVersion',
        'targetNodeId',
        'edgeType',
        'distanceMeters',
        'accessibility',
        'passageVerification',
      ]);
      final from = byId[draftGuid(t['fromNodeId'])];
      final type = t['edgeType'];
      if (!transitionIds.add(draftGuid(t['id'])) ||
          from == null ||
          !(type == 'Elevator' && from['nodeType'] == 'Elevator' ||
              type == 'Stairs' && from['nodeType'] == 'Stairs' ||
              type == 'Ramp' &&
                  ['Entrance', 'Junction'].contains(from['nodeType']))) {
        throw const FormatException('Tham chiếu chuyển tầng không hợp lệ.');
      }
      draftGuid(t['targetDraftId']);
      draftGuid(t['targetNodeId']);
      draftPositive(t['targetVersion']);
      _safety(t);
      _meters(t['distanceMeters']);
    }
  }

  static bool _text(dynamic v, int max) =>
      v is String &&
      v.trim().isNotEmpty &&
      v == v.trim() &&
      v.length <= max &&
      !RegExp(r'[\x00-\x1F\x7F]').hasMatch(v);
  static void _fields(Map<String, dynamic> j, List<String> allowed) {
    if (j.keys.any((k) => !allowed.contains(k))) {
      throw const FormatException(
        'Graph có trường chưa hỗ trợ. Giữ bản local để tránh mất dữ liệu.',
      );
    }
  }

  static void _point(dynamic p) {
    for (final axis in ['x', 'y']) {
      final v = p[axis];
      if (v is! num || !v.isFinite || v < 0 || v > 1) {
        throw const FormatException('Tọa độ Room/Place không hợp lệ.');
      }
    }
  }

  static void _safety(Map<String, dynamic> j) {
    if (j['accessibility'] != 'Unknown' ||
        j['passageVerification'] != 'Unknown') {
      throw const FormatException(
        'Điều kiện tiếp cận/lối đi phải giữ Unknown.',
      );
    }
  }

  static void _meters(dynamic m) {
    if (m != null &&
        (m is! num ||
            !m.isFinite ||
            m <= 0 ||
            m > 999999999.999 ||
            ((m * 1000) - (m * 1000).round()).abs() > .0001)) {
      throw const FormatException(
        'Khoảng cách mét cần dương và tối đa 3 chữ số thập phân.',
      );
    }
  }

  static DraftMap fromContent(
    Map<String, dynamic> c, {
    required int siteId,
    required int buildingId,
    required RouteFloor floor,
  }) {
    validate(c);
    final draft = DraftMap(
      siteId: siteId,
      buildingId: buildingId,
      floor: floor,
    );
    final codes = <String, String>{};
    for (final n in c['nodes'] as List) {
      final code = n['nodeCode'] as String, id = draftGuid(n['id']);
      draft.putNode(
        DraftNode(
          code,
          n['name'] as String,
          (n['x'] as num).toDouble(),
          (n['y'] as num).toDouble(),
          n['nodeType'] as String,
          sourceNodeId: n['sourceNodeId'] as int?,
          wayMarkCode: n['existingWayMarkCode'] as String?,
          displayName: n['displayName'] as String?,
          searchableAsDestination:
              n['searchableAsDestination'] as bool? ?? false,
          landmarkNote: n['landmarkNote'] as String?,
        ),
      );
      draft.nodeIds[code] = id;
      codes[id] = code;
    }
    for (final e in c['edges'] as List) {
      final edge = DraftEdge(
        codes[draftGuid(e['fromNodeId'])]!,
        codes[draftGuid(e['toNodeId'])]!,
        (e['distanceMeters'] as num?)?.toDouble() ?? 0,
        e['edgeType'] as String,
        isActive: e['isActive'] as bool,
        isMeasured: e['distanceMeters'] != null,
      );
      draft.addEdge(edge);
      draft.edgeIds['${edge.from}\u0000${edge.to}'] = draftGuid(e['id']);
    }
    draft.places.addAll(
      (jsonDecode(jsonEncode(c['places'])) as List)
          .cast<Map<String, dynamic>>(),
    );
    draft.transitions.addAll(
      (jsonDecode(jsonEncode(c['transitions'])) as List)
          .cast<Map<String, dynamic>>(),
    );
    return draft;
  }
}

/// A session is tied to ONE selected Site/Building/Floor, never reused across floors.
/// UI disables editing while awaiting it; load is atomic from the editor's view.
class DraftServerSession {
  DraftServerSession(
    this.api, {
    required this.siteId,
    required this.buildingId,
    required this.floor,
  });
  final MapDraftApiService api;
  final int siteId, buildingId;
  final RouteFloor floor;
  DraftMetadata? metadata;
  String? _assetId;
  FloorPlanAsset? _assetSource;
  bool _uncertainUpload = false;
  DateTime? savedAt;

  void _scope(DraftMetadata m) {
    if (m.siteId != siteId ||
        m.buildingId != buildingId ||
        m.floorId != floor.id ||
        (metadata != null && metadata!.id != m.id)) {
      throw const FormatException(
        'Server trả bản nháp sai Site/Building/Floor.',
      );
    }
  }

  void _local(DraftMap d) {
    if (d.isLocal ||
        d.siteId != siteId ||
        d.buildingId != buildingId ||
        d.floor.id != floor.id) {
      throw const FormatException(
        'Bản nháp local/tầng khác chưa được gắn với tầng server.',
      );
    }
  }

  Future<DraftMap> _read(DraftMetadata m) async {
    _scope(m);
    final c = await api.graph(floor.id, m.id, m.version);
    final draft = DraftServerMapper.fromContent(
      c,
      siteId: siteId,
      buildingId: buildingId,
      floor: floor,
    );
    final assetId = c['imageAssetId'] as String?;
    if (assetId != null) {
      final (bytes, mime) = await api.download(floor.id, assetId);
      draft.image = await FloorPlanAsset.validate(
        bytes,
        mime == 'image/png' ? 'server-floor.png' : 'server-floor.jpg',
        mime,
      );
    }
    // Only mutate session after every graph/image check succeeded.
    metadata = m;
    savedAt = m.updatedAt;
    _assetId = assetId;
    _assetSource = draft.image;
    _uncertainUpload = false;
    return draft;
  }

  Future<DraftMap> load() async => _read(await api.metadata(floor.id));

  Future<void> save(DraftMap draft) async {
    _local(draft);
    // Validate the complete local graph before creating any server revision.
    DraftServerMapper.content(draft, null);
    if (metadata == null) {
      try {
        final existing = await api.metadata(floor.id);
        _scope(existing);
        throw const MapDraftApiException(
          'Tầng đã có bản nháp server. Hãy tải về hoặc xuất backup local trước.',
          status: 409,
          code: 'draft_version_conflict',
        );
      } on MapDraftApiException catch (e) {
        if (e.status != 404 || e.code != 'draft_resource_not_found') rethrow;
      }
      // Create the owner without an image, as required by the image FK/API.
      final created = await api.create(
        floor.id,
        DraftServerMapper.content(draft, null),
      );
      _scope(created);
      if (created.version != 1) {
        throw const FormatException('Phiên bản create không hợp lệ.');
      }
      metadata = created;
      if (draft.image == null) {
        savedAt = created.updatedAt;
        return;
      }
    }
    var asset = draft.image == null ? null : _assetId;
    if (draft.image != null &&
        !(_assetSource?.mime == draft.image!.mime &&
            listEquals(_assetSource?.bytes, draft.image!.bytes))) {
      if (_uncertainUpload) {
        throw const MapDraftApiException(
          'Upload trước chưa rõ kết quả. Mở “Ảnh đã upload” để đối chiếu và chọn asset; không tự upload lặp.',
          code: 'upload_uncertain',
        );
      }
      try {
        final image = await api.upload(
          floor.id,
          draft.image!.bytes,
          draft.image!.mime,
        );
        if (image.width != draft.image!.width ||
            image.height != draft.image!.height) {
          _uncertainUpload = true;
          throw const FormatException('Kích thước ảnh server không khớp.');
        }
        // Retain this binding even when the subsequent save fails.
        _assetId = asset = image.id;
        _assetSource = draft.image;
      } on MapDraftApiException catch (e) {
        if (e.uncertain) _uncertainUpload = true;
        rethrow;
      }
    }
    final previous = metadata!;
    final saved = await api.save(
      floor.id,
      previous.id,
      previous.version,
      DraftServerMapper.content(draft, asset),
    );
    _scope(saved);
    if (saved.version != previous.version + 1) {
      throw const FormatException('Phiên bản lưu không hợp lệ.');
    }
    metadata = saved;
    savedAt = saved.updatedAt;
  }

  Future<List<DraftRevision>> revisions({int? beforeVersion}) async {
    final m = metadata ?? await api.metadata(floor.id);
    _scope(m);
    return api.revisions(floor.id, m.id, beforeVersion: beforeVersion);
  }

  Future<DraftMap> restore(int source) async {
    final previous = metadata;
    if (previous == null) {
      throw const FormatException('Tải bản nháp server trước khi khôi phục.');
    }
    final restored = await api.restore(
      floor.id,
      previous.id,
      previous.version,
      source,
    );
    _scope(restored);
    if (restored.version != previous.version + 1) {
      throw const FormatException('Phiên bản restore không hợp lệ.');
    }
    // If download fails, caller keeps its local map. Reload before another write.
    try {
      return await _read(restored);
    } catch (_) {
      throw MapDraftApiException(
        'Server đã xác nhận khôi phục revision ${restored.version}, nhưng chưa tải được graph/ảnh. '
        'Bản local còn nguyên. Hãy Reload để đối chiếu; không khôi phục lặp.',
        code: 'restore_reload_required',
      );
    }
  }

  Future<FloorPlanAsset> recoverImage(DraftImageMetadata image) async {
    if (image.floorId != floor.id) {
      throw const FormatException('Ảnh thuộc tầng khác.');
    }
    final (bytes, mime) = await api.download(floor.id, image.id);
    final asset = await FloorPlanAsset.validate(
      bytes,
      mime == 'image/png' ? 'recovered.png' : 'recovered.jpg',
      mime,
    );
    if (asset.width != image.width ||
        asset.height != image.height ||
        asset.bytes.length != image.byteLength ||
        mime != image.mime) {
      throw const FormatException('Metadata ảnh không khớp.');
    }
    _assetId = image.id;
    _assetSource = asset;
    _uncertainUpload = false;
    return asset;
  }
}
