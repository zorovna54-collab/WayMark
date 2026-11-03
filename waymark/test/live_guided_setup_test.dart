import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/indoor_tracking/live_tracking_panel.dart';
import 'package:waymark/features/indoor_tracking/indoor_position.dart';

import 'support/live_tracking_replay.dart';
import 'support/fake_sensor_provider.dart';
import 'live_navigation_ui_test.dart' show liveTap, unmountLive, closeTracking;

Future<void> mountGuided(
  WidgetTester t,
  LiveTrackingReplay r, {
  Future<void> Function()? onManual,
}) async {
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LiveTrackingPanel(
            controller: r.controller,
            onScan: () async {},
            onManual: onManual ?? () async {},
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> stage(WidgetTester t, String title) async {
  final finder = find.descendant(
    of: find.byType(Stepper),
    matching: find.text(title),
  );
  await t.ensureVisible(finder);
  await t.tap(finder);
  await t.pumpAndSettle();
}

Future<void> next(WidgetTester t) async {
  final step = t.widget<Stepper>(find.byType(Stepper)).currentStep;
  final finder = find.byKey(ValueKey('live-next-$step'));
  await t.ensureVisible(finder);
  await t.tap(finder);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'Five guided stages can be completed using actual controls; partial setup explains missing conditions',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      // Decode/raster fixtures on the real event loop, then construct the
      // controller here so its freshness timer uses the test's fake clock.
      final fixture = (await t.runAsync(LiveTrackingReplay.create))!;
      await t.runAsync(fixture.close);
      final r = LiveTrackingReplay(
        fixture.map,
        fixture.graph,
        FakeSensorProvider(),
      );
      await mountGuided(t, r);
      await stage(t, 'Bắt đầu Live Navigation');
      await liveTap(t, const Key('live-align'));
      expect(r.controller.canIntegrate, false);
      expect(find.byKey(const Key('live-setup-error')), findsOneWidget);
      expect(find.byKey(const Key('live-missing-conditions')), findsOneWidget);
      expect(r.fake.starts, 0);

      await stage(t, 'Xác nhận vị trí');
      await liveTap(t, const Key('live-confirm-anchor'));
      expect(
        r.controller.position.value!.confidence,
        PositionConfidence.manualConfirmation,
      );
      await next(t);
      await liveTap(t, const Key('live-probe'));
      expect(r.fake.permissionRequests, 0);
      await liveTap(t, const Key('live-permission'));
      await liveTap(t, const Key('live-start'));
      expect(r.fake.running, true);
      await next(t);
      await liveTap(t, const Key('live-save-stride'));
      expect(r.controller.strideConfirmed, true);
      await next(t);
      final straight = find.text(
        'Đã đối chiếu thực tế: hành lang thẳng, mét đúng và không xuyên vật cản.',
      );
      await t.ensureVisible(straight);
      await t.tap(straight);
      await t.pumpAndSettle();
      r.orientation();
      await next(t);
      await liveTap(t, const Key('live-align'));
      expect(r.controller.canIntegrate, true);
      expect(find.byKey(const Key('live-guided-setup')), findsNothing);
      expect(r.controller.position.value!.edgeId, r.edge('A', 'J').id);
      r.step();
      await t.pump(const Duration(milliseconds: 220));
      expect(r.controller.position.value!.progressMeters, closeTo(.7, .0001));
      final before = r.controller.position.value!.point;
      r.elapse(const Duration(seconds: 2));
      await t.pump(const Duration(milliseconds: 600));
      expect(r.controller.position.value!.point, before);
      expect(r.controller.reason, 'staleOrientation');
      expect(r.controller.showTravelArrow, false);
      expect(find.byKey(const Key('live-recover')), findsOneWidget);
      await unmountLive(t);
      await closeTracking(t, r.controller);
    },
  );

  testWidgets(
    'Ambiguous junction opens real graph choices and marks recommendation without confirming an anchor',
    (t) async {
      final r = (await t.runAsync(
        () => LiveTrackingReplay.create(ambiguous: true),
      ))!;
      await t.runAsync(r.begin);
      r.controller.confirmGeometry(r.edge('J', 'K').id, true);
      await mountGuided(t, r);
      r.walk(11);
      await t.pump(const Duration(milliseconds: 220));
      expect(r.controller.reason, 'junctionConfirmation');
      expect(t.widget<Stepper>(find.byType(Stepper)).currentStep, 3);
      expect(find.textContaining('Điểm này vẫn là ước lượng'), findsOneWidget);
      final choices = t.widget<DropdownButtonFormField<String>>(
        find.byKey(ValueKey('live-edge-${r.node('J').id}-null')),
      );
      expect(choices.initialValue, isNotNull);
      // Every same-floor outgoing corridor, including the off-route same-heading K, is available.
      final rendered = find.byType(DropdownButton<String>).last;
      final button = t.widget<DropdownButton<String>>(rendered);
      expect(button.items!.length, r.graph.outgoing(r.node('J').id).length);
      expect(
        button.items!.any((item) => item.value == r.edge('J', 'K').id),
        true,
      );
      expect(r.controller.reanchors, 1);
      await unmountLive(t);
      await closeTracking(t, r.controller);
    },
  );

  testWidgets(
    'Budget warning and recovery open location stage without silently resetting budget',
    (t) async {
      final r = (await t.runAsync(LiveTrackingReplay.create))!;
      await t.runAsync(() => r.begin(stride: .2));
      await mountGuided(t, r);
      r.walk(32);
      await t.pump(const Duration(milliseconds: 220));
      expect(find.byKey(const Key('live-budget-warning')), findsOneWidget);
      r.walk(9);
      await t.pump(const Duration(milliseconds: 220));
      expect(r.controller.reason, 'anchorAged');
      await liveTap(t, const Key('live-recover'));
      expect(t.widget<Stepper>(find.byType(Stepper)).currentStep, 0);
      expect(r.controller.stepsSinceAnchor, 41);
      await liveTap(t, const Key('live-confirm-anchor'));
      expect(r.controller.stepsSinceAnchor, 0);
      expect(
        r.controller.position.value!.source,
        PositionSource.manualExperiment,
      );
      await unmountLive(t);
      await closeTracking(t, r.controller);
    },
  );

  testWidgets(
    'Manual fallback during unfinished setup remains actionable and unmount has no listener leak',
    (t) async {
      final r = (await t.runAsync(LiveTrackingReplay.create))!;
      var calls = 0;
      await mountGuided(
        t,
        r,
        onManual: () async {
          calls++;
        },
      );
      await liveTap(t, const Key('live-manual'));
      expect(calls, 1);
      expect(r.controller.canIntegrate, false);
      await unmountLive(t);
      await closeTracking(t, r.controller);
      expect(r.fake.disposed, true);
    },
  );
  testWidgets(
    'Estimated destination explains explicit arrival confirmation and leaves manual fallback actionable',
    (t) async {
      final r = (await t.runAsync(LiveTrackingReplay.create))!;
      await t.runAsync(r.begin);
      r.walk(20);
      var manual = 0;
      await mountGuided(
        t,
        r,
        onManual: () async {
          manual++;
        },
      );
      expect(
        find.textContaining('Chấm xanh không tự xác nhận đã đến.'),
        findsOneWidget,
      );
      expect(r.controller.status, isNot(TrackingStatus.finished));
      expect(r.controller.corrections, 0);
      await liveTap(t, const Key('live-manual'));
      expect(manual, 1);
      await unmountLive(t);
      await closeTracking(t, r.controller);
    },
  );
}
