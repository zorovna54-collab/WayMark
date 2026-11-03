import 'dart:convert';

import '../../models/ai_graph_proposal.dart';
import '../../models/ai_map_suggestion.dart';
import 'draft_map.dart';
import 'floor_plan_asset.dart';

String aiFloorKey(DraftMap draft) =>
    draft.localWorkspaceId ??
    'floor:${draft.siteId}/${draft.buildingId}/${draft.floor.id}';

String _graphStamp(DraftMap draft) => jsonEncode({
  'nodes': draft.nodes.map((n) => n.toJson()).toList(),
  'edges': draft.edges.map((e) => e.toJson()).toList(),
  'nodeIds': draft.nodeIds,
  'edgeIds': draft.edgeIds,
  'places': draft.places,
  'transitions': draft.transitions,
});

class AiExistingNode {
  const AiExistingNode(
    this.ref,
    this.code,
    this.label,
    this.type,
    this.x,
    this.y,
  );
  final String ref, code, label, type;
  final double x, y;
  Map<String, Object> toJson() => {
    'id': ref,
    'displayName': label,
    'nodeType': type,
    'normalizedX': x,
    'normalizedY': y,
  };
}

/// Detached request context. Capturing does not assign IDs or mutate a Draft.
class AiGraphInput {
  AiGraphInput._(
    this.projectId,
    this.floorId,
    this.image,
    this.stamp,
    List<AiExistingNode> nodes,
    Set<String> pairs,
  ) : existing = List.unmodifiable(nodes),
      existingPairs = Set.unmodifiable(pairs);
  final String projectId, floorId, stamp;
  final FloorPlanAsset image;
  final List<AiExistingNode> existing;
  final Set<String> existingPairs;
  Set<String> get existingRefs => existing.map((n) => n.ref).toSet();
  factory AiGraphInput.capture(DraftMap draft, {required String projectId}) {
    final image = draft.image;
    if (image == null) throw const FormatException('Chọn ảnh tầng trước.');
    final nodes = <AiExistingNode>[];
    for (final (i, n) in draft.nodes.indexed) {
      final id = draft.nodeIds[n.code];
      if (id == null) {
        throw const FormatException(
          'Node thiếu stable GUID; cần mở lại draft.',
        );
      }
      nodes.add(
        AiExistingNode(
          'existing:$id',
          n.code,
          n.listLabel(i),
          n.type,
          n.x,
          n.y,
        ),
      );
    }
    return AiGraphInput._(
      projectId,
      aiFloorKey(draft),
      image,
      _graphStamp(draft),
      nodes,
      draft.edges.map((e) => '${e.from}\u0000${e.to}').toSet(),
    );
  }
  void ensureCurrent(DraftMap draft, String project) {
    if (project != projectId ||
        aiFloorKey(draft) != floorId ||
        !identical(image, draft.image) ||
        _graphStamp(draft) != stamp) {
      throw const FormatException(
        'Project/tầng/ảnh/graph đã đổi. Không áp dụng kết quả AI cũ.',
      );
    }
  }
}

class AiReviewedEdge {
  const AiReviewedEdge(this.proposal, this.meters, this.direction);
  final AiGraphEdge proposal;
  final double meters;
  final AiEdgeDirection direction;
  Iterable<(String, String)> get pairs sync* {
    if (direction != AiEdgeDirection.reverse) {
      yield (proposal.from, proposal.to);
    }
    if (direction != AiEdgeDirection.forward) {
      yield (proposal.to, proposal.from);
    }
  }
}

class AiGraphBatch {
  AiGraphBatch(this.input, List<AiGraphNode> nodes, List<AiReviewedEdge> edges)
    : nodes = List.unmodifiable(nodes),
      edges = List.unmodifiable(edges);
  final AiGraphInput input;
  final List<AiGraphNode> nodes;
  final List<AiReviewedEdge> edges;
  int get directedEdges => edges.fold(
    0,
    (n, e) => n + (e.direction == AiEdgeDirection.both ? 2 : 1),
  );
}

/// Review is detached; Accept is only a queue. No Draft or API reference here.
class AiGraphReview {
  AiGraphReview(this.input, this.proposal)
    : nodes = [...proposal.nodes],
      edges = [...proposal.edges] {
    if (input.floorId != proposal.floorId) {
      throw const FormatException('Sai tầng review.');
    }
    if (nodes.map((n) => n.node.id).toSet().length != nodes.length ||
        edges.map((e) => e.id).toSet().length != edges.length ||
        nodes.any(
          (n) =>
              n.floorId != input.floorId ||
              !RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(n.node.id),
        ) ||
        edges.any((e) => e.floorId != input.floorId)) {
      throw const FormatException(
        'ID trùng hoặc proposal không thuộc tầng này.',
      );
    }
  }
  final AiGraphInput input;
  final AiGraphProposal proposal;
  final List<AiGraphNode> nodes;
  final List<AiGraphEdge> edges;
  final Map<String, AiReviewStatus> nodeStatuses = {}, edgeStatuses = {};
  final Map<String, AiReviewedEdge> reviewedEdges = {};
  AiReviewStatus nodeStatus(String id) =>
      nodeStatuses[id] ?? AiReviewStatus.pending;
  AiReviewStatus edgeStatus(String id) =>
      edgeStatuses[id] ?? AiReviewStatus.pending;
  bool endpointReady(String ref) =>
      input.existingRefs.contains(ref) ||
      nodes.any(
        (n) => n.node.id == ref && nodeStatus(ref) == AiReviewStatus.accepted,
      );
  void _invalidate(String node) {
    for (final e in edges.where((e) => e.from == node || e.to == node)) {
      reviewedEdges.remove(e.id);
      edgeStatuses[e.id] = AiReviewStatus.pending;
    }
  }

  void acceptNode(String id) {
    if (!nodes.any((n) => n.node.id == id)) {
      throw const FormatException('Thiếu proposal node.');
    }
    nodeStatuses[id] = AiReviewStatus.accepted;
  }

  void rejectNode(String id) {
    _invalidate(id);
    nodeStatuses[id] = AiReviewStatus.rejected;
  }

  void editNode(AiGraphNode revised) {
    final index = nodes.indexWhere((n) => n.node.id == revised.node.id);
    if (index < 0 || revised.floorId != input.floorId) {
      throw const FormatException('Sai node/tầng.');
    }
    final parsed = AiMapSuggestion.parse(revised.node.toJson());
    nodes[index] = AiGraphNode(
      parsed,
      revised.floorId,
      aiProposalText(revised.evidence, 'Evidence'),
    );
    nodeStatuses[parsed.id] = AiReviewStatus.pending;
    _invalidate(parsed.id);
  }

  void rejectEdge(String id) {
    reviewedEdges.remove(id);
    edgeStatuses[id] = AiReviewStatus.rejected;
  }

  void acceptEdge(
    String id, {
    double? meters,
    AiEdgeDirection? direction,
    required bool confirmed,
  }) {
    final e = edges.where((e) => e.id == id).firstOrNull;
    if (e == null) throw const FormatException('Thiếu proposal Edge.');
    if (!confirmed ||
        direction == null ||
        meters == null ||
        !meters.isFinite ||
        meters <= 0 ||
        meters > 999999999.999 ||
        !endpointReady(e.from) ||
        !endpointReady(e.to)) {
      throw const FormatException(
        'Cần duyệt node hai đầu, xác nhận hướng và nhập mét hợp lệ.',
      );
    }
    final revised = AiReviewedEdge(e, meters, direction);
    _validateEdges([
      ...reviewedEdges.values.where((r) => r.proposal.id != id),
      revised,
    ]);
    reviewedEdges[id] = revised;
    edgeStatuses[id] = AiReviewStatus.accepted;
  }

  void editEdge(
    String id, {
    required String from,
    required String to,
    required String type,
  }) {
    final index = edges.indexWhere((e) => e.id == id);
    final valid = {...input.existingRefs, ...nodes.map((n) => n.node.id)};
    if (index < 0 ||
        !valid.contains(from) ||
        !valid.contains(to) ||
        from == to ||
        !AiGraphEdge.types.contains(type)) {
      throw const FormatException('Hai đầu cùng tầng/loại cạnh không hợp lệ.');
    }
    final old = edges[index];
    edges[index] = AiGraphEdge(
      id: id,
      from: from,
      to: to,
      floorId: input.floorId,
      type: type,
      evidence: old.evidence,
      uncertainty: old.uncertainty,
      directionHint: old.directionHint,
      confidence: old.confidence,
    );
    reviewedEdges.remove(id);
    edgeStatuses[id] = AiReviewStatus.pending;
  }

  void _validateEdges(Iterable<AiReviewedEdge> selected) {
    final pairs = <String>{};
    final existingCodes = {for (final n in input.existing) n.ref: n.code};
    for (final e in selected) {
      if (e.proposal.floorId != input.floorId ||
          !endpointReady(e.proposal.from) ||
          !endpointReady(e.proposal.to)) {
        throw const FormatException('Edge cần node đã duyệt trên đúng tầng.');
      }
      for (final (from, to) in e.pairs) {
        if (from == to ||
            !pairs.add('$from\u0000$to') ||
            input.existingPairs.contains(
              '${existingCodes[from]}\u0000${existingCodes[to]}',
            )) {
          throw const FormatException('Cạnh trùng hoặc self-loop.');
        }
      }
    }
  }

  AiGraphBatch batch() {
    final accepted = nodes
        .where((n) => nodeStatus(n.node.id) == AiReviewStatus.accepted)
        .toList();
    _validateEdges(reviewedEdges.values);
    return AiGraphBatch(input, accepted, reviewedEdges.values.toList());
  }
}

class AiGraphApplied {
  AiGraphApplied._(
    this.input,
    this.nodes,
    this.edges,
    this.afterStamp,
    this.wasReviewed,
  );
  final AiGraphInput input;
  final List<DraftNode> nodes;
  final List<DraftEdge> edges;
  final String afterStamp;
  final bool wasReviewed;
  void undo(DraftMap draft, {required String projectId}) {
    if (projectId != input.projectId ||
        aiFloorKey(draft) != input.floorId ||
        !identical(draft.image, input.image) ||
        _graphStamp(draft) != afterStamp) {
      throw const FormatException(
        'Draft đã đổi sau AI; không hoàn tác đè lên thay đổi mới.',
      );
    }
    for (final e in edges.reversed) {
      draft.removeEdge(e);
    }
    for (final n in nodes.reversed) {
      draft.removeNode(n.code);
    }
    draft.layoutReviewed = wasReviewed;
  }
}

/// Validate a complete candidate graph before any mutation of the original.
AiGraphApplied applyAiGraphBatch(
  DraftMap draft,
  AiGraphBatch batch, {
  required String projectId,
}) {
  batch.input.ensureCurrent(draft, projectId);
  final review = AiGraphReview(
    batch.input,
    AiGraphProposal(
      floorId: batch.input.floorId,
      nodes: batch.nodes,
      edges: batch.edges.map((e) => e.proposal).toList(),
      areas: const [],
    ),
  );
  for (final n in batch.nodes) {
    review.editNode(n);
    review.acceptNode(n.node.id);
  }
  for (final e in batch.edges) {
    review.acceptEdge(
      e.proposal.id,
      meters: e.meters,
      direction: e.direction,
      confirmed: true,
    );
  }
  final checked = review.batch();
  if (draft.nodes.length + checked.nodes.length > 2000 ||
      draft.edges.length + checked.directedEdges > 10000) {
    throw const FormatException('AI vượt giới hạn node/edge của draft.');
  }
  final candidate = DraftMap(
    siteId: draft.siteId,
    buildingId: draft.buildingId,
    floor: draft.floor,
    localWorkspaceId: draft.localWorkspaceId,
    localSiteName: draft.localSiteName,
    localBuildingName: draft.localBuildingName,
  );
  for (final n in draft.nodes) {
    candidate.putNode(n);
  }
  for (final e in draft.edges) {
    candidate.addEdge(e);
  }
  final refs = {for (final n in batch.input.existing) n.ref: n.code};
  final newNodes = <DraftNode>[], newEdges = <DraftEdge>[];
  for (final proposed in checked.nodes) {
    final n = proposed.node;
    final code = 'AI-${newDraftGuid()}';
    final node = DraftNode(
      code,
      n.name,
      n.x,
      n.y,
      n.type,
      displayName: n.name,
      searchableAsDestination: n.destination,
      landmarkNote:
          'AI chưa xác minh vị trí/lối đi.${n.landmarkNote == null ? '' : ' ${n.landmarkNote}'}',
    );
    candidate.putNode(node);
    refs[n.id] = code;
    newNodes.add(node);
  }
  for (final e in checked.edges) {
    for (final (from, to) in e.pairs) {
      final edge = DraftEdge(refs[from]!, refs[to]!, e.meters, e.proposal.type);
      candidate.addEdge(edge);
      newEdges.add(edge);
    }
  }
  final wasReviewed = draft.layoutReviewed;
  for (final node in newNodes) {
    draft.putNode(node);
  }
  for (final edge in newEdges) {
    draft.addEdge(edge);
  }
  return AiGraphApplied._(
    batch.input,
    newNodes,
    newEdges,
    _graphStamp(draft),
    wasReviewed,
  );
}
