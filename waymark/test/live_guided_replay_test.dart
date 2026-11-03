import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/indoor_tracking/indoor_position.dart';
import 'package:waymark/features/indoor_tracking/pdr_engine.dart';
import 'package:waymark/features/indoor_tracking/indoor_tracking_controller.dart';
import 'package:waymark/features/indoor_tracking/sensors/sensor_models.dart';
import 'package:waymark/models/route_models.dart';

import 'live_tracking_graph_test.dart' show trackingFixture;
import 'support/live_tracking_replay.dart';
import 'support/fake_sensor_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Replay A-J-E continues uniquely from fresh calibrated heading, keeps estimated source and budget', () async {
    final r = await LiveTrackingReplay.create();
    addTearDown(r.close);
    await r.begin();
    r.walk(10);
    expect(r.controller.position.value!.nodeId, r.node('J').id);
    expect(
      r.controller.position.value!.confidence,
      PositionConfidence.uncertain,
    );
    r.step();
    expect(r.controller.position.value!.edgeId, r.edge('J', 'E').id);
    expect(r.controller.position.value!.progressMeters, 1);
    expect(r.controller.position.value!.source, PositionSource.pdr);
    expect(
      r.controller.position.value!.confidence,
      PositionConfidence.estimated,
    );
    expect(r.controller.reanchors, 1);
    expect(r.controller.stepsSinceAnchor, 11);
    expect(
      r.controller.diagnosticEvents.join(),
      contains('edgeContinuedEstimated'),
    );
    r.walk(9);
    expect(r.controller.position.value!.nodeId, r.node('E').id);
    expect(r.controller.status, isNot(TrackingStatus.finished));
    expect(r.controller.estimatedRouteRemaining, 0);
  });

  test('Replay full graph ambiguity holds, explicit different corridor does not create an anchor', () async {
    final r = await LiveTrackingReplay.create(ambiguous: true);
    addTearDown(r.close);
    await r.begin();
    r.controller.confirmGeometry(r.edge('J', 'K').id, true);
    r.walk(11);
    expect(r.controller.reason, 'junctionConfirmation');
    expect(r.controller.position.value!.nodeId, r.node('J').id);
    expect(r.controller.canIntegrate, false);
    r.controller.confirmEdge(r.edge('J', 'K').id, straightGeometry: true);
    expect(r.controller.position.value!.source, PositionSource.pdr);
    expect(
      r.controller.position.value!.confidence,
      PositionConfidence.uncertain,
    );
    r.step();
    expect(r.controller.position.value!.edgeId, r.edge('J', 'K').id);
    expect(r.controller.offRoute, true);
    expect(r.controller.reanchors, 1);
    expect(r.controller.stepsSinceAnchor, 12);
    expect(r.controller.reroutes, 0);
  });

  test('Replay unverified next geometry never auto-continues', () async {
    final r = await LiveTrackingReplay.create();
    addTearDown(r.close);
    await r.begin(nextGeometry: false);
    r.walk(11);
    expect(r.controller.reason, 'junctionConfirmation');
    expect(r.controller.position.value!.nodeId, r.node('J').id);
    expect(r.controller.integratedDistance, 10);
  });

  test(
    'Replay manual bearing cannot prove automatic junction continuation',
    () async {
      final r = await LiveTrackingReplay.create();
      addTearDown(r.close);
      await r.begin(manual: true);
      r.walk(11);
      expect(r.controller.position.value!.nodeId, r.node('J').id);
      expect(r.controller.reason, 'junctionConfirmation');
    },
  );

  test('Replay reverse decreases progress without route bias', () async {
    final r = await LiveTrackingReplay.create();
    addTearDown(r.close);
    await r.begin();
    r.walk(5);
    r.step(yaw: math.pi);
    expect(r.controller.position.value!.progressMeters, 4);
    expect(r.controller.reason, 'reverse');
  });

  test('Replay stop and rotation-only produce no displacement; stale arrow disappears without steps', () async {
    final r = await LiveTrackingReplay.create();
    addTearDown(r.close);
    await r.begin();
    r.step();
    final before = r.controller.position.value!.point;
    r.orientation(math.pi / 2);
    expect(r.controller.position.value!.point, before);
    r.elapse(const Duration(seconds: 2));
    expect(r.controller.showTravelArrow, false);
    expect(r.controller.position.value!.point, before);
    r.step(withOrientation: false);
    expect(r.controller.reason, 'staleOrientation');
    expect(r.controller.position.value!.point, before);
  });

  test(
    'Replay duplicate detector and counter are not extra movements',
    () async {
      final r = await LiveTrackingReplay.create();
      addTearDown(r.close);
      await r.begin();
      r.step();
      r.fake.emit(
        SensorKind.stepDetector,
        timestamp: r.ns + 1000,
        sequence: r.sequence,
      );
      r.fake.emit(
        SensorKind.stepCounter,
        timestamp: r.ns + 2000,
        sequence: ++r.sequence,
        values: [999],
      );
      expect(r.controller.integratedDistance, 1);
      expect(r.controller.acceptedMovements, 1);
      expect(r.controller.sensors.rejectedEvents, greaterThan(0));
    },
  );

  test('Replay budget warns at 32, allows 40, holds 41; only explicit anchor resets it', () async {
    final r = await LiveTrackingReplay.create();
    addTearDown(r.close);
    await r.begin(stride: .2);
    r.walk(32);
    expect(r.controller.budgetNearLimit, true);
    expect(r.controller.remainingBudget, 8);
    r.walk(8);
    expect(r.controller.integratedDistance, closeTo(8, .0001));
    r.step();
    expect(r.controller.reason, 'anchorAged');
    expect(r.controller.requiresAnchor, true);
    expect(r.controller.remainingBudget, 0);
    expect(
      () => r.controller.confirmEdge(
        r.edge('A', 'J').id,
        straightGeometry: true,
        stayedStill: true,
      ),
      throwsFormatException,
    );
    r.controller.setStride(StrideCalibration(.3));
    await r.controller.pause();
    await r.controller.startSensors();
    expect(r.controller.requiresAnchor, true);
    expect(r.controller.stepsSinceAnchor, 41);
    r.controller.manualAnchor(r.node('A').id);
    expect(r.controller.stepsSinceAnchor, 0);
    expect(
      r.controller.position.value!.source,
      PositionSource.manualExperiment,
    );
    expect(
      r.controller.position.value!.confidence,
      PositionConfidence.manualConfirmation,
    );
  });

  test(
    'Replay ten pause/resume cycles fence old generations and need alignment',
    () async {
      final r = await LiveTrackingReplay.create();
      addTearDown(r.close);
      await r.begin(stride: .2);
      r.step();
      for (var i = 0; i < 10; i++) {
        final old = r.fake.generation;
        await r.controller.pause();
        await r.controller.startSensors();
        r.fake.emit(
          SensorKind.stepDetector,
          timestamp: r.ns + 9000,
          sequence: ++r.sequence,
          forGeneration: old,
          late: true,
        );
        r.step();
        expect(r.controller.integratedDistance, closeTo(.2 * (i + 1), .0001));
        r.controller.confirmEdge(
          r.edge('A', 'J').id,
          straightGeometry: true,
          stayedStill: true,
        );
        r.step();
      }
      expect(r.controller.integratedDistance, closeTo(2.2, .0001));
    },
  );

  test('Replay QR atomic correction drops old queued generation and fences late response after route replacement', () async {
    final f = await trackingFixture(), fake = FakeSensorProvider();
    final route = f.map.routeToRoom(
      f.map.startChoices.first.key,
      f.map.rooms.first.id,
    );
    final c = IndoorTrackingController(
      graph: f.graph,
      map: f.map,
      route: route,
      provider: fake,
    );
    addTearDown(() async {
      await c.close();
      c.dispose();
    });
    c.manualAnchor(f.graph.nodes.values.first.id);
    c.setStride(StrideCalibration(.5));
    await c.startSensors();
    final oldGeneration = fake.generation,
        pending = Completer<WayMarkMapLocation>();
    f.map.resolvePublishedQr = (_) => pending.future;
    final ticket = await c.beginRelocalization();
    final correction = c.completeRelocalization('DO-NOT-EXPORT-QR', ticket);
    fake.emit(
      SensorKind.stepDetector,
      timestamp: 9000,
      forGeneration: oldGeneration,
      late: true,
    );
    final n = f.graph.nodes.values.last;
    pending.complete(
      f.map.stableLocation(n.floorKey, n.id, 'DO-NOT-EXPORT-QR'),
    );
    expect(await correction, true);
    expect(c.position.value!.nodeId, n.id);
    expect(c.stepsSinceAnchor, 0);
    expect(c.position.value!.source, PositionSource.qr);
    await c.startSensors();
    fake.emit(
      SensorKind.stepDetector,
      timestamp: 10000,
      forGeneration: oldGeneration,
      late: true,
    );
    expect(c.position.value!.nodeId, n.id);
    final later = Completer<WayMarkMapLocation>();
    f.map.resolvePublishedQr = (_) => later.future;
    final nextTicket = await c.beginRelocalization();
    final reply = c.completeRelocalization('DO-NOT-EXPORT-QR', nextTicket);
    await c.replaceRoute(route);
    later.complete(f.map.stableLocation(n.floorKey, n.id, 'DO-NOT-EXPORT-QR'));
    expect(await reply, false);
    expect(c.corrections, 1);
    expect(c.sanitizedDiagnostics(), isNot(contains('DO-NOT-EXPORT-QR')));
  });

  test(
    'Replay overflow cannot be bypassed by alignment or automatic continuation',
    () async {
      final r = await LiveTrackingReplay.create();
      addTearDown(r.close);
      await r.begin();
      r.walk(10);
      r.fake.statusEvents.add(
        SensorProviderStatus(
          SensorProviderPhase.overflow,
          r.fake.generation,
          'PRIVATE',
        ),
      );
      r.step();
      expect(r.controller.requiresAnchor, true);
      expect(r.controller.position.value!.nodeId, r.node('J').id);
      expect(
        () => r.controller.confirmEdge(
          r.edge('J', 'E').id,
          straightGeometry: true,
        ),
        throwsFormatException,
      );
      expect(r.controller.sanitizedDiagnostics(), isNot(contains('PRIVATE')));
    },
  );

  test(
    'Replay floor transition stops and never interpolates across images',
    () async {
      final r = await LiveTrackingReplay.create();
      addTearDown(r.close);
      await r.begin();
      r.controller.manualAnchor(r.node('S').id);
      final link = r.edge('S', 'S1');
      r.controller.confirmEdge(link.id, straightGeometry: false);
      final p = r.controller.position.value!;
      r.step();
      expect(r.controller.position.value!.point, p.point);
      expect(p.kind, PositionKind.floorTransition);
      r.controller.manualAnchor(r.node('S1').id);
      expect(r.controller.position.value!.floorKey, r.node('S1').floorKey);
      expect(
        r.controller.position.value!.source,
        PositionSource.manualExperiment,
      );
    },
  );

  test('Replay timeline stays bounded and sanitized; cancel during setup closes resources', () async {
    final r = await LiveTrackingReplay.create();
    for (var i = 0; i < 150; i++) {
      r.controller.manualAnchor(r.node('A').id);
    }
    expect(r.controller.timeline.events.length, 96);
    for (final id in [...r.graph.nodes.keys, ...r.graph.edges.keys]) {
      expect(r.controller.sanitizedDiagnostics(), isNot(contains(id)));
    }
    await r.close();
    expect(r.fake.disposed, true);
    expect(r.controller.diagnosticEvents.last, contains('disposed'));
    expect(r.fake.emit(SensorKind.stepDetector), false);
  });

  test('Replay changed published version fences samples, alignment and new anchors', () async {
    final f = await trackingFixture(), fake = FakeSensorProvider();
    final c = IndoorTrackingController(
      graph: f.graph,
      map: f.map,
      route: f.map.routeToRoom(
        f.map.startChoices.first.key,
        f.map.rooms.first.id,
      ),
      provider: fake,
    );
    addTearDown(() async {
      await c.close();
      c.dispose();
    });
    c.manualAnchor(f.graph.nodes.values.first.id);
    c.setStride(StrideCalibration(.5));
    await c.startSensors();
    c.confirmEdge(
      f.graph.edges.values.first.id,
      straightGeometry: true,
      manualDirection: true,
    );
    fake.emit(SensorKind.stepDetector, timestamp: 1000);
    final before = c.position.value!.point;
    f.map.publication = (
      mapId: f.graph.key.mapId,
      version: f.graph.key.version + 1,
    );
    fake.emit(SensorKind.stepDetector, timestamp: 2000, sequence: 2);
    expect(c.reason, 'mapVersionChanged');
    expect(c.position.value!.point, before);
    expect(c.canIntegrate, false);
    expect(
      () => c.manualAnchor(f.graph.nodes.values.first.id),
      throwsFormatException,
    );
    await c.startSensors();
    expect(c.canIntegrate, false);
  });

  for (final denied in [false, true]) {
    test(
      'Replay sensor setup fallback: ${denied ? 'permission denied' : 'detector absent'}',
      () async {
        final fake = FakeSensorProvider();
        if (denied) {
          fake.permission = MotionPermission.denied;
        } else {
          fake.available.remove(SensorKind.stepDetector);
        }
        final r = await LiveTrackingReplay.create(fake: fake);
        addTearDown(r.close);
        r.controller.manualAnchor(r.node('A').id);
        r.controller.setStride(StrideCalibration(1));
        await r.controller.startSensors();
        expect(
          r.controller.status,
          denied
              ? TrackingStatus.permissionDenied
              : TrackingStatus.sensorUnavailable,
        );
        expect(r.controller.canIntegrate, false);
        expect(fake.permissionRequests, 0);
      },
    );
  }
}
