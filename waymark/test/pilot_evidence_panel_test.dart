import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/indoor_tracking/debug/pilot_evidence_panel.dart';
import 'package:waymark/features/indoor_tracking/debug/pilot_evidence.dart';
import 'package:waymark/features/indoor_tracking/live_tracking_panel.dart';
import 'package:waymark/features/indoor_tracking/pdr_engine.dart';
import 'package:waymark/features/indoor_tracking/sensors/sensor_models.dart';
import 'package:waymark/features/navigation/navigation_page.dart';

import 'fixtures/published_live_fixture.dart';
import 'support/live_tracking_replay.dart';
import 'support/fake_sensor_provider.dart';
import 'live_navigation_ui_test.dart'
    show liveTap, waitLive, cacheLiveMap, unmountLive;

void main() {
  testWidgets(
    'Pilot UI exports only on explicit tap, defaults NOT TESTED, rejects invalid field inputs',
    (t) async {
      String? copied;
      var writes = 0;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
            writes++;
          }
          return null;
        },
      );
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PilotEvidencePanel(mode: PilotMode.published),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(copied, isNull);
      expect(writes, 0);
      await liveTap(t, const Key('pilot-copy-report'));
      final report = jsonDecode(copied!) as Map;
      expect(
        (report['checklist'] as Map).values.every((x) => x == 'NOT TESTED'),
        true,
      );
      expect(report['tracking'], isNull);
      expect(report['physicalAccuracy'], 'NOT_VERIFIED');
      final title = find.text(
        'Lượt đo thật • nhập số quan sát, không lấy fixture làm chuẩn',
      );
      await t.ensureVisible(title);
      await t.tap(title);
      await t.pumpAndSettle();
      await liveTap(t, const Key('pilot-save-measurement'));
      expect(find.byKey(const Key('pilot-input-error')), findsOneWidget);
      await liveTap(t, const Key('pilot-copy-report'));
      expect(jsonDecode(copied!)['userMeasuredTrial'], isNull);
      await unmountLive(t);
    },
  );
  testWidgets(
    'Published steps reuse the preflight report; manual fallback disposes the existing session',
    (t) async {
      final f = (await t.runAsync(PublishedLiveFixture.create))!,
          fake = FakeSensorProvider();
      await cacheLiveMap(t, f.session.map);
      await t.pumpWidget(
        MaterialApp(
          home: NavigationPage(
            route: f.route,
            localMap: f.session.map,
            liveSensorProvider: fake,
          ),
        ),
      );
      await t.pumpAndSettle();
      await liveTap(t, const Key('enable-live-navigation'));
      await waitLive(t);
      final panel = t.widget<LiveTrackingPanel>(find.byType(LiveTrackingPanel));
      final report = panel.readiness!, c = panel.controller;
      c.manualAnchor(c.graph.nodes.values.first.id);
      c.setStride(StrideCalibration(.5));
      final starting = c.startSensors();
      await t.pump();
      await starting;
      c.confirmEdge(
        c.graph.edges.values.first.id,
        straightGeometry: true,
        manualDirection: true,
      );
      String? liveReport;
      if (const bool.fromEnvironment('WAYMARK_LIVE_TEST')) {
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              liveReport = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        await liveTap(t, const Key('live-diagnostics'));
        await liveTap(t, const Key('pilot-begin'));
      }
      for (var i = 0; i < 3; i++) {
        fake.emit(
          SensorKind.stepDetector,
          timestamp: 1000 + i * 1000,
          sequence: i + 1,
        );
      }
      await t.pump(const Duration(milliseconds: 220));
      expect(
        t.widget<LiveTrackingPanel>(find.byType(LiveTrackingPanel)).readiness,
        same(report),
      );
      await liveTap(t, const Key('live-manual'));
      expect(fake.disposed, true);
      expect(find.byType(LiveTrackingPanel), findsNothing);
      if (const bool.fromEnvironment('WAYMARK_LIVE_TEST')) {
        final closed = find.text('Pilot report • phiên Live vừa đóng');
        await t.ensureVisible(closed);
        await t.tap(closed);
        await t.pumpAndSettle();
        await liveTap(t, const Key('pilot-copy-report'));
        expect(
          jsonDecode(liveReport!)['tracking']['trackingState'],
          'disposed',
        );
        expect(
          jsonDecode(
            liveReport!,
          )['observationWindow']['detectorAcceptedEvents'],
          3,
        );
      }
      await unmountLive(t);
    },
  );
  testWidgets(
    'A closed Live session keeps a frozen report and permits explicit fallback checklist evidence',
    (t) async {
      final r = (await t.runAsync(LiveTrackingReplay.create))!;
      await t.runAsync(() => r.begin(stride: .5));
      final s = PilotEvidenceSession(mode: PilotMode.local);
      s.begin(controller: r.controller);
      r.walk(2);
      await t.runAsync(r.controller.close);
      s.freezeClosedSession(r.controller, null);
      r.controller.dispose();
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PilotEvidencePanel(mode: PilotMode.local, session: s),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final title = find.text('Checklist Published Pilot (do người thử ghi)');
      await t.ensureVisible(title);
      await t.tap(title);
      await t.pumpAndSettle();
      await liveTap(t, const Key('pilot-check-manualFallback'));
      await t.tap(find.text('PASS').last);
      await t.pumpAndSettle();
      await liveTap(t, const Key('pilot-copy-report'));
      final data = jsonDecode(copied!) as Map;
      expect(data['tracking']['trackingState'], 'disposed');
      expect(data['observationWindow']['detectorAcceptedEvents'], 2);
      expect(data['checklist']['manualFallback'], 'PASS');
      expect(data['physicalAccuracy'], 'NOT_VERIFIED');
      await unmountLive(t);
      s.dispose();
    },
  );
}
