import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:waymark/services/map_draft_api_service.dart';
import 'package:waymark/features/admin/draft_file_gateway.dart';
import 'package:waymark/features/admin/draft_files_native.dart';
import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/admin/draft_map_editor.dart';
import 'package:waymark/features/admin/draft_server_session.dart';
import 'package:waymark/features/admin/floor_plan_asset.dart';
import 'package:waymark/features/navigation/local_map_navigation.dart';
import 'package:waymark/features/route/floor_plan_canvas.dart';
import 'package:waymark/services/auth_session.dart';

import 'draft_floor_workflow_test.dart' show MemoryDraftFiles;
import 'fixtures/local_navigation_fixture.dart';

import 'package:waymark/features/search/local_map_search_page.dart';
import 'package:waymark/features/route/route_preview_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List png;
  setUp(() async {
    final bytes = await rootBundle.load('assets/demo_maps/ground.png');
    png = bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(draftFilesChannel, null);
    AuthSession.clear();
  });

  test('Android gateway enabled; cancellation, size limit and save outcomes explicit', () async {
    expect(const PlatformDraftFiles().supported, isTrue);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(draftFilesChannel, (call) async => null);
    expect(await pickDraftFile('.png,.jpg', 100), isNull);
    await expectLater(
      downloadDraftFile(png, 'a.json', 'application/json'),
      throwsFormatException,
    );
    messenger.setMockMethodCallHandler(
      draftFilesChannel,
      (call) async => {
        'bytes': Uint8List(101),
        'name': 'x.png',
        'mime': 'image/png',
      },
    );
    await expectLater(pickDraftFile('.png', 100), throwsFormatException);
    messenger.setMockMethodCallHandler(
      draftFilesChannel,
      (call) async => call.method == 'save'
          ? true
          : {'bytes': png, 'name': 'plan.png', 'mime': 'image/png'},
    );
    expect((await pickDraftFile('.png', FloorPlanAsset.maxBytes))!.bytes, png);
    await downloadDraftFile(png, 'a.json', 'application/json');
  });

  test('Android PNG export passes image MIME and filename without converting to JSON', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(draftFilesChannel, (call) async {
          expect(call.method, 'save');
          expect((call.arguments as Map)['mime'], 'image/png');
          expect((call.arguments as Map)['name'], 'qr.png');
          expect((call.arguments as Map)['bytes'], png);
          return true;
        });
    await downloadDraftFile(png, 'qr.png', 'image/png');
  });

  test('Custom local v2 restores metadata, image, Room entrances and directed edges; no server binding', () async {
    final draft = DraftMap.local(
      'My site',
      'My building',
      'Custom floor',
      'F2',
    );
    draft.image = await FloorPlanAsset.validate(
      png,
      'my-plan.png',
      'image/png',
    );
    draft.putNode(const DraftNode('DOOR-A', 'Door A', .1, .2, 'Entrance'));
    draft.putNode(const DraftNode('DOOR-B', 'Door B', .3, .4, 'Entrance'));
    draft.putNode(const DraftNode('J', 'Junction', .2, .2, 'Junction'));
    draft.addEdge(const DraftEdge('J', 'DOOR-A', 5.25, 'Door'));
    draft.places.add({
      'id': newDraftGuid(),
      'placeCode': '101',
      'name': 'Custom room',
      'label': {'x': .5, 'y': .5},
      'polygon': [],
      'entranceNodeIds': [draft.nodeId('DOOR-A'), draft.nodeId('DOOR-B')],
      'accessibility': 'Unknown',
    });
    DraftServerMapper.content(draft, null);
    final restored = await openLocalDraft(draft.encode());
    expect(restored.localWorkspaceId, draft.localWorkspaceId);
    expect(restored.localSiteName, 'My site');
    expect(restored.floor.name, 'Custom floor');
    expect(restored.image!.bytes, png);
    expect(restored.places, draft.places);
    expect(restored.nodeIds, draft.nodeIds);
    expect(restored.edges.single.to, 'DOOR-A');
    expect(restored.edges.single.meters, 5.25);
    expect(
      DraftServerMapper.content(restored, null)['edges'][0]['accessibility'],
      'Unknown',
    );
    expect(() => restored.removeNode('DOOR-A'), throwsFormatException);
    await expectLater(
      DraftMap.decode(
        draft.encode(),
        siteId: 1,
        buildingId: 1,
        floor: draft.floor,
      ),
      throwsFormatException,
    );
    final client = MockClient(
      (request) async => throw StateError('Local draft must not call server'),
    );
    addTearDown(client.close);
    await expectLater(
      DraftServerSession(
        MapDraftApiService(client: client),
        siteId: 1,
        buildingId: 1,
        floor: draft.floor,
      ).save(draft),
      throwsFormatException,
    );
    final bad = jsonDecode(utf8.decode(draft.encode())) as Map<String, dynamic>;
    bad['localWorkspace']['siteName'] = '';
    await expectLater(
      openLocalDraft(Uint8List.fromList(utf8.encode(jsonEncode(bad)))),
      throwsFormatException,
    );
  });

  testWidgets(
    'Builder validates and tries an in-memory snapshot, then returns to intact draft without export',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final draft = customNavigationDraft();
      final files = MemoryDraftFiles()
        ..next = (
          bytes: draft.encode(),
          name: 'local.json',
          mime: 'application/json',
        );
      await t.pumpWidget(MaterialApp(home: DraftMapEditor(files: files)));
      await t.pumpAndSettle();
      await t.tap(find.text('Mở JSON'));
      await t.pumpAndSettle();
      expect(
        find.text('5 Node • 4 Edge • 3 điểm đến • 3 Room (legacy)'),
        findsOneWidget,
      );
      await t.pump(const Duration(seconds: 5));
      await Scrollable.ensureVisible(
        t.element(find.byKey(const Key('validate-local-map'))),
        alignment: .5,
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('validate-local-map')));
      await t.pumpAndSettle();
      expect(find.text('Dữ liệu có thể tính tuyến cục bộ'), findsOneWidget);
      await t.tap(find.text('Đóng'));
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 5));
      await t.ensureVisible(find.byKey(const Key('try-local-navigation')));
      await t.tap(find.byKey(const Key('try-local-navigation')));
      await t.pumpAndSettle();
      await t.tap(find.text('Chọn điểm đến'));
      await t.pumpAndSettle();
      expect(find.byType(LocalMapSearchPage), findsOneWidget);
      await t.tap(find.byKey(const Key('local-start-node')));
      await t.pumpAndSettle();
      await t.tap(find.text('Start (S)').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Room 101 (101)'));
      await t.pumpAndSettle();
      expect(find.byType(RoutePreviewPage), findsOneWidget);
      await t.tap(find.byIcon(Icons.arrow_back).first);
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(
        find.text('5 Node • 4 Edge • 3 điểm đến • 3 Room (legacy)'),
        findsOneWidget,
      );
      expect(files.saved, isNull);
      await Scrollable.ensureVisible(
        t.element(find.byKey(const Key('export-draft'))),
        alignment: .5,
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('export-draft')));
      await t.pumpAndSettle();
      final after = await openLocalDraft(files.saved!);
      expect(after.nodeIds, draft.nodeIds);
      expect(after.edgeIds, draft.edgeIds);
      expect(after.places, draft.places);
      expect(after.localWorkspaceId, draft.localWorkspaceId);
    },
  );

  testWidgets(
    'Builder opens search for a Room-less graph and reaches its marked Node',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      final draft =
          DraftMap.local('Node-first site', 'Building', 'Ground floor', 'G')
            ..putNode(const DraftNode('START', 'Start', .1, .5, 'Entrance'))
            ..putNode(
              const DraftNode('JUNCTION', 'Junction', .4, .5, 'Junction'),
            )
            ..putNode(
              const DraftNode(
                'DEST',
                'Technical destination',
                .8,
                .5,
                'Destination',
                displayName: 'Operating theatre',
                searchableAsDestination: true,
                landmarkNote: 'Blue sign beside the door',
              ),
            )
            ..addEdge(const DraftEdge('START', 'JUNCTION', 4, 'Corridor'))
            ..addEdge(const DraftEdge('JUNCTION', 'DEST', 6, 'Door'));
      expect(draft.places, isEmpty);
      expect(LocalMapValidation.check(draft).canRoute, isTrue);
      final files = MemoryDraftFiles()
        ..next = (
          bytes: draft.encode(),
          name: 'node-first.json',
          mime: 'application/json',
        );
      await t.pumpWidget(MaterialApp(home: DraftMapEditor(files: files)));
      await t.pumpAndSettle();
      await t.tap(find.text('Mở JSON'));
      await t.pumpAndSettle();

      await t.ensureVisible(find.byKey(const Key('try-local-navigation')));
      await t.tap(find.byKey(const Key('try-local-navigation')));
      await t.pumpAndSettle();
      expect(find.text('Dữ liệu có thể tính tuyến cục bộ'), findsOneWidget);
      await t.tap(find.text('Chọn điểm đến'));
      await t.pumpAndSettle();
      expect(find.byType(LocalMapSearchPage), findsOneWidget);
      expect(find.text('Operating theatre (DEST)'), findsOneWidget);

      await t.tap(find.byKey(const Key('local-start-node')));
      await t.pumpAndSettle();
      await t.tap(find.text('Start (START)').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Operating theatre (DEST)'));
      await t.pumpAndSettle();
      expect(find.byType(RoutePreviewPage), findsOneWidget);
      expect(find.text('Operating theatre'), findsOneWidget);
      ScaffoldMessenger.of(t.element(find.byType(RoutePreviewPage)))
          .hideCurrentSnackBar();
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Bắt đầu dẫn đường'));
      await t.tap(find.text('Bắt đầu dẫn đường'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('navigation-confirm')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('navigation-confirm')));
      await t.pumpAndSettle();
      expect(find.text('Node đang chọn: Operating theatre'), findsOneWidget);
      expect(
        find.text('Mốc nhận biết: Blue sign beside the door'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Room-less map without a marked destination shows actionable validation',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final draft = DraftMap.local('Site', 'Building', 'Floor', 'G')
        ..putNode(const DraftNode('START', 'Start', .1, .5, 'Entrance'))
        ..putNode(const DraftNode('DEST', 'Node', .8, .5, 'Destination'))
        ..addEdge(const DraftEdge('START', 'DEST', 5, 'Corridor'));
      expect(LocalMapValidation.check(draft).canRoute, isFalse);
      expect(
        LocalMapValidation.check(draft).errors.join(' '),
        contains('đánh dấu một Node làm điểm đến'),
      );
      final files = MemoryDraftFiles()
        ..next = (
          bytes: draft.encode(),
          name: 'missing-destination.json',
          mime: 'application/json',
        );
      await t.pumpWidget(MaterialApp(home: DraftMapEditor(files: files)));
      await t.pumpAndSettle();
      await t.tap(find.text('Mở JSON'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('try-local-navigation')));
      await t.tap(find.byKey(const Key('try-local-navigation')));
      await t.pumpAndSettle();
      expect(find.text('Cần sửa bản đồ trước khi tính tuyến'), findsOneWidget);
      expect(
        find.textContaining(
          'đánh dấu một Node làm điểm đến hoặc thêm Room/Place',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Phone creates offline blank map; image cancel/tool changes keep draft; Room and file save work',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final files = MemoryDraftFiles();
      AuthSession.accessToken = 'session-must-stay';
      await t.pumpWidget(MaterialApp(home: DraftMapEditor(files: files)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('new-local-map')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('create-local-map')));
      await t.pumpAndSettle();
      expect(find.text('0 Node • 0 Edge • 0 điểm đến'), findsOneWidget);
      files.next = (bytes: png, name: 'my-plan.png', mime: 'image/png');
      await t.runAsync(() async {
        await t.tap(find.byKey(const Key('pick-floor-image')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      for (var i = 0; i < 3; i++) {
        await t.pump();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
      }
      await t.pumpAndSettle();
      expect(find.byKey(const Key('floor-plan-image-layer')), findsOneWidget);
      final before = t
          .widget<FloorPlanCanvas>(find.byType(FloorPlanCanvas))
          .image;
      files.next = null;
      await t.ensureVisible(find.byKey(const Key('pick-floor-image')));
      await t.tap(find.byKey(const Key('pick-floor-image')));
      await t.pumpAndSettle();
      expect(
        t.widget<FloorPlanCanvas>(find.byType(FloorPlanCanvas)).image,
        same(before),
      );
      await t.ensureVisible(find.text('Thêm node'));
      await t.tap(find.text('Thêm node'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('floor-route-canvas')));
      await t.tapAt(t.getCenter(find.byKey(const Key('floor-route-canvas'))));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Tên node'), 'Cửa 101');
      await t.tap(find.text('Junction'));
      await t.pumpAndSettle();
      await t.tap(find.text('Entrance').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Lưu node nháp'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('legacy-room-tools')));
      await t.tap(find.byKey(const Key('legacy-room-tools')));
      await t.pumpAndSettle();
      await t.tap(find.text('Thêm Room/Place'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Mã phòng / số phòng'),
        '101',
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Tên Room/Place'),
        'Khám 101',
      );
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await t.tap(find.text('Lưu phòng nháp'));
      await t.pumpAndSettle();
      expect(
        find.text('1 Node • 0 Edge • 1 điểm đến • 1 Room (legacy)'),
        findsOneWidget,
      );
      await t.tap(find.text('Đóng bảng'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('export-draft')));
      await t.tap(find.byKey(const Key('export-draft')));
      await t.pumpAndSettle();
      final saved = await t.runAsync(() => openLocalDraft(files.saved!));
      expect(saved!.places.single['name'], 'Khám 101');
      expect(saved.image!.bytes, png);
      expect(saved.nodes.single.type, 'Entrance');
      expect(AuthSession.accessToken, 'session-must-stay');
      expect(
        find.text('Đã lưu/mở file cục bộ • chưa lưu server'),
        findsOneWidget,
      );
      await t.ensureVisible(find.byKey(const Key('legacy-room-tools')));
      await t.tap(find.byKey(const Key('legacy-room-tools')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Khám 101 (101)'));
      await t.tap(find.text('Khám 101 (101)'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Tên Room/Place'),
        'Khám 101 mới',
      );
      await t.tap(find.text('Lưu phòng nháp'));
      await t.pumpAndSettle();
      await t.tap(find.text('Đóng bảng'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('legacy-room-tools')));
      await t.tap(find.byKey(const Key('legacy-room-tools')));
      await t.pumpAndSettle();
      expect(find.text('Khám 101 mới (101)'), findsOneWidget);
      await t.ensureVisible(find.byTooltip('Xóa phòng nháp'));
      await t.tap(find.byTooltip('Xóa phòng nháp'));
      await t.pumpAndSettle();
      await t.tap(find.text('Xóa phòng'));
      await t.pumpAndSettle();
      expect(find.text('Khám 101 mới (101)'), findsNothing);
      expect(find.text('1 Node • 0 Edge • 0 điểm đến'), findsOneWidget);
      expect(AuthSession.accessToken, 'session-must-stay');
      expect(t.takeException(), isNull);
    },
  );
}
