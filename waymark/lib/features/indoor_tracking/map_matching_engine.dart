import 'dart:math' as math;

import 'indoor_position.dart';
import 'pdr_engine.dart';
import 'tracking_graph.dart';

class MatchResult {
  const MatchResult(
    this.position,
    this.reason, {
    this.movedMeters = 0,
    this.overshoot = 0,
  });
  final IndoorPosition position;
  final String reason;
  final double movedMeters, overshoot;
}

/// Conservative full-topology matcher. Intended destination/route is never
/// an input to branch selection. Unknown geometry remains a user decision.
class MapMatchingEngine {
  MapMatchingEngine(this.graph);
  final TrackingGraph graph;
  final confirmedStraightEdges = <String>{};
  static const headingTolerance =
      math.pi / 5; // 36°, a heuristic, not accuracy.

  List<TrackingEdge> candidates(IndoorPosition position) =>
      position.nodeId == null ? const [] : graph.outgoing(position.nodeId!);

  MatchResult advance(IndoorPosition position, MovementObservation motion) {
    if (position.map != graph.key ||
        motion.meters <= 0 ||
        !motion.meters.isFinite) {
      return MatchResult(position, 'mapOrMotionMismatch');
    }
    if (position.kind == PositionKind.floorTransition ||
        position.kind == PositionKind.unknown) {
      return MatchResult(position, 'needsAnchor');
    }
    if (position.kind == PositionKind.nodeAnchor) {
      final possible = graph
          .outgoing(position.nodeId!)
          .where(
            (e) =>
                e.bearing == null ||
                angleDifference(e.bearing!, motion.travelDirection) <=
                    headingTolerance,
          )
          .toList();
      if (possible.length != 1 ||
          !confirmedStraightEdges.contains(possible.single.id) ||
          !possible.single.geometryEligible) {
        return MatchResult(
          position.withConfidence(
            PositionConfidence.uncertain,
            'junctionConfirmation',
          ),
          'junctionConfirmation',
        );
      }
      return advance(
        onEdge(possible.single, generation: motion.generation),
        motion,
      );
    }
    final edge = graph.edges[position.edgeId];
    if (edge == null ||
        !edge.active ||
        !edge.geometryEligible ||
        !confirmedStraightEdges.contains(edge.id)) {
      return MatchResult(
        position.withConfidence(
          PositionConfidence.uncertain,
          'unsupportedGeometry',
        ),
        'unsupportedGeometry',
      );
    }
    final forward =
        angleDifference(motion.travelDirection, edge.bearing!) <=
        headingTolerance;
    final backward =
        angleDifference(motion.travelDirection, edge.bearing! + math.pi) <=
        headingTolerance;
    if (!forward && !backward) {
      return MatchResult(
        position.withConfidence(
          PositionConfidence.uncertain,
          'headingConflict',
        ),
        'headingConflict',
      );
    }
    final signed = forward ? motion.meters : -motion.meters;
    final next = position.progressMeters + signed;
    final clipped = next.clamp(0.0, edge.meters);
    final moved = (clipped - position.progressMeters).abs();
    final reverseAllowed = graph.edgeBetween(edge.to, edge.from) != null;
    if (next >= edge.meters || next <= 0) {
      final node = graph.nodes[next >= edge.meters ? edge.to : edge.from]!;
      return MatchResult(
        IndoorPosition(
          map: graph.key,
          kind: PositionKind.nodeAnchor,
          floorKey: node.floorKey,
          nodeId: node.id,
          point: node.point,
          source: PositionSource.pdr,
          confidence: PositionConfidence.uncertain,
          timestampNs: motion.timestampNs,
          generation: motion.generation,
          phoneYaw: motion.phoneYaw,
          travelDirection: motion.travelDirection,
          reason: 'candidateNodeConfirm',
        ),
        'candidateNodeConfirm',
        movedMeters: moved,
        overshoot: (next - clipped).abs(),
      );
    }
    final reason = backward && !reverseAllowed
        ? 'againstOneWay'
        : backward
        ? 'reverse'
        : 'estimated';
    return MatchResult(
      IndoorPosition(
        map: graph.key,
        kind: PositionKind.onEdge,
        floorKey: graph.nodes[edge.from]!.floorKey,
        edgeId: edge.id,
        progressMeters: clipped,
        point: graph.interpolate(edge.id, clipped),
        source: PositionSource.pdr,
        confidence: motion.manualDirection || reason == 'againstOneWay'
            ? PositionConfidence.uncertain
            : PositionConfidence.estimated,
        timestampNs: motion.timestampNs,
        generation: motion.generation,
        phoneYaw: motion.phoneYaw,
        travelDirection: motion.travelDirection,
        reason: reason,
      ),
      reason,
      movedMeters: moved,
    );
  }

  IndoorPosition onEdge(
    TrackingEdge edge, {
    int generation = 0,
    PositionSource source = PositionSource.manualExperiment,
    PositionConfidence confidence = PositionConfidence.manualConfirmation,
  }) => IndoorPosition(
    map: graph.key,
    kind: PositionKind.onEdge,
    floorKey: graph.nodes[edge.from]!.floorKey,
    edgeId: edge.id,
    progressMeters: 0,
    point: graph.nodes[edge.from]!.point,
    source: source,
    confidence: confidence,
    generation: generation,
  );
}
