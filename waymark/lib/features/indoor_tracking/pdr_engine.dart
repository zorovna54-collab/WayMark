import 'dart:collection';
import 'dart:math' as math;

import 'sensors/sensor_models.dart';

double wrapAngle(double radians) =>
    math.atan2(math.sin(radians), math.cos(radians));
double angleDifference(double a, double b) => wrapAngle(a - b).abs();

class StrideCalibration {
  StrideCalibration(this.meters, {this.measured = false}) {
    if (!meters.isFinite || meters < .2 || meters > 1.5) {
      throw const FormatException('Chiều dài bước cần 0,2–1,5 m.');
    }
  }
  factory StrideCalibration.fromWalk(
    double measuredMeters,
    int steps, {
    bool interrupted = false,
  }) {
    if (interrupted ||
        !measuredMeters.isFinite ||
        measuredMeters <= 0 ||
        steps <= 0) {
      throw const FormatException(
        'Phép đo cần quãng đường/số bước dương và không gián đoạn.',
      );
    }
    return StrideCalibration(measuredMeters / steps, measured: true);
  }
  final double meters;
  final bool measured;
}

class HeadingObservation {
  const HeadingObservation(
    this.yaw,
    this.projection,
    this.kind,
    this.timestampNs,
    this.generation,
    this.reliable,
  );
  final double yaw, projection;
  final SensorKind kind;
  final int timestampNs, generation;
  final bool reliable;
  static HeadingObservation? fromSample(SensorSample sample) {
    final q = sample.quaternion;
    if (q == null) return null;
    final x = q[0], y = q[1], z = q[2], w = q[3];
    // Android SensorManager azimuth: atan2(R[1], R[4]).
    // Physical +Y (top of phone) projected onto the horizontal world plane.
    final east = 2 * (x * y - z * w), north = 1 - 2 * (x * x + z * z);
    final projection = math.sqrt(east * east + north * north);
    final headingAccuracy = sample.values.length == 5 ? sample.values[4] : -1;
    return HeadingObservation(
      math.atan2(east, north),
      projection,
      sample.kind,
      sample.sensorTimestampNs,
      sample.generation,
      projection >= .35 &&
          sample.accuracy >= 1 &&
          (headingAccuracy == -1 || headingAccuracy <= .6),
    );
  }
}

class HeadingCalibration {
  HeadingCalibration.align(HeadingObservation observation, double mapBearing)
    : yawAtAlignment = observation.yaw,
      mapAtAlignment = mapBearing,
      kind = observation.kind {
    if (!observation.reliable || !mapBearing.isFinite) {
      throw const FormatException(
        'Tư thế/hướng chưa đủ tin cậy; giữ máy gần nằm ngang.',
      );
    }
  }
  final double yawAtAlignment, mapAtAlignment;
  final SensorKind kind;
  double? travelDirection(HeadingObservation observation) =>
      observation.reliable && observation.kind == kind
      ? wrapAngle(mapAtAlignment + observation.yaw - yawAtAlignment)
      : null;
}

class MovementObservation {
  const MovementObservation(
    this.meters,
    this.travelDirection,
    this.phoneYaw,
    this.timestampNs,
    this.generation,
    this.manualDirection,
  );
  final double meters, travelDirection;
  final double? phoneYaw;
  final int timestampNs, generation;
  final bool manualDirection;
}

class PdrUpdate {
  const PdrUpdate({this.motion, this.reason});
  final MovementObservation? motion;
  final String? reason;
}

/// On-device step observations, not a route animation. A changed phone yaw
/// cannot by itself produce displacement or prove a changed walking direction.
class PdrEngine {
  StrideCalibration? stride;
  HeadingCalibration? heading;
  double? manualBearing;
  final _gate = SensorSampleGate();
  final _orientations = ListQueue<HeadingObservation>();
  HeadingObservation? get latestHeading => _orientations.lastOrNull;
  int generation = 0, minTimestampNs = 0, lastTimestampNs = 0;
  int acceptedSteps = 0, rejectedSteps = 0;
  static const staleOrientationNs = 1500000000;

  void beginGeneration(int next) {
    generation = next;
    _gate.reset(next, {
      SensorKind.stepDetector,
      SensorKind.rotationVector,
      SensorKind.gameRotationVector,
    });
    _orientations.clear();
    minTimestampNs = 0;
    lastTimestampNs = 0;
  }

  void fenceBaseline() {
    minTimestampNs = lastTimestampNs;
  }

  void invalidateHeading() {
    heading = null;
    manualBearing = null;
    fenceBaseline();
  }

  PdrUpdate ingest(SensorSample sample) {
    if (sample.kind == SensorKind.stepCounter) return const PdrUpdate();
    if (!_gate.accept(sample) || sample.sensorTimestampNs <= minTimestampNs) {
      if (sample.kind == SensorKind.stepDetector) rejectedSteps++;
      return const PdrUpdate();
    }
    lastTimestampNs = math.max(lastTimestampNs, sample.sensorTimestampNs);
    final orientation = HeadingObservation.fromSample(sample);
    if (orientation != null) {
      if (_orientations.length == 32) _orientations.removeFirst();
      _orientations.addLast(orientation);
      return const PdrUpdate(); // Rotation-only never changes the position.
    }
    if (sample.kind != SensorKind.stepDetector) return const PdrUpdate();
    acceptedSteps++;
    final calibratedStride = stride;
    if (calibratedStride == null) {
      return const PdrUpdate(reason: 'strideRequired');
    }
    final prior = _orientations
        .where(
          (o) =>
              o.timestampNs <= sample.sensorTimestampNs &&
              sample.sensorTimestampNs - o.timestampNs <= staleOrientationNs,
        )
        .lastOrNull;
    final direction =
        manualBearing ??
        (prior == null ? null : heading?.travelDirection(prior));
    if (direction == null) {
      return PdrUpdate(
        reason: prior == null ? 'staleOrientation' : 'headingRequired',
      );
    }
    return PdrUpdate(
      motion: MovementObservation(
        calibratedStride.meters,
        direction,
        prior?.yaw,
        sample.sensorTimestampNs,
        sample.generation,
        manualBearing != null,
      ),
    );
  }
}
