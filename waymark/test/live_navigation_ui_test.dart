import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:waymark/features/indoor_tracking/blue_dot_overlay.dart';
import 'package:waymark/features/indoor_tracking/indoor_tracking_controller.dart';
import 'package:waymark/features/indoor_tracking/live_tracking_panel.dart';
import 'package:waymark/features/indoor_tracking/pdr_engine.dart';
import 'package:waymark/features/indoor_tracking/sensors/sensor_models.dart';
import 'package:waymark/features/navigation/navigation_page.dart';
import 'package:waymark/features/navigation/local_map_navigation.dart';
import 'package:waymark/features/route/floor_plan_canvas.dart';
import 'package:waymark/features/route/floor_route_map.dart';

import 'fixtures/published_map_fixture.dart';
import 'floor_image_cleanup_test.dart' show cleanupTestImage;
import 'live_tracking_graph_test.dart' show trackingFixture;
import 'scanner_camera_test.dart' show CameraFake;
import 'support/fake_sensor_provider.dart';

Future<void> liveTap(WidgetTester t, Key key) async {
  final finder = find.byKey(key);
  await t.ensureVisible(finder);
  await t.tap(finder);
  await t.pumpAndSettle();
  for (var i = 0; i < 5; i++) {
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    await t.pump();
  }
}

Future<void> waitLive(WidgetTester t) async {
  for (
    var i = 0;
    i < 40 && find.byType(LiveTrackingPanel).evaluate().isEmpty;
    i++
  ) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump();
  }
  expect(find.byType(LiveTrackingPanel), findsOneWidget);
  await t.pumpAndSettle();
}

Future<void> unmountLive(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pumpAndSettle();
  for (var i = 0; i < 8; i++) {
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    await t.pump();
  }
}

Future<void> closeTracking(WidgetTester t, IndoorTrackingController c) async {
  final closing = c.close();
  var done = false;
  closing.then((_) => done = true);
  for (var i = 0; i < 20 && !done; i++) {
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(done, true, reason: 'Tracking cleanup must complete');
  await closing;
  c.dispose();
}

Future<void> cacheLiveMap(WidgetTester t, LocalMapNavigation map) async {
  await t.pumpWidget(const MaterialApp(home: Text('cache-live-map')));
  await t.runAsync(
    () => Future.wait([
      for (final f in [1, 2, 3])
        precacheImage(map.imageFor(f)!, t.element(find.text('cache-live-map'))),
    ]),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Blue dot paints in the contained scene with screen-sized diameter under zoom/pan', () async {
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
    c.manualAnchor(f.graph.nodes.values.first.id);
    final p = c.position.value!, diameters = <int>[];
    expect(blueDotScenePoint(p, 'other-floor', const Size(200, 100)), isNull);
    expect(
      containedFloorSize(const Size(1000, 500), const Size(200, 200)),
      const Size(200, 100),
    );
    for (final scale in [1.0, 2.0, 4.0]) {
      final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
      canvas.drawColor(Colors.white, BlendMode.src);
      canvas.translate(30, 20);
      canvas.scale(scale);
      BlueDotPainter(c, p.floorKey, scale).paint(canvas, const Size(200, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(900, 500);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final center =
          blueDotScenePoint(p, p.floorKey, const Size(200, 100))! * scale +
          const Offset(30, 20);
      final pixels = <int>[];
      for (var dx = -15; dx <= 15; dx++) {
        final n = ((center.dy.round()) * 900 + center.dx.round() + dx) * 4;
        if (bytes.getUint8(n) < 100 && bytes.getUint8(n + 2) > 180) {
          pixels.add(dx);
        }
      }
      expect(pixels, isNotEmpty);
      diameters.add(pixels.last - pixels.first + 1);
      image.dispose();
      picture.dispose();
    }
    expect(diameters.every((d) => (d - diameters.first).abs() <= 1), true);
    await c.close();
    c.dispose();
  });

  testWidgets(
    'Navigation opt-in owns tracking; map/widget identity survives steps; manual fallback and unmount clean up',
    (t) async {
      final f = (await t.runAsync(trackingFixture))!,
          fake = FakeSensorProvider();
      final route = f.map.routeToRoom(
        f.map.startChoices.first.key,
        f.map.rooms.first.id,
      );
      await cacheLiveMap(t, f.map);
      await t.pumpWidget(
        MaterialApp(
          home: NavigationPage(
            route: route,
            localMap: f.map,
            liveSensorProvider: fake,
          ),
        ),
      );
      await t.pumpAndSettle();
      await liveTap(t, const Key('enable-live-navigation'));
      await waitLive(t);
      final c = t
          .widget<LiveTrackingPanel>(find.byType(LiveTrackingPanel))
          .controller;
      c.manualAnchor(f.graph.nodes.values.first.id);
      c.setStride(StrideCalibration(.5));
      final starting = c.startSensors();
      await t.pump();
      await starting;
      c.confirmEdge(
        f.graph.edges.values.first.id,
        straightGeometry: true,
        manualDirection: true,
      );
      final mapState = t.state(find.byType(FloorRouteMap));
      final imageLayer = t.widget(
        find.byKey(const Key('floor-plan-image-layer')),
      );
      fake.emit(SensorKind.stepDetector, timestamp: 1000);
      await t.pump(const Duration(milliseconds: 220));
      expect(c.position.value!.progressMeters, .5);
      expect(t.state(find.byType(FloorRouteMap)), same(mapState));
      expect(
        t.widget(find.byKey(const Key('floor-plan-image-layer'))),
        same(imageLayer),
      );
      expect(
        t
            .widget<ElevatedButton>(find.byKey(const Key('navigation-confirm')))
            .onPressed,
        isNull,
      );
      await liveTap(t, const Key('live-manual'));
      expect(find.byType(LiveTrackingPanel), findsNothing);
      expect(fake.disposed, true);
      expect(
        t
            .widget<ElevatedButton>(find.byKey(const Key('navigation-confirm')))
            .onPressed,
        isNotNull,
      );
      await unmountLive(t);
    },
  );

  testWidgets(
    'Covered route stops sensor even when app remains foreground; return needs explicit resume',
    (t) async {
      final f = (await t.runAsync(trackingFixture))!,
          fake = FakeSensorProvider();
      final c = IndoorTrackingController(
        graph: f.graph,
        map: f.map,
        route: f.map.routeToRoom(
          f.map.startChoices.first.key,
          f.map.rooms.first.id,
        ),
        provider: fake,
      );
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: Scaffold(
            body: SingleChildScrollView(
              child: LiveTrackingPanel(
                controller: c,
                onScan: () async {},
                onManual: () async {},
              ),
            ),
          ),
        ),
      );
      final starting = c.startSensors();
      await t.pump();
      await starting;
      await t.pumpAndSettle();
      final covered = nav.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Covered')),
        ),
      );
      await t.pumpAndSettle();
      expect(fake.running, false);
      nav.currentState!.pop();
      await covered;
      await t.pumpAndSettle();
      expect(fake.running, false);
      await unmountLive(t);
      await closeTracking(t, c);
    },
  );

  testWidgets(
    'Published live QR pauses camera overlay atomically and keeps snapshot version',
    (t) async {
      final old = MobileScannerPlatform.instance, camera = CameraFake();
      MobileScannerPlatform.instance = camera;
      addTearDown(() async {
        MobileScannerPlatform.instance = old;
        await camera.captures.close();
      });
      final fixture = PublishedMapFixture(
        (await t.runAsync(cleanupTestImage))!,
      );
      final session = (await t.runAsync(
        () => fixture.api.loadQr(fixture.payload),
      ))!;
      final target = session.map.destinationNodes.first,
          fake = FakeSensorProvider();
      await cacheLiveMap(t, session.map);
      await t.pumpWidget(
        MaterialApp(
          home: NavigationPage(
            localMap: session.map,
            route: session.map.routeToNode(
              session.startKey,
              target.nodeId,
              target.floorId,
            ),
            liveSensorProvider: fake,
          ),
        ),
      );
      await t.pumpAndSettle();
      await liveTap(t, const Key('enable-live-navigation'));
      await waitLive(t);
      final c = t
          .widget<LiveTrackingPanel>(find.byType(LiveTrackingPanel))
          .controller;
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
      fixture.nextNode = fixture.project.floors.first.nodeId('STAIR');
      await liveTap(t, const Key('live-qr'));
      expect(fake.running, false);
      camera.captures.add(
        BarcodeCapture(barcodes: [Barcode(rawValue: fixture.payload)]),
      );
      await t.pumpAndSettle();
      expect(c.corrections, 1);
      expect(c.position.value!.nodeId, fixture.nextNode);
      expect(c.graph.key.version, 1);
      expect(fake.running, false);
      await unmountLive(t);
      expect(fake.disposed, true);
    },
  );

  testWidgets(
    'External route replacement pauses same pinned controller; map replacement disposes it',
    (t) async {
      final f = (await t.runAsync(trackingFixture))!,
          fake = FakeSensorProvider();
      final first = f.map.routeToRoom(
        f.map.startChoices.first.key,
        f.map.rooms.first.id,
      );
      await cacheLiveMap(t, f.map);
      await t.pumpWidget(
        MaterialApp(
          home: NavigationPage(
            route: first,
            localMap: f.map,
            liveSensorProvider: fake,
          ),
        ),
      );
      await t.pumpAndSettle();
      await liveTap(t, const Key('enable-live-navigation'));
      await waitLive(t);
      final c = t
          .widget<LiveTrackingPanel>(find.byType(LiveTrackingPanel))
          .controller;
      final starting = c.startSensors();
      await t.pump();
      await starting;
      final next = f.map.routeToRoom(
        f.map.startChoices.first.key,
        f.map.rooms.last.id,
      );
      await t.pumpWidget(
        MaterialApp(
          home: NavigationPage(
            route: next,
            localMap: f.map,
            liveSensorProvider: fake,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(c.sensorRunning, false);
      expect(
        t.widget<LiveTrackingPanel>(find.byType(LiveTrackingPanel)).controller,
        same(c),
      );
      final other = (await t.runAsync(trackingFixture))!;
      await t.runAsync(
        () => Future.wait([
          for (final id in [1, 2, 3])
            precacheImage(
              other.map.imageFor(id)!,
              t.element(find.byType(LiveTrackingPanel)),
            ),
        ]),
      );
      await t.pumpWidget(
        MaterialApp(
          home: NavigationPage(
            localMap: other.map,
            route: other.map.routeToRoom(
              other.map.startChoices.first.key,
              other.map.rooms.first.id,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(LiveTrackingPanel), findsNothing);
      await unmountLive(t);
      expect(fake.disposed, true);
    },
  );

  testWidgets(
    'Diagnostics clipboard export is explicit and excludes identifiers and tokens',
    (t) async {
      final f = (await t.runAsync(trackingFixture))!,
          fake = FakeSensorProvider();
      final c = IndoorTrackingController(
        graph: f.graph,
        map: f.map,
        route: f.map.routeToRoom(
          f.map.startChoices.first.key,
          f.map.rooms.first.id,
        ),
        provider: fake,
      );
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
              child: LiveTrackingPanel(
                controller: c,
                onScan: () async {},
                onManual: () async {},
              ),
            ),
          ),
        ),
      );
      expect(copied, isNull);
      await liveTap(t, const Key('live-diagnostics'));
      await liveTap(t, const Key('live-copy-diagnostics'));
      expect(copied, contains('physicalAccuracy=NOT_VERIFIED'));
      expect(copied, isNot(contains(f.graph.key.mapId)));
      expect(copied, isNot(contains(f.graph.nodes.values.first.id)));
      expect(copied, isNot(contains('WMQR1:')));
      await unmountLive(t);
      await closeTracking(t, c);
    },
  );
}
