import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/indoor_tracking/pdr_engine.dart';
import 'package:waymark/features/indoor_tracking/map_matching_engine.dart';
import 'package:waymark/features/indoor_tracking/indoor_position.dart';
import 'package:waymark/features/indoor_tracking/sensors/sensor_models.dart';

import 'support/fake_sensor_provider.dart';
import 'live_tracking_graph_test.dart' show trackingFixture;

SensorSample rotation(
  double yaw,
  int timestamp, {
  int generation = 1,
  int accuracy = 3,
}) => SensorSample.decode({
  ...samplePayload(
    SensorKind.rotationVector,
    timestamp: timestamp,
    generation: generation,
    sequence: timestamp,
    values: [0, 0, -math.sin(yaw / 2), math.cos(yaw / 2), -1],
  ),
  'accuracy': accuracy,
});
SensorSample step(int timestamp, {int generation = 1}) => SensorSample.decode(
  samplePayload(
    SensorKind.stepDetector,
    timestamp: timestamp,
    generation: generation,
    sequence: timestamp,
  ),
);

PdrEngine calibratedEngine() {
  final engine = PdrEngine()..beginGeneration(1);
  engine.stride = StrideCalibration(.5);
  engine.ingest(rotation(0, 100));
  engine.heading = HeadingCalibration.align(engine.latestHeading!, 0);
  return engine;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Zero steps/rotation-only/counter never displace; N detector events use confirmed stride', () {
    final e = calibratedEngine();
    expect(e.ingest(rotation(.2, 150)).motion, isNull);
    expect(
      e
          .ingest(
            SensorSample.decode(
              samplePayload(
                SensorKind.stepCounter,
                timestamp: 160,
                values: [200],
              ),
            ),
          )
          .motion,
      isNull,
    );
    var distance = 0.0;
    for (var i = 0; i < 10; i++) {
      distance += e.ingest(step(200 + i)).motion!.meters;
    }
    expect(distance, 5);
    expect(e.acceptedSteps, 10);
  });
  test('Duplicate, same-sensor backwards, wrong generation and calibration baseline are fenced', () {
    final e = calibratedEngine();
    expect(e.ingest(step(200)).motion, isNotNull);
    expect(e.ingest(step(200)).motion, isNull);
    expect(e.ingest(step(199)).motion, isNull);
    expect(e.ingest(step(300, generation: 2)).motion, isNull);
    e.fenceBaseline();
    expect(e.ingest(step(200)).motion, isNull);
    e.beginGeneration(2);
    expect(e.ingest(step(201)).motion, isNull);
    expect(e.ingest(step(400, generation: 2)).reason, 'staleOrientation');
  });
  test('Missing, future-only, stale and unreliable orientation do not create movement', () {
    final e = PdrEngine()
      ..beginGeneration(1)
      ..stride = StrideCalibration(.6);
    expect(e.ingest(step(100)).reason, 'staleOrientation');
    e.ingest(rotation(0, 1000));
    e.heading = HeadingCalibration.align(e.latestHeading!, 0);
    expect(
      e.ingest(step(200)).motion,
      isNull,
    ); // Future orientation not applied retroactively.
    expect(e.ingest(step(2000001000)).reason, 'staleOrientation');
    e.ingest(rotation(0, 2000001100, accuracy: 0));
    expect(e.ingest(step(2000001200)).reason, 'headingRequired');
  });
  test('Map alignment is relative, does not assume magnetic north equals map north', () {
    final e = calibratedEngine();
    e.heading = HeadingCalibration.align(e.latestHeading!, math.pi / 2);
    e.ingest(rotation(math.pi / 2, 150));
    expect(
      angleDifference(e.ingest(step(200)).motion!.travelDirection, math.pi),
      closeTo(0, 1e-8),
    );
  });
  test('Invalid stride/walk/pose calibration is rejected; manual direction is explicit', () {
    for (final v in [0.0, -1.0, double.nan, 2.0]) {
      expect(() => StrideCalibration(v), throwsFormatException);
    }
    expect(() => StrideCalibration.fromWalk(10, 0), throwsFormatException);
    expect(
      () => StrideCalibration.fromWalk(10, 20, interrupted: true),
      throwsFormatException,
    );
    expect(StrideCalibration.fromWalk(10, 20).meters, .5);
    final e = PdrEngine()
      ..beginGeneration(1)
      ..stride = StrideCalibration(.5);
    e.manualBearing = math.pi;
    expect(e.ingest(step(100)).motion!.manualDirection, true);
    e.invalidateHeading();
    expect(e.ingest(step(200)).motion, isNull);
  });

  test('Straight-edge forward/reverse progress, bounded overshoot, no route auto-arrival', () async {
    final f = await trackingFixture(), matcher = MapMatchingEngine(f.graph);
    final edge = f.graph.edges.values.first;
    matcher.confirmedStraightEdges.add(edge.id);
    MovementObservation motion(double heading, double distance) =>
        MovementObservation(distance, heading, null, 1000, 1, false);
    final start = matcher.onEdge(edge);
    final p = matcher.advance(start, motion(edge.bearing!, 1));
    expect(p.position.progressMeters, 1);
    final reverse = matcher.advance(
      p.position,
      motion(edge.bearing! + math.pi, .5),
    );
    expect(reverse.position.progressMeters, .5);
    final end = matcher.advance(p.position, motion(edge.bearing!, 10));
    expect(end.position.kind, PositionKind.nodeAnchor);
    expect(end.position.confidence, PositionConfidence.uncertain);
    expect(end.overshoot, 7);
    expect(end.reason, 'candidateNodeConfirm');
  });

  test(
    'Unconfirmed geometry or conflicting direction never moves through a room',
    () async {
      final f = await trackingFixture(), matcher = MapMatchingEngine(f.graph);
      final edge = f.graph.edges.values.first,
          start = matcher.onEdge(f.graph.edges.values.first);
      final m = MovementObservation(1, edge.bearing!, null, 1000, 1, false);
      expect(matcher.advance(start, m).reason, 'unsupportedGeometry');
      expect(matcher.advance(start, m).movedMeters, 0);
      matcher.confirmedStraightEdges.add(edge.id);
      expect(
        matcher
            .advance(
              start,
              MovementObservation(
                1,
                edge.bearing! + math.pi / 2,
                null,
                1000,
                1,
                false,
              ),
            )
            .reason,
        'headingConflict',
      );
    },
  );

  test('Junction includes cross-floor exits and does not choose desired route implicitly', () async {
    final f = await trackingFixture(), matcher = MapMatchingEngine(f.graph);
    matcher.confirmedStraightEdges.addAll(f.graph.edges.keys);
    final floor = f.project.floors.first;
    final stair = f.graph.nodes[floor.nodeIds['STAIR']]!;
    final p = VerifiedTrackingAnchor(
      f.graph.key,
      stair.id,
      stair.floorKey,
      PositionSource.manualExperiment,
    ).position(f.graph);
    final exits = matcher.candidates(p);
    expect(exits.length, 2);
    final result = matcher.advance(
      p,
      const MovementObservation(1, 0, null, 1000, 1, false),
    );
    expect(result.reason, 'junctionConfirmation');
    expect(result.movedMeters, 0);
  });
}
