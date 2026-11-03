import 'dart:convert';

import '../../services/map_draft_api_service.dart' show draftGuid;

typedef SavedQrNode = ({String id, String floorKey, String label});

/// Reads only the saved API contract. Local codes/labels are never QR identities.
List<SavedQrNode> savedQrNodes(Map<String, dynamic>? document) => [
  for (final f in ((document?['content'] as Map?)?['floors'] as List? ?? []))
    for (final (i, n) in (f['content']['nodes'] as List? ?? []).indexed)
      (
        id: draftGuid(n['id']),
        floorKey: draftGuid(f['id']),
        label:
            '${f['name']} • N${(i + 1).toString().padLeft(2, '0')} · ${n['displayName'] ?? n['name']}',
      ),
];

// Object key order and JSON number formatting can differ between Dart and .NET.
// Ignore only server-owned personal metadata; preserve all graph/asset identities.
bool sameProjectGraph(Map<String, dynamic> a, Map<String, dynamic> b) {
  const identities = {
    'id',
    'imageAssetId',
    'fromNodeId',
    'toNodeId',
    'fromFloor',
    'toFloor',
    'fromNode',
    'toNode',
    'entranceNodeIds',
    'targetDraftId',
    'targetNodeId',
  };
  Object? canonical(Object? value, [String? field]) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: canonical(value[key], key)};
    }
    if (value is List) {
      return value.map((item) => canonical(item, field)).toList();
    }
    if (value is num) return value.toDouble();
    if (value is String &&
        identities.contains(field) &&
        RegExp(
          r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
        ).hasMatch(value)) {
      return value.toLowerCase();
    }
    return value;
  }

  return jsonEncode(canonical({...a}..remove('info'))) ==
      jsonEncode(canonical({...b}..remove('info')));
}
