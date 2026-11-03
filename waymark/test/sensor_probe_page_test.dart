import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/indoor_tracking/debug/sensor_probe_page.dart';
import 'package:waymark/features/indoor_tracking/sensors/sensor_models.dart';

import 'support/fake_sensor_provider.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    FakeSensorProvider fake, {
    GlobalKey<NavigatorState>? navigator,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [sensorProbeRouteObserver],
        home: SensorProbePage(provider: fake),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    // Stream cancellation cleanup can finish on the real async event queue.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  testWidgets(
    'Probe shows capabilities without prompting; Start/Stop and cleanup',
    (tester) async {
      final fake = FakeSensorProvider();
      await mount(tester, fake);
      expect(find.textContaining('TEST FAKE'), findsOneWidget);
      expect(fake.permissionRequests, 0);
      expect(fake.running, false);
      await tap(tester, 'sensor-start');
      await tester.scrollUntilVisible(
        find.byKey(const Key('sensor-state')),
        -200,
      );
      expect(find.text('Trạng thái: running'), findsOneWidget);
      fake.emit(SensorKind.stepDetector);
      fake.emit(SensorKind.stepCounter, values: [500]);
      await tester.pump(const Duration(milliseconds: 210));
      await tester.scrollUntilVisible(
        find.byKey(const Key('sensor-step-count')),
        200,
      );
      expect(find.text('Step Detector events: 1'), findsOneWidget);
      await tap(tester, 'sensor-stop');
      expect(fake.running, false);
      await unmount(tester);
      expect(fake.disposed, true);
      expect(fake.sampleEvents.hasListener, false);
    },
  );

  testWidgets(
    'Permission deny has explicit retry UX; no repeated prompt on lifecycle',
    (tester) async {
      final fake = FakeSensorProvider()
        ..requestedPermission = MotionPermission.denied;
      await mount(tester, fake);
      await tap(tester, 'sensor-permission');
      await tester.scrollUntilVisible(
        find.byKey(const Key('sensor-state')),
        -200,
      );
      expect(find.text('Trạng thái: permissionDenied'), findsOneWidget);
      expect(find.textContaining('Quyền bước chân bị từ chối'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(fake.permissionRequests, 1);
      expect(fake.running, false);
      await unmount(tester);
    },
  );

  testWidgets(
    'Unavailable/failed sensors are reported rather than Sensor Ready',
    (tester) async {
      final fake = FakeSensorProvider()..available.clear();
      await mount(tester, fake);
      await tap(tester, 'sensor-start');
      await tester.scrollUntilVisible(
        find.byKey(const Key('sensor-state')),
        -200,
      );
      expect(find.text('Trạng thái: unavailable'), findsOneWidget);
      expect(
        find.textContaining('Không có cảm biến đăng ký được'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.textContaining('registration=unavailable').first,
        200,
      );
      expect(find.textContaining('registration=unavailable'), findsWidgets);
      await unmount(tester);
    },
  );

  testWidgets(
    'Route cover unregisters even with app resumed; Resume is explicit',
    (tester) async {
      final fake = FakeSensorProvider();
      final navigator = GlobalKey<NavigatorState>();
      await mount(tester, fake, navigator: navigator);
      await tap(tester, 'sensor-start');
      final oldGeneration = fake.generation;
      final covered = navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Covered route')),
        ),
      );
      await tester.pumpAndSettle();
      expect(fake.running, false);
      navigator.currentState!.pop();
      await covered;
      await tester.pumpAndSettle();
      expect(fake.running, false);
      await tap(tester, 'sensor-resume');
      expect(fake.running, true);
      expect(fake.generation, greaterThan(oldGeneration));
      await unmount(tester);
    },
  );

  testWidgets(
    'App background unregisters; resumed app remains paused pending user Resume',
    (tester) async {
      final fake = FakeSensorProvider();
      await mount(tester, fake);
      await tap(tester, 'sensor-start');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(fake.running, false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(fake.running, false);
      await tap(tester, 'sensor-resume');
      expect(fake.running, true);
      await unmount(tester);
    },
  );

  testWidgets(
    'Rotation unavailable selects relative game vector without inventing heading',
    (tester) async {
      final fake = FakeSensorProvider()
        ..available.remove(SensorKind.rotationVector);
      await mount(tester, fake);
      await tap(tester, 'sensor-start');
      expect(
        fake.result!.registeredKinds,
        contains(SensorKind.gameRotationVector),
      );
      expect(
        fake.result!.registeredKinds,
        isNot(contains(SensorKind.rotationVector)),
      );
      fake.emit(SensorKind.gameRotationVector);
      expect(fake.running, true);
      await unmount(tester);
    },
  );
}
