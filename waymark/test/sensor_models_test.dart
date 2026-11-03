import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/indoor_tracking/sensors/sensor_models.dart';

import 'support/fake_sensor_provider.dart';

void main() {
  for (final kind in SensorKind.values) {
    test(
      'Codec preserves int64, values, units and Android frame: ${kind.name}',
      () {
        final sample = SensorSample.decode(samplePayload(kind));
        expect(sample.sensorTimestampNs, 9007199254740993);
        expect(sample.nativeDeliveryLatencyNs, 100);
        expect(sample.units, kind.units);
        expect(sample.referenceFrame, kind.referenceFrame);
        expect(() => sample.values.add(0), throwsUnsupportedError);
      },
    );
  }

  test(
    'Rotation vectors preserve optional fields and reconstruct missing w only',
    () {
      final full = SensorSample.decode(
        samplePayload(SensorKind.rotationVector),
      );
      expect(full.quaternion, [0, 0, 0, 1]);
      expect(full.values[4], -1);
      final three = SensorSample.decode(
        samplePayload(SensorKind.rotationVector, values: [0, 0, 0]),
      );
      expect(three.quaternion, [0, 0, 0, 1]);
      expect(
        SensorSample.decode(samplePayload(SensorKind.accelerometer)).quaternion,
        isNull,
      );
    },
  );

  final malformed = <String, Map<String, Object?>>{
    'schema': {'schemaVersion': 2},
    'schema type': {'schemaVersion': 1.0},
    'kind': {'kind': 'travelHeading'},
    'type': {'androidType': 19},
    'type number': {'androidType': 18.0},
    'frame': {'referenceFrame': 'travelDirection'},
    'units': {'units': 'meters'},
    'timestamp double': {'sensorTimestampNs': 1000.0},
    'timestamp negative': {'sensorTimestampNs': -1},
    'timestamp int64 overflow': {'sensorTimestampNs': -9223372036854775808},
    'generation zero': {'generation': 0},
    'sequence zero': {'sequence': 0},
    'receive missing': {'nativeReceiveTimestampNs': null},
    'accuracy': {'accuracy': 4},
    'value type': {
      'values': ['1'],
    },
    'length': {
      'values': [1, 2],
    },
    'NaN': {
      'values': [double.nan],
    },
    'infinity': {
      'values': [double.infinity],
    },
    'detector not one': {
      'values': [2],
    },
  };
  for (final entry in malformed.entries) {
    test('Reject malformed sample: ${entry.key}', () {
      expect(
        () => SensorSample.decode({
          ...samplePayload(SensorKind.stepDetector),
          ...entry.value,
        }),
        throwsFormatException,
      );
    });
  }
  test(
    'Reject non-map, fractional/negative counter and invalid quaternion',
    () {
      expect(() => SensorSample.decode(null), throwsFormatException);
      for (final value in [-1.0, 1.5]) {
        expect(
          () => SensorSample.decode(
            samplePayload(SensorKind.stepCounter, values: [value]),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => SensorSample.decode(
          samplePayload(SensorKind.rotationVector, values: [1, 1, 1, 1]),
        ),
        throwsFormatException,
      );
    },
  );

  test('Negative latency is not represented as a valid timing measurement', () {
    final sample = SensorSample.decode({
      ...samplePayload(SensorKind.stepDetector),
      'nativeReceiveTimestampNs': 1,
    });
    expect(sample.nativeDeliveryLatencyNs, isNull);
  });

  test('Gate rejects stale generation, duplicate, per-sensor timestamp/order; cross-sensor reorder accepted', () {
    final gate = SensorSampleGate()..reset(2, SensorKind.values.toSet());
    SensorSample sample(SensorKind kind, int gen, int time, int seq) =>
        SensorSample.decode(
          samplePayload(kind, generation: gen, timestamp: time, sequence: seq),
        );
    expect(gate.accept(sample(SensorKind.stepDetector, 2, 200, 2)), isTrue);
    expect(gate.accept(sample(SensorKind.rotationVector, 2, 100, 1)), isTrue);
    expect(gate.accept(sample(SensorKind.stepDetector, 1, 300, 3)), isFalse);
    expect(gate.accept(sample(SensorKind.stepDetector, 2, 200, 3)), isFalse);
    expect(gate.accept(sample(SensorKind.stepDetector, 2, 300, 2)), isFalse);
    gate.reset(3, {SensorKind.stepDetector});
    expect(gate.accept(sample(SensorKind.stepDetector, 3, 50, 1)), isTrue);
    expect(gate.accept(sample(SensorKind.accelerometer, 3, 100, 2)), isFalse);
  });

  test('Configuration rejects unsafe rates/empty sensor set', () {
    expect(() => SensorConfig(kinds: {}), throwsArgumentError);
    expect(() => SensorConfig(samplingPeriodUs: 1), throwsArgumentError);
  });

  test(
    'Registration outcomes also decode from the versioned status stream',
    () {
      final status = SensorProviderStatus.decode({
        'schemaVersion': 1,
        'type': 'status',
        'state': 'registration',
        'generation': 10,
        'message': 'partial',
        'registrations': [
          {
            'kind': 'stepDetector',
            'state': 'permissionDenied',
            'reason': 'denied',
          },
          {'kind': 'rotationVector', 'state': 'registered', 'reason': ''},
        ],
      });
      expect(status.registrations[0].state, RegistrationState.permissionDenied);
      expect(status.registrations[1].state, RegistrationState.registered);
    },
  );
}
