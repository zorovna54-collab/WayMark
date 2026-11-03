import 'dart:convert';

import 'ai_map_suggestion.dart';

enum AiReviewStatus { pending, accepted, rejected }

enum AiEdgeDirection { forward, reverse, both }

String aiProposalText(Object? value, String field, [int max = 1000]) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > max ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw FormatException('$field không hợp lệ.');
  }
  return value.trim();
}

void _keys(Map<String, dynamic> value, Set<String> allowed) {
  if (value.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('AI trả trường ngoài schema.');
  }
}

String _id(Object? value) {
  final id = aiProposalText(value, 'Temporary ID', 64);
  if (!RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(id)) {
    throw const FormatException('Temporary ID phải là mã chữ thường riêng.');
  }
  return id;
}

double _unit(Object? value) {
  if (value is! num || !value.isFinite || value < 0 || value > 1) {
    throw const FormatException('Tọa độ/confidence phải hữu hạn trong 0–1.');
  }
  return value.toDouble();
}

class AiGraphNode {
  const AiGraphNode(this.node, this.floorId, this.evidence);
  final AiMapSuggestion node;
  final String floorId, evidence;
}

class AiGraphEdge {
  const AiGraphEdge({
    required this.id,
    required this.from,
    required this.to,
    required this.floorId,
    required this.type,
    required this.evidence,
    required this.uncertainty,
    required this.directionHint,
    this.confidence,
  });
  final String id,
      from,
      to,
      floorId,
      type,
      evidence,
      uncertainty,
      directionHint;
  final double? confidence;
  static const types = ['Corridor', 'Door', 'Ramp', 'Stairs', 'Elevator'];
}

class AiUncertainArea {
  const AiUncertainArea(this.name, this.x, this.y, this.reason);
  final String name, reason;
  final double x, y;
}

/// Proposal schema is independent of persisted Draft JSON v2/v3.
/// IDs beginning existing: refer ONLY to the supplied floor's stable GUIDs.
class AiGraphProposal {
  AiGraphProposal({
    required this.floorId,
    required List<AiGraphNode> nodes,
    required List<AiGraphEdge> edges,
    required List<AiUncertainArea> areas,
    this.discarded = 0,
  }) : nodes = List.unmodifiable(nodes),
       edges = List.unmodifiable(edges),
       areas = List.unmodifiable(areas);
  final String floorId;
  final List<AiGraphNode> nodes;
  final List<AiGraphEdge> edges;
  final List<AiUncertainArea> areas;
  final int discarded;

  static AiGraphProposal parse(
    String content, {
    required String floorId,
    required Set<String> existingRefs,
  }) {
    if (content.length > 128 * 1024) {
      throw const FormatException('Proposal quá lớn.');
    }
    var source = content.trim();
    if (source.startsWith('```json') && source.endsWith('```')) {
      source = source.substring(7, source.length - 3).trim();
    }
    final root = jsonDecode(source);
    if (root is! Map<String, dynamic>) {
      throw const FormatException('Cần JSON object.');
    }
    _keys(root, {
      'schemaVersion',
      'floorId',
      'nodes',
      'edges',
      'uncertainAreas',
    });
    if (root['schemaVersion'] != 2 ||
        root['floorId'] != floorId ||
        root['nodes'] is! List ||
        root['edges'] is! List ||
        root['uncertainAreas'] is! List ||
        (root['nodes'] as List).length > 40 ||
        (root['edges'] as List).length > 80 ||
        (root['uncertainAreas'] as List).length > 20) {
      throw const FormatException(
        'Proposal sai schema/tầng hoặc vượt giới hạn.',
      );
    }
    final nodes = <AiGraphNode>[],
        edges = <AiGraphEdge>[],
        areas = <AiUncertainArea>[];
    final nodeIds = <String>{}, edgeIds = <String>{}, pairs = <String>{};
    var discarded = 0;
    for (final raw in root['nodes'] as List) {
      try {
        if (raw is! Map<String, dynamic>) throw const FormatException();
        _keys(raw, {
          'proposedNodeId',
          'displayName',
          'nodeType',
          'normalizedX',
          'normalizedY',
          'suggestedAsDestination',
          'landmarkNote',
          'confidence',
          'uncertainty',
          'floorId',
          'evidence',
        });
        final id = _id(raw['proposedNodeId']);
        if (raw['floorId'] != floorId || nodeIds.contains(id)) {
          throw const FormatException();
        }
        final node = AiMapSuggestion.parse(raw);
        final evidence = aiProposalText(raw['evidence'], 'Evidence');
        nodeIds.add(id);
        nodes.add(AiGraphNode(node, floorId, evidence));
      } on FormatException {
        discarded++;
      }
    }
    final validRefs = {...existingRefs, ...nodeIds};
    for (final raw in root['edges'] as List) {
      try {
        if (raw is! Map<String, dynamic>) throw const FormatException();
        _keys(raw, {
          'proposedEdgeId',
          'sourceNodeId',
          'targetNodeId',
          'floorId',
          'edgeType',
          'evidence',
          'uncertainty',
          'confidence',
          'directionHint',
          'distanceMeters',
        });
        final id = _id(raw['proposedEdgeId']);
        final from = aiProposalText(raw['sourceNodeId'], 'Source', 120);
        final to = aiProposalText(raw['targetNodeId'], 'Target', 120);
        final type = aiProposalText(raw['edgeType'], 'Edge type', 30);
        final hint = aiProposalText(raw['directionHint'], 'Direction hint', 30);
        if (raw['floorId'] != floorId ||
            !validRefs.contains(from) ||
            !validRefs.contains(to) ||
            from == to ||
            !AiGraphEdge.types.contains(type) ||
            !['Unknown', 'FromTo', 'Both'].contains(hint) ||
            raw['distanceMeters'] != null ||
            edgeIds.contains(id) ||
            pairs.contains('$from\u0000$to')) {
          throw const FormatException();
        }
        final edge = AiGraphEdge(
          id: id,
          from: from,
          to: to,
          floorId: floorId,
          type: type,
          evidence: aiProposalText(raw['evidence'], 'Evidence'),
          uncertainty: aiProposalText(raw['uncertainty'], 'Uncertainty'),
          directionHint: hint,
          confidence: raw['confidence'] == null
              ? null
              : _unit(raw['confidence']),
        );
        edges.add(edge);
        edgeIds.add(id);
        pairs.add('$from\u0000$to');
      } on FormatException {
        discarded++;
      }
    }
    for (final raw in root['uncertainAreas'] as List) {
      try {
        if (raw is! Map<String, dynamic>) throw const FormatException();
        _keys(raw, {'label', 'normalizedX', 'normalizedY', 'reason'});
        areas.add(
          AiUncertainArea(
            aiProposalText(raw['label'], 'Area', 200),
            _unit(raw['normalizedX']),
            _unit(raw['normalizedY']),
            aiProposalText(raw['reason'], 'Reason'),
          ),
        );
      } on FormatException {
        discarded++;
      }
    }
    if (nodes.isEmpty && edges.isEmpty && areas.isEmpty && discarded > 0) {
      throw const FormatException('Không có proposal hợp lệ.');
    }
    return AiGraphProposal(
      floorId: floorId,
      nodes: nodes,
      edges: edges,
      areas: areas,
      discarded: discarded,
    );
  }
}
