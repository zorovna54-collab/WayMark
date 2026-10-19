import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/admin/draft_file_gateway.dart';
import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/admin/draft_map_editor.dart';
import 'package:waymark/features/admin/floor_plan_asset.dart';
import 'package:waymark/models/route_models.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/waymark_api_service.dart';

import 'fixtures/routing_fixture.dart';

class MemoryDraftFiles implements DraftFileGateway {
  DraftFile? next;
  Uint8List? saved;
  @override
  bool get supported => true;
  @override
  Future<DraftFile?> pick(String accept, int maxBytes) async => next;
  @override
  Future<void> save(Uint8List bytes, String name, String mime) async =>
      saved = bytes;
}

// Generated 8x4 solid-color JPEG fixture. Never bundled into the production app.
const jpeg =
    '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAAEAAgDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDq6KKK/os/Kj//2Q==';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List png;
  setUpAll(() async {
    if (const bool.fromEnvironment('WAYMARK_CAPTURE_FLOOR_EDITOR')) {
      final inter = FontLoader('Inter');
      for (final weight in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
      }
      await inter.load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
    final border = Paint()
      ..color = Colors.blueGrey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(const Rect.fromLTWH(8, 10, 48, 30), border);
    canvas.drawRect(const Rect.fromLTWH(100, 10, 48, 30), border);
    canvas.drawLine(
      const Offset(10, 60),
      const Offset(150, 60),
      Paint()
        ..color = Colors.cyan
        ..strokeWidth = 3,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(160, 80);
    png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
    image.dispose();
    picture.dispose();
  });
  DraftMap draft() => DraftMap(
    siteId: 1,
    buildingId: 1,
    floor: RouteFloor.fromJson(floorGraphJson(1)['floor']),
  );
  Future<DraftMap> restore(Uint8List bytes) =>
      DraftMap.decode(bytes, siteId: 1, buildingId: 1, floor: draft().floor);
  Future<DraftMap> populated() async {
    final map = draft();
    map.image = await FloorPlanAsset.validate(
      png,
      'test-floor.png',
      'image/png',
    );
    map.putNode(
      const DraftNode('A', 'QR start', .2, .3, 'Entrance', wayMarkCode: 'WM-A'),
    );
    map.putNode(const DraftNode('B', 'Destination', .7, .7, 'Destination'));
    map.putNode(const DraftNode('C', 'Isolated', .9, .2, 'Junction'));
    map.addEdge(const DraftEdge('A', 'B', 8.25, 'Corridor'));
    return map;
  }

  test('PNG and JPEG really decode; missing OS MIME is inferred safely', () async {
    final a = await FloorPlanAsset.validate(png, 'floor.png', '');
    final b = await FloorPlanAsset.validate(
      base64Decode(jpeg),
      'floor.jpg',
      'image/jpeg',
    );
    expect([a.width, a.height, a.mime], [160, 80, 'image/png']);
    expect([b.width, b.height], [8, 4]);
    expect(() => a.bytes[0] = 0, throwsUnsupportedError);
    // Web's decoder rejects _UnmodifiableUint8ListView at JS interop.
    // Rendering must use a native typed array copied once, not the draft view.
    expect(a.imageProvider.bytes.runtimeType, Uint8List(0).runtimeType);
    expect(a.imageProvider.bytes, isNot(same(a.bytes)));
    expect(a.imageProvider.bytes, orderedEquals(a.bytes));
    expect(a.imageProvider, same(a.imageProvider));
    final huge = Uint8List.fromList(png);
    ByteData.sublistView(huge).setUint32(16, 100000);
    await expectLater(
      FloorPlanAsset.validate(huge, 'huge.png', 'image/png'),
      throwsFormatException,
    );
  });

  test(
    'Version 2 round-trip preserves actual image bytes, metadata and graph',
    () async {
      final map = await populated();
      final restored = await restore(map.encode());
      expect(restored.toJson(), map.toJson());
      expect(restored.image!.bytes, orderedEquals(png));
      expect(restored.image!.name, 'test-floor.png');
      expect(restored.layoutReviewed, isFalse);
      expect(restored.toJson()['verifiedForPatientUse'], isFalse);
      for (final change in ['floor', 'image', 'node', 'edge', 'approval']) {
        final data = map.toJson();
        switch (change) {
          case 'floor':
            data['floorId'] = 999;
          case 'image':
            (data['image'] as Map)['width'] = 999;
          case 'node':
            (data['nodes'] as List).first['x'] = 2;
          case 'edge':
            (data['edges'] as List).first['toNodeCode'] = 'missing';
          case 'approval':
            data['verifiedForPatientUse'] = true;
        }
        await expectLater(
          restore(Uint8List.fromList(utf8.encode(jsonEncode(data)))),
          throwsFormatException,
        );
      }
    },
  );

  test('Legacy draft with embedded image remains importable', () async {
    final map = await populated();
    final legacy = map.toJson()
      ..['version'] = 1
      ..remove('image')
      ..remove('floor')
      ..['imageBase64'] = base64Encode(png);
    final restored = await restore(
      Uint8List.fromList(utf8.encode(jsonEncode(legacy))),
    );
    expect(restored.image!.bytes, orderedEquals(png));
    expect(restored.nodes.length, 3);
  });

  test(
    'Local preview is directed, reviewed, route-only and never publishes',
    () async {
      final map = await populated();
      expect(() => map.previewRoute('A', 'B'), throwsFormatException);
      map.layoutReviewed = true;
      final route = map.previewRoute('A', 'B');
      expect(route.nodeCodes, ['A', 'B']);
      expect(route.meters, 8.25);
      final painter = DraftMapPainter(map, null, preview: true, route: route);
      expect(painter.visibleNodeCodes, ['A', 'B']);
      expect(painter.visibleEdges.length, 1);
      expect(
        DraftMapPainter(map, null, preview: true).visibleNodeCodes,
        isEmpty,
      );
      expect(() => map.previewRoute('B', 'A'), throwsFormatException);
      expect(() => map.previewRoute('A', 'C'), throwsFormatException);
      expect(map.previewRoute('A', 'A').nodeCodes, ['A']);
      final old = map.edges.single;
      map.updateEdge(old, const DraftEdge('A', 'B', 5, 'Door'));
      expect(map.layoutReviewed, isFalse);
      map.layoutReviewed = true;
      expect(map.previewRoute('A', 'B').meters, 5);
      map.removeNode('B');
      expect(map.edges, isEmpty);
      expect(map.nodes.length, 2);
      expect(map.toJson()['verifiedForPatientUse'], isFalse);
    },
  );

  late MemoryDraftFiles files;
  late MockClient client;
  setUp(() {
    files = MemoryDraftFiles();
    AuthSession.accessToken = 'floor-workflow-token';
    client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.headers['Authorization'], 'Bearer floor-workflow-token');
      final path = request.url.path;
      final Object data = path.endsWith('/sites')
          ? [
              {'id': 1, 'name': 'Test site'},
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
  });
  tearDown(() {
    client.close();
    AuthSession.clear();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('floor-editor-capture'),
        child: MaterialApp(
          home: DraftMapEditor(
            api: WayMarkApiService(client: client),
            files: files,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final pair in [
      ('Site', 'Test site'),
      ('Building', 'Building'),
      ('Floor', 'Floor one'),
    ]) {
      await tester.tap(find.byKey(ValueKey('draft-${pair.$1}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(pair.$2).last);
      await tester.pumpAndSettle();
    }
  }

  Future<void> settleImages(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await tester.runAsync(() async {
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          await precacheImage(
            image.image,
            tester.element(find.byType(DraftMapEditor)),
          ).timeout(const Duration(seconds: 5));
        }
      });
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapAsync(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(key));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await settleImages(tester);
  }

  DraftMapPainter painter(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(find.byKey(const Key('floor-route-canvas')))
              .painter!
          as DraftMapPainter;

  testWidgets(
    'Picker success shows real image/name/size; errors and cancel keep old image',
    (tester) async {
      await open(tester);
      files.next = (bytes: png, name: 'my-floor.png', mime: 'image/png');
      await tapAsync(tester, const Key('pick-floor-image'));
      expect(find.byKey(const Key('draft-image-thumbnail')), findsOneWidget);
      expect(find.text('my-floor.png'), findsOneWidget);
      expect(painter(tester).draft.image!.width, 160);
      expect(find.textContaining('Đã tải my-floor.png'), findsWidgets);
      expect(find.byKey(const Key('draft-image-thumbnail')), findsOneWidget);
      expect(find.byKey(const Key('floor-plan-image-layer')), findsOneWidget);
      expect(
        find.byKey(const Key('draft-image-alignment-warning')),
        findsOneWidget,
      );
      if (!kIsWeb &&
          const bool.fromEnvironment('WAYMARK_CAPTURE_FLOOR_EDITOR')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('floor-editor-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary
              .toImage(pixelRatio: 1)
              .timeout(const Duration(seconds: 15));
          try {
            final data = await image
                .toByteData(format: ui.ImageByteFormat.png)
                .timeout(const Duration(seconds: 15));
            final output = File('.dart_tool/phase7b/editor-1600.png');
            await output.parent.create(recursive: true);
            await output.writeAsBytes(data!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
      final previous = painter(tester).draft.image;
      files.next = (
        bytes: Uint8List.fromList([1, 2, 3]),
        name: 'bad.png',
        mime: 'image/png',
      );
      await tapAsync(tester, const Key('pick-floor-image'));
      expect(painter(tester).draft.image, same(previous));
      expect(find.textContaining('Chỉ nhận PNG/JPG'), findsWidgets);
      files.next = null;
      await tapAsync(tester, const Key('pick-floor-image'));
      expect(painter(tester).draft.image, same(previous));
      expect(find.textContaining('Đã hủy chọn ảnh'), findsWidgets);
      expect(AuthSession.accessToken, 'floor-workflow-token');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Drag under zoom saves normalized position; export/import restores image and graph',
    (tester) async {
      await open(tester);
      files.next = (bytes: png, name: 'graph.png', mime: 'image/png');
      await tapAsync(tester, const Key('pick-floor-image'));
      final map = painter(tester).draft;
      await tester.ensureVisible(find.byKey(const Key('floor-route-canvas')));
      await tester.pumpAndSettle();
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      viewer.transformationController!.value = Matrix4.diagonal3Values(
        1.5,
        1.5,
        1,
      )..setTranslationRaw(-40, -30, 0);
      await tester.pump();
      final rect = tester.getRect(find.byKey(const Key('floor-route-canvas')));
      final node = map.nodes.first;
      final gesture = await tester.startGesture(
        rect.topLeft + Offset(rect.width * node.x, rect.height * node.y),
      );
      await tester.pump();
      await gesture.moveBy(Offset(rect.width * .1, rect.height * .1));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(map.nodes.first.x, closeTo(node.x + .1, .001));
      expect(map.nodes.first.y, closeTo(node.y + .1, .001));
      await tapAsync(tester, const Key('export-draft'));
      expect(files.saved, isNotNull);
      final restored = await tester.runAsync(() => restore(files.saved!));
      expect(restored!.toJson(), map.toJson());
      files.next = (
        bytes: files.saved!,
        name: 'restore.json',
        mime: 'application/json',
      );
      await tester.ensureVisible(find.byKey(const Key('import-draft')));
      await tester.tap(find.byKey(const Key('import-draft')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Rời bản nháp'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await settleImages(tester);
      expect(painter(tester).draft.toJson(), map.toJson());
      expect(find.byKey(const Key('draft-image-thumbnail')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Canvas selects edges for editing, and node deletion is confirmed',
    (tester) async {
      await open(tester);
      files.next = (bytes: png, name: 'edit.png', mime: 'image/png');
      await tapAsync(tester, const Key('pick-floor-image'));
      final map = painter(tester).draft;
      map.addEdge(
        DraftEdge(map.nodes.first.code, map.nodes.last.code, 8, 'Corridor'),
      );
      await tester.ensureVisible(find.byKey(const Key('floor-route-canvas')));
      await tester.pumpAndSettle();
      var rect = tester.getRect(find.byKey(const Key('floor-route-canvas')));
      await tester.tapAt(
        rect.topLeft + Offset(rect.width * .45, rect.height * .5),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit-draft-edge')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '12.5');
      await tester.tap(find.text('Lưu cạnh nháp'));
      await tester.pumpAndSettle();
      expect(map.edges.single.meters, 12.5);
      await tester.tap(find.byKey(const Key('delete-draft-edge')));
      await tester.pumpAndSettle();
      expect(map.edges, isEmpty);
      rect = tester.getRect(find.byKey(const Key('floor-route-canvas')));
      await tester.tapAt(
        rect.topLeft + Offset(rect.width * .2, rect.height * .3),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete-draft-node')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(map.nodes.length, 2);
      await tester.tap(find.byKey(const Key('delete-draft-node')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-delete-node')));
      await tester.pumpAndSettle();
      expect(map.nodes.length, 1);
      expect(map.image, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Preview mode hides editor graph and stays responsive', (
    tester,
  ) async {
    await open(tester);
    files.next = (bytes: png, name: 'preview.png', mime: 'image/png');
    await tapAsync(tester, const Key('pick-floor-image'));
    final map = painter(tester).draft;
    map.putNode(const DraftNode('UNUSED', 'Not on route', .9, .1, 'Junction'));
    map.addEdge(
      DraftEdge(map.nodes[0].code, map.nodes[1].code, 8.25, 'Corridor'),
    );
    await tester.ensureVisible(find.byKey(const Key('draft-mode-preview')));
    await tester.tap(find.byKey(const Key('draft-mode-preview')));
    await tester.pumpAndSettle();
    expect(painter(tester).visibleNodeCodes, isEmpty);
    await tester.tap(find.byKey(const Key('review-draft-layout')));
    await tester.pumpAndSettle();
    for (final pair in [
      ('draft-route-start', 'Entrance'),
      ('draft-route-end', 'Lift'),
    ]) {
      await tester.ensureVisible(find.byKey(ValueKey(pair.$1)));
      await tester.tap(find.byKey(ValueKey(pair.$1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(pair.$2).last);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.byKey(const Key('preview-draft-route')));
    await tester.tap(find.byKey(const Key('preview-draft-route')));
    await tester.pumpAndSettle();
    expect(painter(tester).visibleNodeCodes, ['TEST-0', 'TEST-1']);
    expect(painter(tester).visibleEdges.length, 1);
    expect(find.textContaining('8.25 m'), findsOneWidget);
    expect(find.byKey(const Key('delete-draft-node')), findsNothing);
    tester.view.physicalSize = const Size(390, 850);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(painter(tester).visibleNodeCodes, hasLength(2));
  });
}
