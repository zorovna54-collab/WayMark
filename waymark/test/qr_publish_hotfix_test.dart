import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:waymark/features/admin/draft_map_editor.dart';
import 'package:waymark/features/admin/map_project_cloud_page.dart';
import 'package:waymark/features/admin/project_publish_state.dart';
import 'package:waymark/features/admin/local_map_project.dart';
import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/admin/draft_recovery.dart';
import 'package:waymark/features/navigation/navigation_page.dart';
import 'package:waymark/features/route/floor_plan_canvas.dart';
import 'package:waymark/features/scanner/scanner_page.dart';
import 'package:waymark/features/search/local_map_search_page.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/map_draft_api_service.dart';
import 'package:waymark/services/waymark_api_service.dart';

import 'fixtures/personal_qr_http_fixture.dart';
import 'draft_floor_workflow_test.dart' show MemoryDraftFiles;
import 'floor_image_cleanup_test.dart' show cleanupTestImage;
import 'scanner_camera_test.dart' show CameraFake;
import 'published_map_test.dart' show SessionApi;

final _evidenceKey = GlobalKey();

class NoRecovery extends DraftRecovery {
  @override
  bool get supported => false;
}

const _captureEvidence = bool.fromEnvironment('WAYMARK_CAPTURE_QR_HOTFIX');
Future<void> captureEvidence(WidgetTester t, String name) async {
  if (!_captureEvidence) return;
  await t.pumpAndSettle();
  await t.runAsync(() async {
    final boundary =
        _evidenceKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final pixels = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await pixels.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/qr-publish-hotfix/widget-$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      pixels.dispose();
    }
  });
}

Future<void> tapText(WidgetTester t, String text) async {
  final finder = find.text(text);
  await t.scrollUntilVisible(
    finder,
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await t.pumpAndSettle();
  await t.tap(finder);
  if (text == 'Server / Publish / QR') {
    // Busy indicator is intentional while the detached image codec runs.
    // Give the native codec real time before waiting for animations to settle.
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
  }
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    if (!_captureEvidence) return;
    for (final family in ['Roboto', 'Inter']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  tearDown(AuthSession.clear);
  Future<void> open(
    WidgetTester t,
    PersonalQrHttpFixture h, {
    MemoryDraftFiles? files,
    bool builder = false,
  }) async {
    AuthSession.accessToken = 'personal-test-user';
    final link = ProjectCloudLink(h.copyDocument(), h.project);
    final api = WayMarkApiService(client: h.client);
    await t.pumpWidget(
      RepaintBoundary(
        key: _evidenceKey,
        child: MaterialApp(
          home: builder
              ? DraftMapEditor(
                  recovery: NoRecovery(),
                  initialProject: h.project,
                  initialCloudLink: link,
                  api: api,
                  files: files,
                )
              : MapProjectCloudPage(
                  project: h.project,
                  link: link,
                  api: api,
                  maps: h.api,
                  files: files,
                ),
        ),
      ),
    );
    if (builder) {
      await t.runAsync(
        () => precacheImage(
          h.image.imageProvider,
          t.element(find.byType(DraftMapEditor)),
        ),
      );
    }
    await t.pumpAndSettle();
  }

  testWidgets(
    'Onboarding v1 empty server + 3 local nodes reproduces disabled QR and explains source of truth',
    (t) async {
      final h = PersonalQrHttpFixture((await t.runAsync(cleanupTestImage))!);
      await open(t, h);
      await t.scrollUntilVisible(
        find.byKey(const Key('local-server-counts')),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Local: 3 node'), findsOneWidget);
      expect(find.textContaining('Server v1: 0 node'), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Tạo / xem QR cho Node'),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.textContaining('Chưa có Node được lưu trên Server'),
        findsWidgets,
      );
      expect(h.gets, greaterThan(0));
      expect(h.uploads, 0);
      expect(h.saves, 0);
    },
  );
  testWidgets(
    'Reading empty server workspace from Builder must not replace 3-node local graph',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final h = PersonalQrHttpFixture((await t.runAsync(cleanupTestImage))!);
      await open(t, h, builder: true);
      await tapText(t, 'Server / Publish / QR');
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, 'Tải draft'));
      await t.pumpAndSettle();
      if (find.text('Tải bản server').evaluate().isNotEmpty) {
        await t.tap(find.text('Tải bản server'));
        await t.pumpAndSettle();
      }
      await t.scrollUntilVisible(
        find.byKey(const Key('local-server-counts')),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Local: 3 node • 2 cạnh.'), findsOneWidget);
      expect(h.project.floors.single.nodes, hasLength(3));
      expect(h.saves, 0);
    },
  );
  testWidgets(
    'Upload 503 never claims graph saved and retry after known pre-write refusal is not stuck in reconciliation',
    (t) async {
      final h = PersonalQrHttpFixture((await t.runAsync(cleanupTestImage))!)
        ..failUpload = true;
      await open(t, h);
      await tapText(t, 'Lưu draft nhiều tầng lên server');
      expect(h.saves, 0);
      expect(h.headExists, isTrue);
      expect(find.textContaining('Upload ảnh tầng Floor G'), findsOneWidget);
      expect(find.textContaining('Backend chưa bật kho ảnh'), findsWidgets);
      expect(h.project.floors.single.nodes, hasLength(3));
      expect(
        const MapDraftApiException(
          'disabled',
          status: 503,
          code: 'image_storage_unavailable',
        ).uncertain,
        isFalse,
      );
      h.failUpload = false;
      await tapText(t, 'Lưu draft nhiều tầng lên server');
      expect(h.saves, 1);
      expect(h.document['version'], 2);
      expect(h.savedNodes, hasLength(3));
      expect(
        find.textContaining('Đã lưu và GET xác nhận draft v2'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'Read-only readiness reports disabled storage before any create/upload/save request',
    (t) async {
      final h = PersonalQrHttpFixture((await t.runAsync(cleanupTestImage))!)
        ..storageConfigured = false;
      await open(t, h);
      await tapText(t, 'Lưu draft nhiều tầng lên server');
      expect(h.uploads, 0);
      expect(h.saves, 0);
      expect(h.headExists, isFalse);
      expect(find.textContaining('Backend chưa bật kho ảnh'), findsWidgets);
      expect(h.project.floors.single.nodes, hasLength(3));
    },
  );
  test('Saved QR GUID normalization does not change identity and .NET number/key formatting is tolerated', () {
    const id = '00000000-AAAA-4000-8000-000000000001',
        floor = '00000000-BBBB-4000-8000-000000000001';
    final doc = {
      'content': {
        'floors': [
          {
            'id': floor,
            'name': 'Floor',
            'content': {
              'nodes': [
                {'id': id, 'name': 'Node', 'nodeCode': 'x'},
              ],
            },
          },
        ],
      },
    };
    expect(savedQrNodes(doc).single.id, id.toLowerCase());
    expect(savedQrNodes(doc).single.floorKey, floor.toLowerCase());
    expect(
      sameProjectGraph(
        {'id': id, 'name': 'NODE'},
        {'id': id.toLowerCase(), 'name': 'NODE'},
      ),
      isTrue,
    );
    expect(
      sameProjectGraph(
        {'id': id, 'name': 'NODE'},
        {'id': id.toLowerCase(), 'name': 'node'},
      ),
      isFalse,
    );
    expect(
      sameProjectGraph(
        {
          'id': 'x',
          'x': 1,
          'info': {'server': true},
        },
        {'x': 1.0, 'id': 'x'},
      ),
      isTrue,
    );
  });
  testWidgets(
    'Recover legacy v2 in opened personal map preserves project/floor/node IDs; next export stays v3',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final h = PersonalQrHttpFixture((await t.runAsync(cleanupTestImage))!);
      final files = MemoryDraftFiles()
        ..next = (
          bytes: h.project.floors.single.encode(),
          name: 'backup-v2.json',
          mime: 'application/json',
        );
      await open(t, h, files: files, builder: true);
      final openFile = find.text('Mở JSON');
      await t.scrollUntilVisible(
        openFile,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(openFile);
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      // The deliberate import confirmation keeps the editor busy underneath;
      // its indeterminate progress indicator must not be awaited to settle.
      await t.pump(const Duration(milliseconds: 350));
      await t.tap(find.text('Khôi phục vào bản đồ này'));
      await t.pump(const Duration(milliseconds: 350));
      final restoredCanvas = t.widget<FloorPlanCanvas>(
        find.byType(FloorPlanCanvas),
      );
      await t.runAsync(
        () => precacheImage(
          restoredCanvas.image!,
          t.element(find.byType(FloorPlanCanvas)),
        ),
      );
      await t.pumpAndSettle();
      await tapText(t, 'Lưu JSON + ảnh');
      final recovered = (await t.runAsync(
        () => LocalMapProject.decode(files.saved!),
      ))!;
      expect(recovered.id, h.project.id);
      expect(recovered.floors.single.nodeIds, h.project.floors.single.nodeIds);
      final other = LocalMapProject(
        DraftMap.local('Other', 'Other', 'Other', 'X'),
      );
      expect(
        () =>
            LocalMapProject.recoverSingleFloor(h.project.floors.single, other),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'Builder -> upload+PUT+GET -> select server Junction GUID -> QR PNG -> Publish -> Guest fake scan -> 12m -> Arrival',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final h = PersonalQrHttpFixture((await t.runAsync(cleanupTestImage))!);
      final files = MemoryDraftFiles();
      await open(t, h, files: files, builder: true);
      await tapText(t, 'Server / Publish / QR');
      // Builder detaches/decodes its image before opening the route; allow the
      // real image codec to finish outside the widget test's fake clock.
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await t.pumpAndSettle();
      expect(
        find.byType(MapProjectCloudPage),
        findsOneWidget,
        reason: t
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join(" / "),
      );
      await tapText(t, 'Lưu draft nhiều tầng lên server');
      expect(h.document['version'], 2);
      expect(h.savedNodes, hasLength(3));
      final savedIds = h.project.floors.single.nodeIds.values.toSet();
      expect(h.savedNodes.map((n) => n['id']).toSet(), savedIds);
      final dropdown = find.byWidgetPredicate(
        (w) => w is DropdownButtonFormField<String>,
      );
      await t.scrollUntilVisible(
        dropdown,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(dropdown);
      await t.pumpAndSettle();
      await t.tap(find.text('Floor G • N01 · Start junction').last);
      await t.pumpAndSettle();
      await tapText(t, 'Tạo / xem QR cho Node');
      expect(h.qr!['nodeId'], h.project.floors.single.nodeId('QR-JUNCTION'));
      await captureEvidence(t, 'qr-created');
      final png = (await t.runAsync(() => nodeQrPng(h.payload)))!;
      final codec = (await t.runAsync(() => ui.instantiateImageCodec(png)))!;
      final frame = (await t.runAsync(codec.getNextFrame))!;
      expect(frame.image.width, 640);
      expect(frame.image.height, 640);
      frame.image.dispose();
      codec.dispose();
      await t.tap(find.text('Đóng'));
      await t.pumpAndSettle();
      await tapText(t, 'Xuất bản snapshot đã lưu');
      await t.tap(find.text('Xuất bản snapshot'));
      await t.pumpAndSettle();
      expect(h.publication, isNotNull);
      expect(h.qr!['publishedVersion'], 2);
      await captureEvidence(t, 'published');
      final publishedIds =
          (h.publication!['content']['floors'][0]['content']['nodes'] as List)
              .map((n) => n['id'])
              .toSet();
      expect(publishedIds, savedIds);
      AuthSession.clear();
      final session = (await t.runAsync(() => h.api.loadQr(h.payload)))!;
      expect(session.nodeId, h.project.floors.single.nodeId('QR-JUNCTION'));
      final destination = session.map.destinationNodes.single;
      expect(
        session.map
            .routeToNode(
              session.startKey,
              destination.nodeId,
              destination.floorId,
            )
            .totalDistanceMeters,
        12,
      );
      final original = MobileScannerPlatform.instance, camera = CameraFake();
      MobileScannerPlatform.instance = camera;
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        MobileScannerPlatform.instance = original;
        await camera.captures.close();
      });
      await t.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: ScannerPage(publishedApi: SessionApi(session)),
        ),
      );
      await t.pumpAndSettle();
      camera.captures.add(
        BarcodeCapture(barcodes: [Barcode(rawValue: h.payload)]),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Chọn điểm đến'));
      await t.pumpAndSettle();
      await t.runAsync(
        () => precacheImage(
          session.map.image!,
          t.element(find.byType(LocalMapSearchPage)),
        ),
      );
      await tapText(t, 'Clinic destination (DEST)');
      expect(find.text('12 m'), findsWidgets);
      await t.tap(find.text('Bắt đầu dẫn đường'));
      await t.pumpAndSettle();
      expect(find.byType(NavigationPage), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await t.tap(find.byKey(const Key('navigation-confirm')));
        await t.pumpAndSettle();
      }
      expect(find.byKey(const Key('navigation-complete')), findsOneWidget);
      expect(AuthSession.accessToken, isNull);
      expect(t.takeException(), isNull);
    },
  );
}
