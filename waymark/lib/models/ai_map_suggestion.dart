import 'dart:convert';

/// Untrusted, unverified image observations. Never routing/accessibility proof.
class AiMapSuggestion {
  const AiMapSuggestion({
    required this.id,
    required this.name,
    required this.type,
    required this.x,
    required this.y,
    required this.destination,
    required this.confidence,
    required this.uncertainty,
    this.landmarkNote,
  });
  final String id, name, type, uncertainty;
  final double x, y, confidence;
  final bool destination;
  final String? landmarkNote;
  static const types = [
    'Entrance',
    'Junction',
    'Destination',
    'Elevator',
    'Stairs',
  ];

  static AiMapSuggestion parse(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Node không hợp lệ.');
    }
    String text(String key, int max) {
      final s = value[key];
      if (s is! String ||
          s.trim().isEmpty ||
          s.length > max ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(s)) {
        throw FormatException('Trường $key không hợp lệ.');
      }
      return s.trim();
    }

    double number(String key) {
      final n = value[key];
      if (n is! num || !n.isFinite || n < 0 || n > 1) {
        throw FormatException('$key phải nằm trong 0–1.');
      }
      return n.toDouble();
    }

    final type = text('nodeType', 30);
    if (!types.contains(type) || value['suggestedAsDestination'] is! bool) {
      throw const FormatException('Loại node hoặc cờ điểm đến không hợp lệ.');
    }
    final note = value['landmarkNote'] == null
        ? null
        : text('landmarkNote', 500);
    return AiMapSuggestion(
      id: text('proposedNodeId', 100),
      name: text('displayName', 200),
      type: type,
      x: number('normalizedX'),
      y: number('normalizedY'),
      destination: value['suggestedAsDestination'] as bool,
      confidence: number('confidence'),
      uncertainty: text('uncertainty', 1000),
      landmarkNote: note,
    );
  }

  Map<String, Object?> toJson() => {
    'proposedNodeId': id,
    'displayName': name,
    'nodeType': type,
    'normalizedX': x,
    'normalizedY': y,
    'suggestedAsDestination': destination,
    'confidence': confidence,
    'uncertainty': uncertainty,
    'landmarkNote': landmarkNote,
  };
}

class AiMapResult {
  const AiMapResult(this.nodes, this.rejected);
  final List<AiMapSuggestion> nodes;
  final int rejected;
  static AiMapResult parse(String content) {
    if (content.length > 128 * 1024) {
      throw const FormatException('Phản hồi AI quá lớn.');
    }
    var source = content.trim();
    if (source.startsWith('```json') && source.endsWith('```')) {
      source = source.substring(7, source.length - 3).trim();
    }
    final json = jsonDecode(source);
    if (json is! Map<String, dynamic> ||
        json['nodes'] is! List ||
        (json['nodes'] as List).length > 40) {
      throw const FormatException(
        'AI phải trả object nodes, tối đa 40 đề xuất.',
      );
    }
    final nodes = <AiMapSuggestion>[], ids = <String>{};
    var rejected = 0;
    for (final item in json['nodes'] as List) {
      try {
        final node = AiMapSuggestion.parse(item);
        if (!ids.add(node.id)) throw const FormatException('Trùng ID đề xuất.');
        nodes.add(node);
      } on FormatException {
        rejected++;
      }
    }
    if (nodes.isEmpty && rejected > 0) {
      throw const FormatException('Không có đề xuất AI hợp lệ.');
    }
    return AiMapResult(List.unmodifiable(nodes), rejected);
  }
}
