import 'dart:ui';

import 'tracking_graph.dart';

enum PositionKind { nodeAnchor, onEdge, floorTransition, unknown }

enum PositionSource { qr, manualExperiment, pdr }

enum PositionConfidence {
  confirmedAtScan,
  manualConfirmation,
  estimated,
  uncertain,
}

enum TrackingStatus {
  needsAnchor,
  anchored,
  calibrating,
  tracking,
  uncertain,
  relocalizing,
  paused,
  permissionDenied,
  sensorUnavailable,
  finished,
  failed,
}

class IndoorPosition {
  const IndoorPosition({
    required this.map,
    required this.kind,
    required this.floorKey,
    required this.source,
    required this.confidence,
    this.nodeId,
    this.edgeId,
    this.progressMeters = 0,
    this.point,
    this.targetFloorKey,
    this.phoneYaw,
    this.travelDirection,
    this.timestampNs = 0,
    this.generation = 0,
    this.reason = '',
    this.anchorConfirmedAtUtc,
  });
  final TrackingMapKey map;
  final PositionKind kind;
  final String floorKey;
  final String? nodeId, edgeId, targetFloorKey;
  final double progressMeters;
  final Offset? point;
  final double? phoneYaw, travelDirection;
  final int timestampNs, generation;
  final PositionSource source;
  final PositionConfidence confidence;
  final String reason;

  /// Client confirmation time for non-sensor anchors; never subtracted from
  /// Android monotonic nanoseconds or used as sensor time.
  final DateTime? anchorConfirmedAtUtc;

  IndoorPosition withConfidence(PositionConfidence confidence, String reason) =>
      IndoorPosition(
        map: map,
        kind: kind,
        floorKey: floorKey,
        source: source,
        confidence: confidence,
        reason: reason,
        nodeId: nodeId,
        edgeId: edgeId,
        progressMeters: progressMeters,
        point: point,
        targetFloorKey: targetFloorKey,
        phoneYaw: phoneYaw,
        travelDirection: travelDirection,
        timestampNs: timestampNs,
        generation: generation,
        anchorConfirmedAtUtc: anchorConfirmedAtUtc,
      );
}

class VerifiedTrackingAnchor {
  const VerifiedTrackingAnchor(
    this.map,
    this.nodeId,
    this.floorKey,
    this.source,
  );
  final TrackingMapKey map;
  final String nodeId, floorKey;
  final PositionSource source;

  IndoorPosition position(TrackingGraph graph, {int generation = 0}) {
    final node = graph.nodes[nodeId];
    if (map != graph.key || node == null || node.floorKey != floorKey) {
      throw const FormatException('Anchor khác map/version/node/floor.');
    }
    return IndoorPosition(
      map: map,
      kind: PositionKind.nodeAnchor,
      floorKey: floorKey,
      nodeId: nodeId,
      point: node.point,
      source: source,
      generation: generation,
      confidence: source == PositionSource.qr
          ? PositionConfidence.confirmedAtScan
          : PositionConfidence.manualConfirmation,
      anchorConfirmedAtUtc: DateTime.now().toUtc(),
    );
  }
}
