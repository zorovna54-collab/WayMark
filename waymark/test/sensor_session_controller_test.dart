import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/indoor_tracking/sensors/sensor_models.dart';
import 'package:waymark/features/indoor_tracking/sensors/sensor_session_controller.dart';

import 'support/fake_sensor_provider.dart';

Future<void> flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeSensorProvider fake;
  late SensorSessionController controller;
  setUp(() {
    fake = FakeSensorProvider();
    controller = SensorSessionController(fake);
  });
  tearDown(() async {
    await controller.close();
    controller.dispose();
  });

  test('No fake data before start; double start/stop are safe; no implicit permission request', () async {
    expect(fake.emit(SensorKind.stepDetector), false);
    await Future.wait([controller.start(), controller.start()]);
    expect(fake.starts, 1);
    expect(fake.permissionRequests, 0);
    await controller.stop();
    await controller.stop();
    expect(controller.state, SensorSessionState.idle);
    expect(fake.running, false);
    expect(fake.emit(SensorKind.stepDetector), false);
  });

  test(
    'Ten pause/resume cycles re-probe and fence duplicates and stale samples',
    () async {
      await controller.start();
      for (var i = 0; i < 10; i++) {
        final old = fake.generation;
        fake.emit(SensorKind.stepDetector);
        fake.emit(SensorKind.stepDetector); // Exact duplicate.
        await controller.pause();
        fake.emit(
          SensorKind.stepDetector,
          timestamp: 2000,
          sequence: 2,
          late: true,
        );
        await controller.resume();
        expect(fake.generation, greaterThan(old));
        fake.emit(
          SensorKind.stepDetector,
          forGeneration: old,
          timestamp: 3000,
          late: true,
        );
      }
      expect(controller.detectorEvents, 10);
      expect(fake.starts, 11);
      expect(fake.probes, 11);
      expect(fake.permissionRequests, 0);
    },
  );

  test('Detector count is independent of cumulative counter; no backlog replay on resume', () async {
    await controller.start();
    fake.emit(SensorKind.stepCounter, values: [100]);
    fake.emit(SensorKind.stepDetector);
    expect(controller.detectorEvents, 1);
    await controller.pause();
    await controller.resume();
    fake.emit(SensorKind.stepCounter, values: [120]);
    expect(controller.counterRaw, 120);
    expect(controller.detectorEvents, 1);
    fake.emit(
      SensorKind.stepCounter,
      values: [1],
      sequence: 2,
      timestamp: 2000,
    );
    expect(controller.counterResets, 1);
  });

  test('Cross-sensor reorder accepted, same-sensor reversal rejected, memory bounded', () async {
    await controller.start();
    fake.emit(SensorKind.stepDetector, timestamp: 10000, sequence: 1);
    fake.emit(SensorKind.rotationVector, timestamp: 100, sequence: 2);
    fake.emit(SensorKind.rotationVector, timestamp: 99, sequence: 3);
    for (var i = 2; i < 200; i++) {
      fake.emit(SensorKind.stepDetector, timestamp: 10000 + i, sequence: i + 2);
    }
    expect(
      controller.latest[SensorKind.rotationVector]!.sensorTimestampNs,
      100,
    );
    expect(controller.rejectedEvents, 1);
    expect(controller.recent.length, 128);
  });

  test('Partial registration / denied step permission leaves orientation observable', () async {
    fake.permission = MotionPermission.denied;
    await controller.start();
    expect(controller.state, SensorSessionState.running);
    expect(controller.result!.registeredKinds, {SensorKind.rotationVector});
    fake.emit(SensorKind.stepDetector);
    fake.emit(SensorKind.rotationVector);
    expect(controller.detectorEvents, 0);
    expect(controller.latest.keys, [SensorKind.rotationVector]);
  });

  test('All sensors absent, registration failed and step-only denied are distinct states', () async {
    fake.available.clear();
    await controller.start();
    expect(controller.state, SensorSessionState.unavailable);
    await controller.stop();
    fake.available = {SensorKind.stepDetector};
    fake.registrationFailures = {SensorKind.stepDetector};
    await controller.start(SensorConfig(kinds: {SensorKind.stepDetector}));
    expect(controller.state, SensorSessionState.error);
    await controller.stop();
    fake.registrationFailures.clear();
    fake.permission = MotionPermission.denied;
    await controller.start(SensorConfig(kinds: {SensorKind.stepDetector}));
    expect(controller.state, SensorSessionState.permissionDenied);
  });

  test(
    'Permission denial is explicit and never auto-prompts on resume/revocation',
    () async {
      fake.requestedPermission = MotionPermission.denied;
      await controller.requestPermission();
      expect(controller.state, SensorSessionState.permissionDenied);
      expect(fake.permissionRequests, 1);
      fake.permission = MotionPermission.granted;
      await controller.start(SensorConfig(kinds: {SensorKind.stepDetector}));
      await controller.pause();
      fake.permission = MotionPermission.denied;
      await controller.resume();
      expect(controller.state, SensorSessionState.permissionDenied);
      expect(fake.running, false);
      expect(fake.permissionRequests, 1);
    },
  );

  test(
    'Start/stop race resolves to stopped, not a leaked registration',
    () async {
      fake.startBarrier = Completer<void>();
      final start = controller.start();
      await flush();
      final stop = controller.stop();
      fake.startBarrier!.complete();
      await Future.wait([start, stop]);
      expect(fake.running, false);
      expect(controller.state, SensorSessionState.idle);
      expect(controller.detectorEvents, 0);
    },
  );

  test('Partial start exception cleans up; retry is possible', () async {
    fake.throwStart = true;
    await controller.start();
    expect(fake.running, false);
    expect(controller.state, SensorSessionState.error);
    expect(controller.lastError, contains('cleaned up'));
    fake.throwStart = false;
    await controller.start();
    expect(controller.state, SensorSessionState.running);
  });

  test('Re-probe catches revoked step permission; failed probe also stops active sensors', () async {
    await controller.start();
    fake.permission = MotionPermission.denied;
    await controller.refresh();
    expect(fake.running, false);
    expect(controller.state, SensorSessionState.permissionDenied);
    expect(fake.permissionRequests, 0);
    fake.permission = MotionPermission.granted;
    await controller.start();
    fake.throwProbe = true;
    await controller.refresh();
    expect(fake.running, false);
    expect(controller.state, SensorSessionState.error);
  });

  test(
    'Native fatal error stops, malformed event remains recoverable',
    () async {
      await controller.start();
      fake.emitMalformed({'kind': 'garbage'});
      expect(controller.state, SensorSessionState.running);
      expect(controller.lastError, isNotNull);
      fake.statusEvents.add(
        SensorProviderStatus(
          SensorProviderPhase.error,
          fake.generation,
          'permission revoked',
        ),
      );
      await flush();
      expect(fake.running, false);
      expect(controller.state, SensorSessionState.error);
    },
  );

  test('Visibility is independent of app lifecycle; hidden route pauses until visible', () async {
    await controller.start();
    await controller.setVisible(false);
    expect(controller.state, SensorSessionState.paused);
    expect(fake.running, false);
    await controller.resume();
    expect(fake.running, false);
    await controller.setVisible(true);
    expect(fake.running, false);
    await controller.resume();
    expect(fake.running, true);
  });

  test(
    'Dispose during start suppresses callbacks and cleans up before completing',
    () async {
      fake.startBarrier = Completer<void>();
      final start = controller.start();
      await flush();
      final closed = controller.close();
      fake.emit(SensorKind.stepDetector, forGeneration: 1, late: true);
      fake.startBarrier!.complete();
      await Future.wait([start, closed]);
      expect(fake.disposed, true);
      expect(fake.sampleEvents.hasListener, false);
      expect(controller.state, SensorSessionState.disposed);
      expect(controller.detectorEvents, 0);
    },
  );

  test('Display notifications are throttled; raw samples are retained in bounded memory', () async {
    await controller.start();
    var notifications = 0;
    controller.addListener(() => notifications++);
    for (var i = 1; i <= 200; i++) {
      fake.emit(SensorKind.stepDetector, sequence: i, timestamp: i);
    }
    expect(controller.detectorEvents, 200);
    expect(notifications, 0);
    expect(controller.recent.length, 128);
    await Future<void>.delayed(const Duration(milliseconds: 230));
    expect(notifications, 1);
  });
}
