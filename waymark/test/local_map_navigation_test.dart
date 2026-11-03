import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/admin/floor_plan_asset.dart';
import 'package:waymark/features/navigation/local_map_navigation.dart';
import 'package:waymark/features/navigation/manual_navigation.dart';
import 'package:waymark/features/navigation/navigation_page.dart';
import 'package:waymark/features/route/floor_route_map.dart';
import 'package:waymark/features/route/route_preview_page.dart';
import 'package:waymark/features/search/local_map_search_page.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/waymark_api_service.dart';

import 'fixtures/local_navigation_fixture.dart';
import 'fixtures/multifloor_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DraftMap draft;
  setUp(() => draft = customNavigationDraft());
  tearDown(AuthSession.clear);
  String room(DraftMap d, String code) =>
      d.places.singleWhere((p) => p['placeCode'] == code)['id'] as String;
  test('Validation separates structural errors from unknown safety / isolated warnings, without changing IDs', () {
    final before = draft.encode();
    final report = LocalMapValidation.check(draft);
    expect(report.canRoute, isTrue);
    expect(report.warnings.any((s) => s.contains('cô lập')), isTrue);
    expect(report.warnings.any((s) => s.contains('xe lăn')), isTrue);
    expect(draft.encode(), before);
    expect(draft.layoutReviewed, isFalse);
    draft.nodeIds.remove('J');
    expect(LocalMapValidation.check(draft).canRoute, isFalse);
    expect(draft.nodeIds.containsKey('J'), isFalse);
  });
  test('Empty graph, unknown metres, duplicate GUID and foreign Entrance are blocking', () {
    expect(
      LocalMapValidation.check(DraftMap.local('A', 'B', 'C', 'F')).canRoute,
      isFalse,
    );
    draft.addEdge(
      const DraftEdge('J', 'FAR', 0, 'Corridor', isMeasured: false),
    );
    expect(
      LocalMapValidation.check(draft).errors.join(),
      contains('khoảng cách mét'),
    );
    draft = customNavigationDraft();
    draft.nodeIds['J'] = draft.nodeIds['S']!;
    expect(LocalMapValidation.check(draft).canRoute, isFalse);
    draft = customNavigationDraft();
    draft.places.first['entranceNodeIds'] = [newDraftGuid()];
    expect(LocalMapValidation.check(draft).canRoute, isFalse);
    draft = customNavigationDraft();
    draft.places.first['entranceNodeIds'] = [draft.nodeId('J')];
    expect(LocalMapValidation.check(draft).canRoute, isFalse);
  });
  test('Cross-floor references fail closed, not converted to a same-floor shortcut', () {
    draft.transitions.add({'id': newDraftGuid()});
    expect(
      LocalMapValidation.check(draft).errors.join(),
      contains('liên tầng'),
    );
  });
  test('Shortest directed path chooses reachable cheapest entrance, not room label or fewest edges', () async {
    final map = await LocalMapNavigation.fromDraft(draft);
    final route = map.routeToRoom('S', room(draft, '101'));
    expect(route.nodes.map((n) => n.nodeCode), ['S', 'J', 'DOOR']);
    expect(route.totalDistanceMeters, 10);
    expect(route.nodes.last.nodeType, 'Entrance');
    expect(route.nodes.last.name, 'Door 101');
    expect(route.edges.map((e) => e.distanceMeters), [4, 6]);
    expect(route.edges.every((e) => !e.isAccessible), isTrue);
    expect(route.start.wayMarkCode, isEmpty);
    expect(map.graph.nodes.last.x, .9);
    expect(map.owns(route), isTrue);
    expect(() => map.graph.nodes.clear(), throwsUnsupportedError);
    expect(() => route.nodes.clear(), throwsUnsupportedError);
  });
  test(
    'Node destination uses shortest directed path and keeps its node identity',
    () async {
      draft.putNode(
        const DraftNode(
          'DOOR',
          'Technical door name',
          .7,
          .5,
          'Entrance',
          displayName: 'Clinic reception',
          searchableAsDestination: true,
          landmarkNote: 'Beside the blue desk',
        ),
        replace: true,
      );
      final map = await LocalMapNavigation.fromDraft(draft);
      final originalBytes = draft.encode();
      final destination = map.graph.nodes.singleWhere(
        (node) => node.nodeCode == 'DOOR',
      );
      final route = map.routeToNode('S', destination.id, destination.floorId);

      expect(route.nodes.map((node) => node.nodeCode), ['S', 'J', 'DOOR']);
      expect(route.totalDistanceMeters, 10);
      expect(route.destination.id, destination.id);
      expect(route.destination.location, map.graph.floor.name);
      expect(route.destination.name, 'Clinic reception');
      expect(route.nodes.last.id, destination.id);
      expect(route.nodes.last.floor.id, destination.floorId);
      expect(route.nodes.last.name, 'Clinic reception');
      expect(map.owns(route), isTrue);
      expect(
        draft.nodes.singleWhere((node) => node.code == 'DOOR').landmarkNote,
        'Beside the blue desk',
      );
      final moved = draft.nodes
          .singleWhere((node) => node.code == 'DOOR')
          .at(.75, .6);
      expect(moved.displayName, 'Clinic reception');
      expect(moved.searchableAsDestination, isTrue);
      expect(moved.landmarkNote, 'Beside the blue desk');
      expect(draft.encode(), originalBytes);
      expect(
        () => map.routeToNode('DOOR', map.graph.nodes.first.id, 1),
        throwsFormatException,
      );
      expect(
        () => map.routeToNode('S', destination.id, destination.floorId + 1),
        throwsFormatException,
      );
    },
  );

  test(
    'Node destination without a directed path fails without a fabricated route',
    () async {
      draft.putNode(
        const DraftNode(
          'ISO',
          'Isolated door',
          .9,
          .9,
          'Entrance',
          searchableAsDestination: true,
        ),
        replace: true,
      );
      final map = await LocalMapNavigation.fromDraft(draft);
      final destination = map.graph.nodes.singleWhere(
        (node) => node.nodeCode == 'ISO',
      );

      expect(
        () => map.routeToNode('S', destination.id, destination.floorId),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Không có tuyến có hướng'),
          ),
        ),
      );
    },
  );

  testWidgets(
    'Local search keeps Rooms and searchable Node destinations distinct and filters technical nodes',
    (t) async {
      draft.putNode(
        const DraftNode(
          'LANDMARK',
          'Technical node name',
          .5,
          .8,
          'Junction',
          displayName: 'Information desk',
          searchableAsDestination: true,
        ),
      );
      draft.putNode(
        const DraftNode(
          'HIDDEN',
          'Technical node',
          .6,
          .8,
          'Junction',
          displayName: 'Hidden junction',
        ),
      );
      draft.addEdge(const DraftEdge('S', 'LANDMARK', 3, 'Corridor'));
      draft.nodeId('LANDMARK');
      draft.nodeId('HIDDEN');
      final map = await LocalMapNavigation.fromDraft(draft);
      final page = LocalMapSearchPage(map: map, destinationFloors: [draft]);
      final destination = page.searchableNodeDestinations.single;
      final graphNode = map
          .graphFor(1)
          .nodes
          .singleWhere((node) => node.nodeCode == 'LANDMARK');
      expect(destination.displayName, 'Information desk');
      expect(destination.selection.nodeCode, 'LANDMARK');
      expect(destination.selection.nodeId, graphNode.id);
      expect(destination.selection.floorId, graphNode.floorId);

      await t.pumpWidget(MaterialApp(home: page));
      await t.tap(find.byKey(const Key('local-start-node')));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Start (S)').last);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Information');
      await t.pumpAndSettle();
      expect(find.text('Room 101 (101)'), findsNothing);
      expect(find.text('Information desk (LANDMARK)'), findsOneWidget);
      expect(find.text('Điểm đến • Custom floor'), findsOneWidget);
      await t.tap(
        find.byKey(
          ValueKey(
            'local-node-destination-${destination.selection.floorId}-${destination.selection.nodeId}',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(RoutePreviewPage), findsOneWidget);
      expect(find.text('Information desk'), findsOneWidget);
      await t.tap(find.byTooltip('Quay lại'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'LANDMARK');
      await t.pumpAndSettle();
      expect(find.text('Information desk (LANDMARK)'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Hidden');
      await t.pumpAndSettle();
      expect(find.textContaining('Không tìm thấy'), findsOneWidget);
      await t.enterText(find.byType(TextField), '101');
      await t.pumpAndSettle();
      expect(find.text('Room 101 (101)'), findsOneWidget);
      expect(find.textContaining('Phòng • Custom floor'), findsOneWidget);
    },
  );

  testWidgets('Multi-floor node search retains its graph node and floor IDs', (
    t,
  ) async {
    final project = threeFloorProject();
    final floor = project.floors[1];
    floor.putNode(
      const DraftNode(
        'INFO',
        'Information point',
        .4,
        .7,
        'Destination',
        displayName: 'Information desk',
        searchableAsDestination: true,
      ),
    );
    floor.nodeId('INFO');
    final map = await LocalMapNavigation.fromProject(project);
    final page = LocalMapSearchPage(
      map: map,
      destinationFloors: project.floors,
    );
    final destination = page.searchableNodeDestinations.single;
    final graphNode = map
        .graphFor(2)
        .nodes
        .singleWhere((node) => node.nodeCode == 'INFO');
    expect(destination.selection.nodeId, graphNode.id);
    expect(destination.selection.floorId, 2);
    expect(destination.selection.floorId, graphNode.floorId);
    expect(destination.floorName, 'Tầng I');

    await t.pumpWidget(MaterialApp(home: page));
    await t.enterText(find.byType(TextField), 'INFO');
    await t.pumpAndSettle();
    expect(find.text('Information desk (INFO)'), findsOneWidget);
    expect(find.text('Điểm đến • Tầng I'), findsOneWidget);
  });

  testWidgets(
    'Multi-floor Node destination routes through declared directed transfers and arrives on its floor',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      final project = threeFloorProject();
      final destinationFloor = project.floors.last;
      destinationFloor.putNode(
        const DraftNode(
          'DOOR',
          'Technical door',
          .8,
          .5,
          'Entrance',
          displayName: 'Radiology',
          searchableAsDestination: true,
        ),
        replace: true,
      );
      final map = await LocalMapNavigation.fromProject(project);
      final destination = map
          .graphFor(3)
          .nodes
          .singleWhere((node) => node.nodeCode == 'DOOR');
      final route = map.routeToNode(
        project.floors.first.nodeId('START'),
        destination.id,
        destination.floorId,
      );

      expect(route.totalDistanceMeters, 30);
      expect(route.nodes.map((node) => node.floor.id), [1, 1, 2, 3, 3]);
      expect(
        route.edges.where((edge) => edge.movement == 'ChangeFloor'),
        hasLength(2),
      );
      expect(route.destination.id, destination.id);
      expect(route.destination.location, 'Tầng II');
      expect(route.nodes.last.id, destination.id);
      expect(route.nodes.last.floor.id, 3);
      expect(route.nodes.last.name, 'Radiology');

      await t.pumpWidget(
        MaterialApp(
          home: LocalMapSearchPage(map: map, destinationFloors: project.floors),
        ),
      );
      await t.tap(find.byKey(const Key('local-start-node')));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Bắt đầu (START)').first);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Radiology');
      await t.pumpAndSettle();
      await t.tap(
        find.byKey(
          ValueKey(
            'local-node-destination-${destination.floorId}-${destination.id}',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(RoutePreviewPage), findsOneWidget);
      expect(find.text('Radiology'), findsOneWidget);
      await t.tap(find.text('Bắt đầu dẫn đường'));
      await t.pumpAndSettle();
      for (var step = 0; step < route.nodes.length - 1; step++) {
        await t.tap(find.byKey(const Key('navigation-confirm')));
        await t.pumpAndSettle();
      }
      expect(find.text('Node đang chọn: Radiology'), findsOneWidget);
      expect(find.text('Tầng của bước hiện tại: Tầng II'), findsOneWidget);
      expect(find.byKey(const Key('mobile-arrival-summary')), findsOneWidget);
    },
  );

  testWidgets(
    'Node Search opens Preview and Navigation arrives at the selected Node',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      draft.putNode(
        const DraftNode(
          'DOOR',
          'Technical door',
          .7,
          .5,
          'Entrance',
          displayName: 'Clinic reception',
          searchableAsDestination: true,
          landmarkNote: 'Reception desk on the right',
        ),
        replace: true,
      );
      draft.putNode(
        const DraftNode(
          'J',
          'Junction',
          .4,
          .5,
          'Junction',
          landmarkNote: 'Blue sign at the junction',
        ),
        replace: true,
      );
      final map = await LocalMapNavigation.fromDraft(draft);
      final destination = map.graph.nodes.singleWhere(
        (node) => node.nodeCode == 'DOOR',
      );
      await t.pumpWidget(
        MaterialApp(
          home: LocalMapSearchPage(map: map, destinationFloors: [draft]),
        ),
      );
      await t.tap(find.byKey(const Key('local-start-node')));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Start (S)').last);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Clinic reception');
      await t.pumpAndSettle();
      await t.tap(
        find.byKey(
          ValueKey(
            'local-node-destination-${destination.floorId}-${destination.id}',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(RoutePreviewPage), findsOneWidget);
      expect(find.byKey(const Key('local-preview-banner')), findsOneWidget);
      expect(find.text('Clinic reception'), findsOneWidget);
      await t.tap(find.text('Bắt đầu dẫn đường'));
      await t.pumpAndSettle();
      expect(find.byType(NavigationPage), findsOneWidget);
      expect(find.text('Bước 1/3'), findsOneWidget);
      expect(
        find.byKey(const Key('navigation-current-landmark-note')),
        findsNothing,
      );
      expect(
        find.text('Mốc nhận biết điểm kế tiếp: Blue sign at the junction'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('navigation-confirm')));
      await t.pumpAndSettle();
      expect(
        find.text('Mốc nhận biết: Blue sign at the junction'),
        findsOneWidget,
      );
      expect(
        find.text('Mốc nhận biết điểm kế tiếp: Reception desk on the right'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('navigation-confirm')));
      await t.pumpAndSettle();
      expect(find.text('Node đang chọn: Clinic reception'), findsOneWidget);
      expect(find.text('Tầng của bước hiện tại: Custom floor'), findsOneWidget);
      expect(
        find.text('Mốc nhận biết: Reception desk on the right'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('navigation-next-landmark-note')),
        findsNothing,
      );
      expect(find.byKey(const Key('mobile-arrival-summary')), findsOneWidget);
    },
  );

  testWidgets('Local Navigation without landmark notes keeps the existing UI', (
    t,
  ) async {
    draft.putNode(
      const DraftNode(
        'DOOR',
        'Door without landmark note',
        .7,
        .5,
        'Entrance',
        searchableAsDestination: true,
      ),
      replace: true,
    );
    final map = await LocalMapNavigation.fromDraft(draft);
    final destination = map.graph.nodes.singleWhere(
      (node) => node.nodeCode == 'DOOR',
    );
    final route = map.routeToNode('S', destination.id, destination.floorId);
    await t.pumpWidget(
      MaterialApp(
        home: NavigationPage(route: route, localMap: map),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.byKey(const Key('navigation-current-landmark-note')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('navigation-next-landmark-note')),
      findsNothing,
    );
    expect(find.byKey(const Key('mobile-next-instruction')), findsOneWidget);
  });

  test('No path, wrong direction, unknown start/room; start=entrance has no invented edge', () async {
    final map = await LocalMapNavigation.fromDraft(draft);
    expect(
      () => map.routeToRoom('DOOR', room(draft, '102')),
      throwsFormatException,
    );
    expect(
      () => map.routeToRoom('S', room(draft, '103')),
      throwsFormatException,
    );
    expect(
      () => map.routeToRoom('foreign', room(draft, '101')),
      throwsFormatException,
    );
    expect(() => map.routeToRoom('S', newDraftGuid()), throwsFormatException);
    final same = map.routeToRoom('DOOR', room(draft, '101'));
    expect(same.nodes.length, 1);
    expect(same.edges, isEmpty);
    expect(same.totalDistanceMeters, 0);
    expect(ManualNavigation.validate(same), isNotNull);
    final navigation = ManualNavigation(same, localPreview: true);
    expect(navigation.isValid, isTrue);
    expect(navigation.confirmNext(), isTrue);
    expect(navigation.completed, isTrue);
  });
  test('Inactive edge ignored; JSON reopen identical; snapshot never changes with editor or another map', () async {
    final old = draft.edges.first;
    draft.updateEdge(
      old,
      const DraftEdge('S', 'J', 4, 'Corridor', isActive: false),
    );
    final map = await LocalMapNavigation.fromDraft(draft);
    expect(map.routeToRoom('S', room(draft, '101')).nodes.last.nodeCode, 'FAR');
    final reopened = await openLocalDraft(draft.encode());
    final other = await LocalMapNavigation.fromDraft(reopened);
    expect(other.routeToRoom('S', room(draft, '101')).totalDistanceMeters, 15);
    final route = map.routeToRoom('S', room(draft, '101'));
    expect(other.owns(route), isFalse);
    draft.removeNode('J');
    expect(map.routeToRoom('S', room(draft, '101')).totalDistanceMeters, 15);
  });
  testWidgets(
    'Custom Search -> shared Preview/Navigation, image and manual arrival; no backend QR or session change',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final bytes = await t.runAsync(() async {
        final r = ui.PictureRecorder();
        Canvas(r).drawColor(Colors.white, BlendMode.src);
        final p = r.endRecording(), image = await p.toImage(600, 400);
        final b = await image.toByteData(format: ui.ImageByteFormat.png);
        final data = Uint8List.fromList(
          b!.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes),
        );
        image.dispose();
        p.dispose();
        return data;
      });
      final map = await t.runAsync(() async {
        draft.image = await FloorPlanAsset.validate(
          bytes!,
          'custom.png',
          'image/png',
        );
        return LocalMapNavigation.fromDraft(draft);
      });
      AuthSession.accessToken = 'preserved-session';
      await t.pumpWidget(
        MaterialApp(
          home: LocalMapSearchPage(map: map!, destinationFloors: [draft]),
        ),
      );
      await t.runAsync(
        () => precacheImage(
          map.image!,
          t.element(find.byType(LocalMapSearchPage)),
        ),
      );
      await t.tap(find.byKey(const Key('local-start-node')));
      await t.pumpAndSettle();
      await t.tap(find.text('Start (S)').last);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '101');
      await t.pumpAndSettle();
      await t.tap(find.text('Room 101 (101)'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('local-preview-banner')), findsOneWidget);
      expect(find.byKey(const Key('floor-plan-image-layer')), findsOneWidget);
      expect(find.text('10 m'), findsOneWidget);
      expect(find.byTooltip('Tùy chọn tuyến'), findsNothing);
      await t.tap(find.text('Bắt đầu dẫn đường'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('local-navigation-banner')), findsOneWidget);
      expect(find.text('Quét QR xác nhận vị trí'), findsNothing);
      await t.pump(const Duration(minutes: 3));
      expect(find.text('Bước 1/3'), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await t.tap(find.byKey(const Key('navigation-confirm')));
        await t.pumpAndSettle();
      }
      expect(find.text('Node đang chọn: Door 101'), findsOneWidget);
      expect(find.byKey(const Key('mobile-arrival-summary')), findsOneWidget);
      await t.tap(find.text('Kết thúc'));
      await t.pumpAndSettle();
      expect(find.byType(RoutePreviewPage), findsOneWidget);
      expect(AuthSession.accessToken, 'preserved-session');
    },
  );
  testWidgets(
    'Unreachable local room reports error without enabling Navigation',
    (t) async {
      final map = await LocalMapNavigation.fromDraft(draft);
      await t.pumpWidget(
        MaterialApp(
          home: RoutePreviewPage.local(
            map: map,
            startNodeCode: 'S',
            placeId: room(draft, '103'),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Không có đường có hướng'), findsOneWidget);
      expect(find.text('Bắt đầu dẫn đường'), findsNothing);
      expect(find.text('Thử lại'), findsOneWidget);
    },
  );
  testWidgets(
    'Unreachable Node reports the directed-route error and disables Navigation',
    (t) async {
      draft.putNode(
        const DraftNode(
          'NODE-ISO',
          'Isolated Node',
          .9,
          .9,
          'Destination',
          displayName: 'Isolated destination',
          searchableAsDestination: true,
        ),
      );
      draft.nodeId('NODE-ISO');
      final map = await LocalMapNavigation.fromDraft(draft);
      final destination = map.graph.nodes.singleWhere(
        (node) => node.nodeCode == 'NODE-ISO',
      );
      await t.pumpWidget(
        MaterialApp(
          home: RoutePreviewPage.localNode(
            map: map,
            startNodeCode: 'S',
            destinationNodeId: destination.id,
            destinationFloorId: destination.floorId,
            destinationName: 'Isolated destination',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Không có tuyến có hướng'), findsOneWidget);
      expect(find.text('Bắt đầu dẫn đường'), findsNothing);
      expect(find.text('Thử lại'), findsOneWidget);
    },
  );

  testWidgets(
    'A route from a different local map cannot render or navigate, even when numeric IDs coincide',
    (t) async {
      final a = await LocalMapNavigation.fromDraft(draft),
          b = await LocalMapNavigation.fromDraft(customNavigationDraft());
      final route = b.routeToRoom('S', b.rooms.first.id);
      final client = MockClient(
        (r) async => throw StateError('No HTTP in local mode'),
      );
      addTearDown(client.close);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FloorRouteMap(
              route: route,
              api: WayMarkApiService(client: client),
              localMap: a,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('floor-route-canvas')), findsNothing);
      await t.pumpWidget(
        MaterialApp(
          home: NavigationPage(route: route, localMap: a),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Tuyến không thuộc bản đồ cục bộ này.'), findsOneWidget);
      expect(find.byKey(const Key('navigation-confirm')), findsNothing);
    },
  );
}
