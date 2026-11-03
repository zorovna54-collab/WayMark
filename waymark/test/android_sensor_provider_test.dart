import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/indoor_tracking/sensors/android_sensor_provider.dart';
import 'package:waymark/features/indoor_tracking/sensors/sensor_models.dart';
import 'package:waymark/features/indoor_tracking/sensors/sensor_provider.dart';

import 'support/fake_sensor_provider.dart';

class NativeSensorMock {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  static const control = MethodChannel('waymark/sensors/control');
  static const channel = EventChannel('waymark/sensors/events');
  late MockStreamHandlerEventSink sink;
  final calls = <String>[];
  MotionPermission permission = MotionPermission.granted;
  Set<SensorKind> missing = {}, failed = {};
  int clock = 1000, listens = 0, cancels = 0;
  bool throwStart = false, badStartReply = false, listeningHandshake = true;
  Completer<void>? startBarrier;

  NativeSensorMock() {
    messenger.setMockStreamHandler(
      channel,
      MockStreamHandler.inline(
        onListen: (_, events) {
          listens++;
          sink = events;
          if (listeningHandshake) {
            events.success({
              'type': 'status',
              'schemaVersion': 1,
              'generation': 0,
              'state': 'listening',
              'message': 'ready',
            });
          }
        },
        onCancel: (_) {
          cancels++;
        },
      ),
    );
    messenger.setMockMethodCallHandler(control, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'probe':
          return {
            'schemaVersion': 1,
            'device': 'MOCK ONLY',
            'androidApi': 36,
            'permission': permission.name,
            'sensors': [
              for (final kind in SensorKind.values)
                {
                  'kind': kind.name,
                  'available': !missing.contains(kind),
                  'name': kind.name,
                  'vendor': 'TEST',
                  'version': 1,
                  'minDelayUs': 20000,
                  'maxRange': 1.0,
                  'resolution': .1,
                  'registration': 'notRequested',
                },
            ],
          };
        case 'requestPermission':
          return {'schemaVersion': 1, 'permission': permission.name};
        case 'clock':
          return {'schemaVersion': 1, 'nativeTimestampNs': ++clock};
        case 'start':
          await startBarrier?.future;
          if (throwStart) throw PlatformException(code: 'SENSOR_ERROR');
          final a = call.arguments as Map;
          return {
            'schemaVersion': 1,
            'generation': badStartReply ? 0 : a['generation'],
            'permission': permission.name,
            'registrations': [
              for (final name in a['kinds'] as List)
                {
                  'kind': name,
                  'state': missing.contains(SensorKind.parse(name))
                      ? 'unavailable'
                      : SensorKind.parse(name).isStep &&
                            permission == MotionPermission.denied
                      ? 'permissionDenied'
                      : failed.contains(SensorKind.parse(name))
                      ? 'failed'
                      : 'registered',
                  'reason': '',
                },
            ],
          };
        case 'stop':
          return null;
      }
      throw MissingPluginException();
    });
  }
}

Future<void> flushEvents() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NativeSensorMock native;
  late AndroidSensorProvider provider;
  setUp(() {
    native = NativeSensorMock();
    provider = AndroidSensorProvider();
  });
  tearDown(() async {
    await provider.dispose();
  });

  test('Probe inventories all sensors and never asks for permission', () async {
    native.missing = {SensorKind.stepDetector};
    final capabilities = await provider.probe();
    expect(capabilities.forKind(SensorKind.stepDetector).available, false);
    expect(capabilities.forKind(SensorKind.rotationVector).available, true);
    expect(native.calls, ['probe']);
    expect(native.listens, 0);
  });

  test(
    'A second provider cannot take ownership or stop the active owner',
    () async {
      await provider.start(SensorConfig());
      final other = AndroidSensorProvider();
      final stops = native.calls.where((c) => c == 'stop').length;
      await expectLater(other.start(SensorConfig()), throwsStateError);
      await other.stop();
      await other.dispose();
      expect(native.calls.where((c) => c == 'stop').length, stops);
      expect(native.cancels, 0);
    },
  );

  for (final permission in [
    MotionPermission.granted,
    MotionPermission.denied,
    MotionPermission.notRequired,
  ]) {
    test(
      'Permission response ${permission.name} is explicit and typed',
      () async {
        native.permission = permission;
        expect(await provider.requestPermission(), permission);
        expect(native.calls, ['requestPermission']);
      },
    );
  }

  test(
    'Partial registration keeps orientation while step permission is denied',
    () async {
      native.permission = MotionPermission.denied;
      final result = await provider.start(SensorConfig());
      expect(result.registeredKinds, {SensorKind.rotationVector});
      expect(
        result.registrations.first.state,
        RegistrationState.permissionDenied,
      );
      expect(native.calls, isNot(contains('requestPermission')));
    },
  );

  test('Missing sensor, failed registration and no registered sensors clean subscription', () async {
    native.missing = {SensorKind.stepDetector};
    native.failed = {SensorKind.rotationVector};
    final result = await provider.start(
      SensorConfig(kinds: {SensorKind.stepDetector, SensorKind.rotationVector}),
    );
    expect(result.running, false);
    expect(result.registrations.map((r) => r.state), [
      RegistrationState.unavailable,
      RegistrationState.failed,
    ]);
    expect(native.cancels, 1);
    expect(native.calls, contains('stop'));
  });

  test('Start twice is idempotent; stop twice is safe and cancels native subscription', () async {
    final first = await provider.start(SensorConfig());
    final second = await provider.start(SensorConfig());
    expect(second, same(first));
    expect(native.listens, 1);
    expect(native.calls.where((c) => c == 'start').length, 1);
    await provider.stop();
    await provider.stop();
    expect(native.cancels, 1);
  });

  test('Preserve ns; reject malformed, duplicate/stale/wrong-kind samples, allow cross-sensor reorder', () async {
    final samples = <SensorSample>[], statuses = <SensorProviderStatus>[];
    final sampleSub = provider.samples.listen(samples.add);
    final statusSub = provider.statuses.listen(statuses.add);
    addTearDown(sampleSub.cancel);
    addTearDown(statusSub.cancel);
    final result = await provider.start(SensorConfig());
    void send(SensorKind kind, int time, int seq, {int? generation}) =>
        native.sink.success(
          samplePayload(
            kind,
            timestamp: time,
            sequence: seq,
            generation: generation ?? result.generation,
          ),
        );
    send(SensorKind.stepDetector, 9007199254740993, 2);
    send(SensorKind.rotationVector, 1000, 1);
    send(SensorKind.stepDetector, 9007199254740993, 3);
    send(SensorKind.stepDetector, 9007199254740994, 1);
    send(
      SensorKind.stepDetector,
      9007199254740995,
      3,
      generation: result.generation - 1,
    );
    send(SensorKind.gyroscope, 1100, 4);
    native.sink.success({
      'schemaVersion': 1,
      'type': 'sample',
      'kind': 'unknown',
    });
    send(SensorKind.stepDetector, 9007199254740996, 4);
    await flushEvents();
    expect(samples.length, 3);
    expect(samples.first.sensorTimestampNs, 9007199254740993);
    expect(
      statuses.any((s) => s.phase == SensorProviderPhase.recoverableError),
      true,
    );
  });

  test('Resume is a fresh generation; old events and paused status cannot end the new session', () async {
    final samples = <SensorSample>[];
    final sub = provider.samples.listen(samples.add);
    addTearDown(sub.cancel);
    final old = await provider.start(SensorConfig());
    await provider.stop();
    final next = await provider.start(SensorConfig());
    expect(next.generation, greaterThan(old.generation));
    native.sink.success(
      samplePayload(SensorKind.stepDetector, generation: old.generation),
    );
    native.sink.success({
      'type': 'status',
      'schemaVersion': 1,
      'generation': old.generation,
      'state': 'paused',
      'message': 'stale',
    });
    native.sink.success(
      samplePayload(SensorKind.stepDetector, generation: next.generation),
    );
    await flushEvents();
    expect(samples.length, 1);
    expect(samples.single.generation, next.generation);
  });

  test('Native lifecycle pause fences further samples', () async {
    final samples = <SensorSample>[];
    final sub = provider.samples.listen(samples.add);
    addTearDown(sub.cancel);
    final result = await provider.start(SensorConfig());
    native.sink.success({
      'type': 'status',
      'schemaVersion': 1,
      'generation': result.generation,
      'state': 'paused',
      'message': 'Activity paused',
    });
    native.sink.success(
      samplePayload(SensorKind.stepDetector, generation: result.generation),
    );
    await flushEvents();
    expect(samples, isEmpty);
    expect(native.cancels, 1);
    final next = await provider.start(SensorConfig());
    expect(next.generation, greaterThan(result.generation));
    expect(native.listens, 2);
  });

  test(
    'Channel start failure cleans registration and subscription; retry works',
    () async {
      native.throwStart = true;
      await expectLater(
        provider.start(SensorConfig()),
        throwsA(isA<PlatformException>()),
      );
      expect(native.cancels, 1);
      expect(native.calls, contains('stop'));
      native.throwStart = false;
      expect((await provider.start(SensorConfig())).running, true);
    },
  );

  test('Malformed start response also cleans native registration', () async {
    native.badStartReply = true;
    await expectLater(provider.start(SensorConfig()), throwsFormatException);
    expect(native.cancels, 1);
    expect(native.calls, contains('stop'));
  });

  test('Event channel error is handled and unsubscribes', () async {
    await provider.start(SensorConfig());
    native.sink.error(code: 'SENSOR_ERROR');
    await flushEvents();
    expect(native.cancels, 1);
  });

  test(
    'Stop during in-flight start invalidates pending generation and cleans up',
    () async {
      native.startBarrier = Completer<void>();
      final pending = provider.start(SensorConfig());
      await flushEvents();
      final stopped = provider.stop();
      native.startBarrier!.complete();
      await expectLater(pending, throwsStateError);
      await stopped;
      expect(native.cancels, 1);
    },
  );

  test('Dispose suppresses late samples and is idempotent', () async {
    final samples = <SensorSample>[];
    final sub = provider.samples.listen(samples.add);
    addTearDown(sub.cancel);
    final result = await provider.start(SensorConfig());
    await provider.dispose();
    await provider.dispose();
    native.sink.success(
      samplePayload(SensorKind.stepDetector, generation: result.generation),
    );
    await flushEvents();
    expect(samples, isEmpty);
    await expectLater(provider.probe(), throwsStateError);
  });

  test('Listen handshake timeout cleans up without a native start', () async {
    await provider.dispose();
    provider = AndroidSensorProvider(
      listenTimeout: const Duration(milliseconds: 10),
    );
    native.listeningHandshake = false;
    await expectLater(
      provider.start(SensorConfig()),
      throwsA(isA<TimeoutException>()),
    );
    expect(native.cancels, 1);
    expect(native.calls, isNot(contains('start')));
  });

  test(
    'Factory returns an unavailable provider on non-Android platforms',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });
      final unsupported = createSensorProvider();
      expect(unsupported, isA<UnsupportedSensorProvider>());
      expect(
        (await unsupported.probe()).permission,
        MotionPermission.unavailable,
      );
      expect((await unsupported.start(SensorConfig())).running, false);
      await unsupported.dispose();
    },
  );
}
