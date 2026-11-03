import 'dart:async';

import 'package:waymark/features/indoor_tracking/sensors/sensor_models.dart';
import 'package:waymark/features/indoor_tracking/sensors/sensor_provider.dart';

Map<String, Object?> samplePayload(
  SensorKind kind, {
  int generation = 1,
  int sequence = 1,
  int timestamp = 9007199254740993,
  List<double>? values,
}) => {
  'schemaVersion': 1,
  'type': 'sample',
  'kind': kind.name,
  'androidType': kind.androidType,
  'generation': generation,
  'sequence': sequence,
  'sensorTimestampNs': timestamp,
  'nativeReceiveTimestampNs': timestamp + 100,
  'values':
      values ??
      switch (kind) {
        SensorKind.stepDetector => [1.0],
        SensorKind.stepCounter => [100.0],
        SensorKind.rotationVector => [0.0, 0.0, 0.0, 1.0, -1.0],
        SensorKind.gameRotationVector => [0.0, 0.0, 0.0, 1.0],
        _ => [0.1, 0.2, 0.3],
      },
  'accuracy': 3,
  'units': kind.units,
  'referenceFrame': kind.referenceFrame,
};

/// Test-only provider. No timer or automatic sensor samples; never imported
/// under lib/ or tool/. Late/malformed inputs require explicit test injection.
class FakeSensorProvider implements SensorProvider {
  final sampleEvents = StreamController<SensorSample>.broadcast(sync: true);
  final statusEvents = StreamController<SensorProviderStatus>.broadcast(
    sync: true,
  );
  MotionPermission permission = MotionPermission.granted;
  MotionPermission requestedPermission = MotionPermission.granted;
  Set<SensorKind> available = SensorKind.values.toSet();
  Set<SensorKind> registrationFailures = {};
  int generation = 0, starts = 0, stops = 0, probes = 0, permissionRequests = 0;
  bool running = false,
      disposed = false,
      throwStart = false,
      throwProbe = false;
  Completer<void>? startBarrier;
  SensorStartResult? result;

  @override
  Stream<SensorSample> get samples => sampleEvents.stream;
  @override
  Stream<SensorProviderStatus> get statuses => statusEvents.stream;
  @override
  Future<SensorCapabilities> probe() async {
    probes++;
    if (throwProbe) throw StateError('Probe failed');
    return SensorCapabilities(
      permission: permission,
      device: 'TEST FAKE',
      androidApi: 36,
      sensors: [
        for (final kind in SensorKind.values)
          SensorCapability(
            kind: kind,
            available: available.contains(kind),
            name: kind.name,
          ),
      ],
    );
  }

  @override
  Future<MotionPermission> requestPermission() async {
    permissionRequests++;
    return permission = requestedPermission;
  }

  @override
  Future<SensorStartResult> start(SensorConfig config) async {
    if (running) return result!;
    starts++;
    await startBarrier?.future;
    if (throwStart) {
      running = true;
      throw StateError('Partial native failure');
    }
    final registrations = [
      for (final kind in config.kinds)
        SensorRegistration(
          kind,
          !available.contains(kind)
              ? RegistrationState.unavailable
              : kind.isStep && permission == MotionPermission.denied
              ? RegistrationState.permissionDenied
              : registrationFailures.contains(kind)
              ? RegistrationState.failed
              : RegistrationState.registered,
        ),
    ];
    result = SensorStartResult(
      generation: ++generation,
      permission: permission,
      registrations: registrations,
    );
    running = result!.running;
    return result!;
  }

  @override
  Future<void> stop() async {
    stops++;
    running = false;
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    await stop();
    disposed = true;
    await sampleEvents.close();
    await statusEvents.close();
  }

  bool emit(
    SensorKind kind, {
    int? forGeneration,
    int sequence = 1,
    int timestamp = 1000,
    List<double>? values,
    bool late = false,
  }) {
    if (disposed || !running && !late) return false;
    sampleEvents.add(
      SensorSample.decode(
        samplePayload(
          kind,
          generation: forGeneration ?? generation,
          sequence: sequence,
          timestamp: timestamp,
          values: values,
        ),
      ),
    );
    return true;
  }

  void emitMalformed(Object? payload) {
    if (disposed || !running) return;
    try {
      sampleEvents.add(SensorSample.decode(payload));
    } on FormatException catch (error) {
      statusEvents.add(
        SensorProviderStatus(
          SensorProviderPhase.recoverableError,
          generation,
          error.message,
        ),
      );
    }
  }
}
