import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/indoor_tracking/indoor_tracking_controller.dart';
import 'package:waymark/features/indoor_tracking/indoor_position.dart';
import 'package:waymark/features/indoor_tracking/pdr_engine.dart';
import 'package:waymark/features/indoor_tracking/tracking_graph.dart';
import 'package:waymark/features/indoor_tracking/sensors/sensor_models.dart';
import 'package:waymark/models/route_models.dart';

import 'fixtures/published_map_fixture.dart';
import 'floor_image_cleanup_test.dart' show cleanupTestImage;
import 'live_tracking_graph_test.dart' show trackingFixture;
import 'support/fake_sensor_provider.dart';

Future<void> settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'A QR reply after controller disposal cannot revive the session',
    () async {
      final f = await trackingFixture(), fake = FakeSensorProvider();
      final pending = Completer<WayMarkMapLocation>();
      f.map.resolvePublishedQr = (_) => pending.future;
      final c = IndoorTrackingController(
        graph: f.graph,
        map: f.map,
        route: f.map.routeToRoom(
          f.map.startChoices.first.key,
          f.map.rooms.first.id,
        ),
        provider: fake,
      );
      final ticket = await c.beginRelocalization();
      final correction = c.completeRelocalization('never-exported', ticket);
      await c.close();
      final n = f.graph.nodes.values.first;
      pending.complete(
        f.map.stableLocation(n.floorKey, n.id, 'never-exported'),
      );
      expect(await correction, false);
      expect(c.corrections, 0);
      expect(fake.disposed, true);
      c.dispose();
    },
  );
  test('Accepted real-kind steps -> position; no-step/rotation/counter do not move; finish stops', () async {
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
    final node = f.graph.nodes.values.first,
        edge = f.graph.outgoing(f.graph.nodes.values.first.id).first;
    c.manualAnchor(node.id);
    c.setStride(StrideCalibration(.5));
    await c.startSensors();
    fake.emit(
      SensorKind.rotationVector,
      timestamp: 1000,
      values: [0, 0, 0, 1, -1],
    );
    c.confirmEdge(edge.id, straightGeometry: true);
    final initial = c.position.value!.point;
    fake.emit(
      SensorKind.rotationVector,
      timestamp: 1100,
      sequence: 2,
      values: [0, 0, 0, 1, -1],
    );
    fake.emit(SensorKind.stepCounter, timestamp: 1200, values: [500]);
    expect(c.position.value!.point, initial);
    fake.emit(SensorKind.stepDetector, timestamp: 2000);
    expect(c.position.value!.progressMeters, .5);
    fake.emit(SensorKind.stepDetector, timestamp: 2000);
    expect(c.position.value!.progressMeters, .5);
    expect(c.integratedDistance, .5);
    await c.finish();
    fake.emit(
      SensorKind.stepDetector,
      timestamp: 3000,
      sequence: 3,
      late: true,
    );
    expect(c.status, TrackingStatus.finished);
    expect(c.position.value!.progressMeters, .5);
    expect(fake.running, false);
  });

  test('Pause/resume retains only an uncertain pose; requires explicit alignment again', () async {
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
    final edge = f.graph.edges.values.first;
    c.confirmEdge(edge.id, straightGeometry: true, manualDirection: true);
    fake.emit(SensorKind.stepDetector, timestamp: 1000);
    final oldGeneration = fake.generation;
    await c.pause();
    await c.startSensors();
    fake.emit(
      SensorKind.stepDetector,
      timestamp: 2000,
      forGeneration: oldGeneration,
      late: true,
    );
    fake.emit(SensorKind.stepDetector, timestamp: 3000, sequence: 2);
    expect(c.position.value!.progressMeters, .5);
    c.confirmEdge(
      edge.id,
      straightGeometry: true,
      manualDirection: true,
      stayedStill: true,
    );
    fake.emit(SensorKind.stepDetector, timestamp: 4000, sequence: 3);
    expect(c.position.value!.progressMeters, 1);
    await c.setVisible(false);
    expect(fake.running, false);
    await c.setVisible(true);
    expect(fake.running, false);
  });

  test(
    'Missing detector/denied permission leave static/manual fallback',
    () async {
      for (final denied in [false, true]) {
        final f = await trackingFixture(), fake = FakeSensorProvider();
        if (denied) {
          fake.permission = MotionPermission.denied;
        } else {
          fake.available.remove(SensorKind.stepDetector);
        }
        final c = IndoorTrackingController(
          graph: f.graph,
          map: f.map,
          route: f.map.routeToRoom(
            f.map.startChoices.first.key,
            f.map.rooms.first.id,
          ),
          provider: fake,
        );
        await c.startSensors();
        expect(
          c.status,
          denied
              ? TrackingStatus.permissionDenied
              : TrackingStatus.sensorUnavailable,
        );
        expect(fake.running, false);
        expect(fake.permissionRequests, 0);
        await c.close();
        c.dispose();
      }
    },
  );

  test('Floor transition never interpolates; explicit new-floor anchor is required', () async {
    final f = await trackingFixture(), fake = FakeSensorProvider();
    final c = IndoorTrackingController(
      graph: f.graph,
      map: f.map,
      route: f.map.routeToRoom(
        f.map.startChoices.first.key,
        f.map.rooms.last.id,
      ),
      provider: fake,
    );
    addTearDown(() async {
      await c.close();
      c.dispose();
    });
    final link = f.graph.edges.values.firstWhere(f.graph.isTransition);
    c.manualAnchor(link.from);
    c.setStride(StrideCalibration(.5));
    await c.startSensors();
    c.confirmEdge(link.id, straightGeometry: false);
    await settle();
    expect(c.position.value!.kind, PositionKind.floorTransition);
    expect(c.position.value!.floorKey, f.graph.nodes[link.from]!.floorKey);
    fake.emit(SensorKind.stepDetector, timestamp: 2000, late: true);
    expect(c.position.value!.targetFloorKey, f.graph.nodes[link.to]!.floorKey);
    c.manualAnchor(link.to);
    expect(c.position.value!.floorKey, f.graph.nodes[link.to]!.floorKey);
    expect(c.position.value!.edgeId, isNull);
  });

  test('Overflow lowers confidence and fences motion; no raw exception or token in clipboard text', () async {
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
    fake.statusEvents.add(
      SensorProviderStatus(
        SensorProviderPhase.overflow,
        fake.generation,
        'SECRET-DO-NOT-EXPORT',
      ),
    );
    fake.emit(SensorKind.stepDetector, timestamp: 2000);
    expect(c.position.value!.progressMeters, 0);
    expect(c.reason, 'sensorOverflow');
    expect(c.sanitizedDiagnostics(), isNot(contains('SECRET-DO-NOT-EXPORT')));
    expect(
      c.sanitizedDiagnostics(),
      isNot(contains(f.graph.nodes.values.first.id)),
    );
  });

  test('Reroute only on confirmed off-route anchors, with cooldown; estimates alone never call it', () async {
    final f = await trackingFixture(), fake = FakeSensorProvider();
    var calls = 0;
    var now = DateTime(2026, 10, 28);
    final c = IndoorTrackingController(
      graph: f.graph,
      map: f.map,
      route: f.map.routeToRoom(
        f.map.startChoices.first.key,
        f.map.rooms.first.id,
      ),
      provider: fake,
      now: () => now,
      onConfirmedOffRoute: (_) async {
        calls++;
      },
    );
    addTearDown(() async {
      await c.close();
      c.dispose();
    });
    final off = f.graph.nodes.values.firstWhere(
      (n) => n.floorKey != f.graph.nodes.values.first.floorKey,
    );
    c.manualAnchor(off.id);
    await settle();
    expect(calls, 1);
    c.manualAnchor(off.id);
    await settle();
    expect(calls, 1);
    now = now.add(const Duration(seconds: 9));
    c.manualAnchor(off.id);
    await settle();
    expect(calls, 2);
  });

  for (final mode in [
    'valid',
    'revoked',
    'wrongVersion',
    'wrongMap',
    'missingNode',
    'missingFloor',
    'offline',
  ]) {
    test(
      'Published QR correction $mode is atomic and pins the existing snapshot',
      () async {
        final fixture = PublishedMapFixture(await cleanupTestImage());
        final s = await fixture.api.loadQr(fixture.payload);
        final graph = await TrackingGraph.fromNavigation(s.map),
            fake = FakeSensorProvider();
        final target = s.map.destinationNodes.first;
        final c = IndoorTrackingController(
          graph: graph,
          map: s.map,
          route: s.map.routeToNode(s.startKey, target.nodeId, target.floorId),
          provider: fake,
        );
        addTearDown(() async {
          await c.close();
          c.dispose();
        });
        c.manualAnchor(graph.nodes.values.first.id);
        final before = c.position.value;
        final next = fixture.project.floors.first;
        fixture.nextNode = next.nodeId('STAIR');
        if (mode == 'revoked') fixture.status = 410;
        if (mode == 'wrongVersion') fixture.resolvedVersion = 2;
        if (mode == 'wrongMap') {
          s.map.publication = (
            mapId: '22222222-2222-4222-8222-222222222222',
            version: 1,
          );
        }
        if (mode == 'missingFloor') {
          fixture.nextFloor = fixture.project.floors[1].localWorkspaceId!;
        }
        if (mode == 'missingNode') {
          fixture.nextNode = '99999999-9999-4999-8999-999999999999';
        }
        if (mode == 'offline') fixture.offline = true;
        final ticket = await c.beginRelocalization();
        final accepted = await c.completeRelocalization(
          fixture.payload,
          ticket,
        );
        expect(accepted, mode == 'valid');
        expect(c.graph.key, graph.key);
        if (accepted) {
          expect(c.position.value!.nodeId, fixture.nextNode);
          expect(c.position.value!.source, PositionSource.qr);
          expect(c.beforeLastCorrection, same(before));
        } else {
          expect(c.position.value!.point, before!.point);
        }
        expect(c.sanitizedDiagnostics(), isNot(contains(fixture.token)));
        expect(fixture.calls.every((r) => r.method == 'GET'), true);
      },
    );
  }

  test(
    'Late QR reply cannot overwrite pause/replacement/disposed session',
    () async {
      final f = await trackingFixture(), fake = FakeSensorProvider();
      final pending = Completer<WayMarkMapLocation>();
      f.map.resolvePublishedQr = (_) => pending.future;
      final c = IndoorTrackingController(
        graph: f.graph,
        map: f.map,
        route: f.map.routeToRoom(
          f.map.startChoices.first.key,
          f.map.rooms.first.id,
        ),
        provider: fake,
      );
      c.manualAnchor(f.graph.nodes.values.first.id);
      final before = c.position.value!.point;
      final ticket = await c.beginRelocalization();
      final correction = c.completeRelocalization('not-logged', ticket);
      await c.pause();
      final n = f.graph.nodes.values.last;
      pending.complete(f.map.stableLocation(n.floorKey, n.id, 'not-logged'));
      expect(await correction, false);
      expect(c.position.value!.point, before);
      await c.close();
      c.dispose();
    },
  );
}
