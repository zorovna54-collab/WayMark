import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:waymark/features/admin/map_project_cloud_page.dart';
import 'package:waymark/features/admin/draft_server_session.dart';
import 'package:waymark/features/admin/local_map_project.dart';
import 'package:waymark/features/navigation/manual_navigation.dart';
import 'package:waymark/features/navigation/navigation_page.dart';
import 'package:waymark/features/scanner/scanner_page.dart';
import 'package:waymark/features/search/local_map_search_page.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/map_draft_api_service.dart';
import 'package:waymark/services/published_map_api_service.dart';

import 'fixtures/published_map_fixture.dart';
import 'floor_image_cleanup_test.dart' show cleanupTestImage;
import 'scanner_camera_test.dart' show CameraFake;

class SessionApi extends PublishedMapApiService {
  SessionApi(this.session);
  final PublishedMapSession session;
  @override
  Future<PublishedMapSession> loadQr(String payload) async => session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(AuthSession.clear);
  test(
    'QR tokens accept only public locators; never route to scanned remote host',
    () {
      final token = List.filled(64, 'a').join();
      expect(publicQrToken(' WMQR1:$token '), token);
      expect(publicQrToken('https://untrusted.test/q/$token'), token);
      for (final value in [
        'N01',
        'WM-DEMO-2A-START',
        'WMQR1:../x',
        'WMQR1:JWT',
        'https://test/q/nope',
      ]) {
        expect(publicQrToken(value), isNull);
      }
    },
  );
  test('Server mapper preserves Node destinations, Landmark, legacy Room and stable IDs', () async {
    final fixture = PublishedMapFixture(await cleanupTestImage());
    final floor = fixture.project.floors[1];
    final c = DraftServerMapper.content(floor, null);
    final restored = DraftServerMapper.fromContent(
      c,
      siteId: 1,
      buildingId: 1,
      floor: floor.floor,
    );
    expect(restored.nodes.last.searchableAsDestination, true);
    expect(restored.nodes.last.displayName, 'Destination I');
    expect(restored.nodes.last.landmarkNote, 'Sign I');
    expect(restored.nodeIds, floor.nodeIds);
    expect(restored.edgeIds, floor.edgeIds);
  });
  test('Public QR loads detached 3 floor snapshot with images and route; app JWT unchanged and never sent', () async {
    AuthSession.accessToken = 'creator-session-to-preserve';
    final fixture = PublishedMapFixture(await cleanupTestImage());
    final session = await fixture.api.loadQr(fixture.payload);
    expect(session.project.floors.length, 3);
    expect(session.project.links.length, 2);
    expect(
      session.project.floors.every((f) => f.image != null && f.places.isEmpty),
      true,
    );
    final target = session.map.destinationNodes.last;
    final route = session.map.routeToNode(
      session.startKey,
      target.nodeId,
      target.floorId,
    );
    expect(route.totalDistanceMeters, 30);
    expect(route.nodes.map((n) => n.floor.floorCode).toSet(), {'G', 'I', 'II'});
    expect(
      session.map.landmarkNoteForNode(
        route.nodes.last.id,
        route.nodes.last.floor.id,
      ),
      'Sign II',
    );
    expect(AuthSession.accessToken, 'creator-session-to-preserve');
    expect(
      fixture.calls.every((r) => r.headers['Authorization'] == null),
      true,
    );
    final first = session.map.graph.nodes.first.x;
    fixture.project.floors.first.putNode(
      fixture.project.floors.first.nodes.first.at(.9, .9),
      replace: true,
    );
    expect(session.map.graph.nodes.first.x, first);
    final reopened = await LocalMapProject.decode(session.project.encode());
    expect(
      reopened.links.map((l) => l.id),
      session.project.links.map((l) => l.id),
    );
  });
  for (final status in [404, 409, 410, 503]) {
    test(
      'Public resolve HTTP $status fails clearly without changing draft/AuthSession',
      () async {
        final fixture = PublishedMapFixture(await cleanupTestImage())
          ..status = status;
        AuthSession.accessToken = 'unchanged';
        final before = fixture.project.encode();
        await expectLater(
          fixture.api.loadQr(fixture.payload),
          throwsA(
            isA<MapDraftApiException>().having(
              (e) => e.status,
              'status',
              status,
            ),
          ),
        );
        expect(fixture.project.encode(), before);
        expect(AuthSession.accessToken, 'unchanged');
      },
    );
  }
  test(
    'Private save reuses JWT and project graph schema; no embedded Base64',
    () async {
      final fixture = PublishedMapFixture(await cleanupTestImage());
      await expectLater(
        fixture.api.save('map', fixture.content),
        throwsA(
          isA<MapDraftApiException>().having((e) => e.status, 'status', 401),
        ),
      );
      AuthSession.accessToken = 'creator-fixture';
      await fixture.api.save('map', fixture.content);
      expect((fixture.lastPrivateBody as Map)['content'], fixture.content);
      expect(fixture.calls.last.body, isNot(contains('base64')));
      expect(fixture.calls.last.followRedirects, false);
    },
  );
  test('QR relocalization pinned map/version/floor/node; revoked/offline cannot advance', () async {
    final fixture = PublishedMapFixture(await cleanupTestImage());
    final session = await fixture.api.loadQr(fixture.payload);
    final end = session.map.destinationNodes.last;
    final route = session.map.routeToNode(
      session.startKey,
      end.nodeId,
      end.floorId,
    );
    final manual = ManualNavigation(
      route,
      localPreview: true,
      allowLocalQr: true,
    );
    final next = fixture.project.floors.first;
    fixture.nextFloor = next.localWorkspaceId!;
    fixture.nextNode = next.nodeId('STAIR');
    final loc = await session.map.resolvePublishedQr!(fixture.payload);
    expect(manual.acceptQr(manual.inspectQr(loc)), true);
    expect(manual.nodeIndex, 1);
    fixture.resolvedVersion = 2;
    await expectLater(
      session.map.resolvePublishedQr!(fixture.payload),
      throwsFormatException,
    );
    expect(manual.nodeIndex, 1);
    fixture.resolvedVersion = 1;
    fixture.nextFloor = fixture.project.floors[1].localWorkspaceId!;
    await expectLater(
      session.map.resolvePublishedQr!(fixture.payload),
      throwsFormatException,
    ); // Node GUID of G cannot be used as floor I.
    fixture.status = 410;
    await expectLater(
      session.map.resolvePublishedQr!(fixture.payload),
      throwsA(isA<MapDraftApiException>()),
    );
    expect(manual.nodeIndex, 1);
    fixture.status = 200;
    fixture.offline = true;
    await expectLater(
      session.map.resolvePublishedQr!(fixture.payload),
      throwsA(isA<MapDraftApiException>()),
    );
    expect(manual.nodeIndex, 1);
  });
  test('Reroute uses directed pinned graph and original destination, not backend demo graph', () async {
    final fixture = PublishedMapFixture(await cleanupTestImage());
    final session = await fixture.api.loadQr(fixture.payload);
    final target = session.map.destinationNodes.last;
    final old = session.map.routeToNode(
      session.startKey,
      target.nodeId,
      target.floorId,
    );
    final mid = fixture.project.floors[1];
    final location = session.map.stableLocation(
      mid.localWorkspaceId!,
      mid.nodeId('START'),
      fixture.payload,
    );
    final rerouted = session.map.rerouteFromLocation(location, old);
    expect(rerouted.totalDistanceMeters, 20);
    expect(rerouted.destination.id, old.destination.id);
    expect(fixture.calls.where((c) => c.method != 'GET'), isEmpty);
  });
  test('QR PNG export has real pixels and quiet zone', () async {
    final payload = 'WMQR1:${List.filled(64, 'a').join()}';
    final png = await nodeQrPng(payload);
    expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(png.length, greaterThan(1000));
  });

  testWidgets(
    'Published QR UI: cancel reroute, next node, wrong version and revoked QR preserve state',
    (t) async {
      final original = MobileScannerPlatform.instance, camera = CameraFake();
      MobileScannerPlatform.instance = camera;
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        MobileScannerPlatform.instance = original;
        await camera.captures.close();
      });
      final fixture = PublishedMapFixture(
        (await t.runAsync(cleanupTestImage))!,
      );
      final session = (await t.runAsync(
        () => fixture.api.loadQr(fixture.payload),
      ))!;
      final destination = session.map.destinationNodes.last;
      final route = session.map.routeToNode(
        session.startKey,
        destination.nodeId,
        destination.floorId,
      );
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) =>
                TextButton(onPressed: () {}, child: const Text('Init')),
          ),
        ),
      );
      await t.runAsync(
        () => Future.wait([
          for (final f in [1, 2, 3])
            precacheImage(
              session.map.imageFor(f)!,
              t.element(find.text('Init')),
            ),
        ]),
      );
      await t.pumpWidget(
        MaterialApp(
          home: NavigationPage(route: route, localMap: session.map),
        ),
      );
      await t.pumpAndSettle();
      Future<void> scan() async {
        await t.tap(find.text('Quét QR xác nhận vị trí'));
        await t.pumpAndSettle();
        camera.captures.add(
          BarcodeCapture(barcodes: [Barcode(rawValue: fixture.payload)]),
        );
        await t.pumpAndSettle();
      }

      final middle = fixture.project.floors[1];
      fixture.nextFloor = middle.localWorkspaceId!;
      fixture.nextNode = middle.nodeId('START');
      await scan();
      expect(find.text('QR ngoài tuyến • tính lại?'), findsOneWidget);
      await t.tap(find.text('Hủy'));
      await t.pumpAndSettle();
      expect(find.textContaining('Bước 1/5'), findsOneWidget);
      final ground = fixture.project.floors.first;
      fixture.nextFloor = ground.localWorkspaceId!;
      fixture.nextNode = ground.nodeId('STAIR');
      await scan();
      expect(find.textContaining('Bước 2/5'), findsOneWidget);
      fixture.resolvedVersion = 2;
      await scan();
      expect(find.textContaining('phiên bản khác'), findsOneWidget);
      expect(find.textContaining('Bước 2/5'), findsOneWidget);
      fixture.resolvedVersion = 1;
      fixture.status = 410;
      await scan();
      expect(find.textContaining('thu hồi'), findsOneWidget);
      expect(find.textContaining('Bước 2/5'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Scanner -> public snapshot -> locked Search -> Preview -> manual Navigation, with fake camera',
    (t) async {
      final oldCamera = MobileScannerPlatform.instance, fake = CameraFake();
      MobileScannerPlatform.instance = fake;
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        MobileScannerPlatform.instance = oldCamera;
        await fake.captures.close();
      });
      final fixture = PublishedMapFixture(
        (await t.runAsync(cleanupTestImage))!,
      );
      final session = (await t.runAsync(
        () => fixture.api.loadQr(fixture.payload),
      ))!;
      AuthSession.accessToken = 'kept-session';
      await t.pumpWidget(
        MaterialApp(home: ScannerPage(publishedApi: SessionApi(session))),
      );
      await t.pumpAndSettle();
      fake.captures.add(
        BarcodeCapture(barcodes: [Barcode(rawValue: fixture.payload)]),
      );
      await t.pumpAndSettle();
      expect(find.text('Đã tải snapshot Published'), findsOneWidget);
      await t.tap(find.text('Chọn điểm đến'));
      await t.pumpAndSettle();
      final context = t.element(find.byType(LocalMapSearchPage));
      await t.runAsync(
        () => Future.wait([
          for (final f in [1, 2, 3])
            precacheImage(session.map.imageFor(f)!, context),
        ]),
      );
      final dropdown = t.widget<DropdownButtonFormField<String>>(
        find.byKey(const Key('local-start-node')),
      );
      expect(dropdown.onChanged, isNull);
      await t.ensureVisible(find.textContaining('Destination II').first);
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Destination II').first);
      await t.pumpAndSettle();
      expect(find.text('30 m'), findsWidgets);
      await t.ensureVisible(find.text('Bắt đầu dẫn đường'));
      await t.pumpAndSettle();
      await t.tap(find.text('Bắt đầu dẫn đường'));
      await t.pumpAndSettle();
      expect(find.byType(NavigationPage), findsOneWidget);
      expect(find.text('Quét QR xác nhận vị trí'), findsOneWidget);
      expect(AuthSession.accessToken, 'kept-session');
      expect(t.takeException(), isNull);
    },
  );
}
