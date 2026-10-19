import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/admin/draft_map_editor.dart';
import 'package:waymark/features/admin/floor_plan_asset.dart';
import 'package:waymark/models/route_models.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/waymark_api_service.dart';

import 'fixtures/routing_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DraftMap draft() => DraftMap(
    siteId: 1,
    buildingId: 1,
    floor: RouteFloor.fromJson(floorGraphJson(1)['floor']),
  );

  test('Draft constraints, directed edges and export never publish', () {
    final map = draft();
    map.putNode(const DraftNode('DRAFT-A', 'A', .2, .4, 'Junction'));
    map.putNode(const DraftNode('DRAFT-B', 'B', .8, .4, 'Destination'));
    expect(
      () => map.putNode(
        const DraftNode('draft-a', 'duplicate', .2, .4, 'Junction'),
      ),
      throwsFormatException,
    );
    expect(
      () => map.putNode(const DraftNode('C', 'bad', 1.1, .4, 'Junction')),
      throwsFormatException,
    );
    expect(
      () => map.addEdge(const DraftEdge('DRAFT-A', 'missing', 4, 'Corridor')),
      throwsFormatException,
    );
    expect(
      () => map.addEdge(const DraftEdge('DRAFT-A', 'DRAFT-A', 4, 'Corridor')),
      throwsFormatException,
    );
    expect(
      () => map.addEdge(const DraftEdge('DRAFT-A', 'DRAFT-B', 0, 'Corridor')),
      throwsFormatException,
    );
    map.addEdge(const DraftEdge('DRAFT-A', 'DRAFT-B', 3.5, 'Corridor'));
    expect(
      () => map.addEdge(const DraftEdge('DRAFT-A', 'DRAFT-B', 2, 'Corridor')),
      throwsFormatException,
    );
    map.addEdge(const DraftEdge('DRAFT-B', 'DRAFT-A', 3.5, 'Corridor'));
    map.putNode(
      const DraftNode('DRAFT-A', 'A moved', .3, .5, 'Junction'),
      replace: true,
    );
    expect(map.nodes.first.x, .3);
    expect(map.edges.length, 2);
    expect(map.toJson()['status'], 'draft');
    expect(map.toJson()['verifiedForPatientUse'], false);
    expect((map.toJson()['edges'] as List).first['isAccessible'], false);
  });

  test('WayMark cannot link two nodes in a draft', () {
    final map = draft();
    map.putNode(
      const DraftNode('A', 'A', .2, .3, 'Entrance', wayMarkCode: 'QR-A'),
    );
    expect(
      () => map.putNode(
        const DraftNode('B', 'B', .3, .3, 'Junction', wayMarkCode: 'qr-a'),
      ),
      throwsFormatException,
    );
  });

  test(
    'Image input rejects MIME spoof, paths, oversized data and corrupt image',
    () async {
      await expectLater(
        FloorPlanAsset.validate(Uint8List(0), 'floor.png', 'image/png'),
        throwsFormatException,
      );
      await expectLater(
        FloorPlanAsset.validate(
          Uint8List(FloorPlanAsset.maxBytes + 1),
          'floor.png',
          'image/png',
        ),
        throwsFormatException,
      );
      await expectLater(
        FloorPlanAsset.validate(
          Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
          'floor.jpg',
          'image/jpeg',
        ),
        throwsFormatException,
      );
      await expectLater(
        FloorPlanAsset.validate(
          Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
          'floor.png',
          'image/png',
        ),
        throwsFormatException,
      );
    },
  );

  test('Valid PNG is decoded with real dimensions, without changing published graph', () async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(80, 40);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    final asset = await FloorPlanAsset.validate(
      bytes,
      'floor.png',
      'image/png',
    );
    expect(asset.width, 80);
    expect(asset.height, 40);
    // A complete PNG header with no pixel data must not replace a valid draft.
    await expectLater(
      FloorPlanAsset.validate(
        Uint8List.sublistView(bytes, 0, 33),
        'truncated.png',
        'image/png',
      ),
      throwsFormatException,
    );
    image.dispose();
    picture.dispose();
  });

  testWidgets(
    'Builder selects real hierarchy and edits a draft using GET only',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AuthSession.accessToken = 'draft-test';
      addTearDown(AuthSession.clear);
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.headers['Authorization'], 'Bearer draft-test');
        final path = request.url.path;
        final Object data = path.endsWith('/sites')
            ? [
                {'id': 1, 'name': 'Test site'},
                {'id': 2, 'name': 'Other site'},
              ]
            : path.endsWith('/buildings')
            ? [
                {'id': 1, 'siteId': 1, 'name': 'Building'},
              ]
            : path.endsWith('/floors')
            ? [floorGraphJson(1)['floor']]
            : floorGraphJson(1);
        return http.Response(jsonEncode(data), 200);
      });
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          home: DraftMapEditor(api: WayMarkApiService(client: client)),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> choose(String level, String label) async {
        await tester.tap(find.byKey(ValueKey('draft-$level')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      await choose('Site', 'Test site');
      await choose('Building', 'Building');
      await choose('Floor', 'Floor one');
      expect(find.textContaining('2 node / 0 cạnh'), findsOneWidget);
      expect(find.textContaining('BẢN NHÁP'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Thêm node'));
      await tester.tap(find.text('Thêm node'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('floor-route-canvas')));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'DRAFT-TEST');
      await tester.enterText(fields.at(1), 'Draft destination');
      await tester.tap(find.text('Lưu node nháp'));
      await tester.pumpAndSettle();
      expect(find.textContaining('3 node / 0 cạnh'), findsOneWidget);
      await choose('Site', 'Other site');
      expect(find.text('Rời bản nháp chưa xuất?'), findsOneWidget);
      await tester.tap(find.text('Giữ lại'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<int>>(
              find.byKey(const ValueKey('draft-Site')),
            )
            .value,
        1,
      );
      expect(find.textContaining('3 node / 0 cạnh'), findsOneWidget);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cài đặt'));
      await tester.pumpAndSettle();
      expect(find.text('Rời bản nháp chưa xuất?'), findsOneWidget);
      await tester.tap(find.text('Giữ lại'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Rời bản nháp chưa xuất?'), findsNothing);
      expect(find.textContaining('3 node / 0 cạnh'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
