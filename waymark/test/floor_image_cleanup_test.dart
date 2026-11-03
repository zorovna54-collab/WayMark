import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/admin/local_map_project.dart';
import 'package:waymark/features/admin/floor_plan_asset.dart';
import 'package:waymark/features/admin/floor_image_cleanup.dart';
import 'package:waymark/features/admin/floor_image_cleanup_page.dart';
import 'package:waymark/features/navigation/local_map_navigation.dart';

import 'draft_floor_workflow_test.dart' show MemoryDraftFiles;
import 'fixtures/multifloor_fixture.dart';

Future<FloorPlanAsset> cleanupTestImage() async {
  final r = ui.PictureRecorder(), c = Canvas(ui.PictureRecorder());
  final canvas = Canvas(r);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 120, 80),
    Paint()..color = Colors.white,
  );
  for (final (index, color) in [
    Colors.red,
    Colors.green,
    Colors.blue,
    Colors.yellow,
  ].indexed) {
    canvas.drawRect(
      Rect.fromLTWH(index % 2 * 100, index ~/ 2 * 60, 20, 20),
      Paint()..color = color,
    );
  }
  canvas.drawLine(
    const Offset(0, 40),
    const Offset(120, 40),
    Paint()
      ..color = Colors.black
      ..strokeWidth = 2,
  );
  final p = r.endRecording(),
      image = await p.toImage(120, 80),
      b = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  final asset = await FloorPlanAsset.validate(
    Uint8List.fromList(b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes)),
    'original.png',
    'image/png',
  );
  image.dispose();
  p.dispose();
  c.save();
  c.restore();
  return asset;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Perspective corners and inverse roundtrip; reject bowtie and singular quadrilateral', () {
    final q = [
          const Offset(.1, .2),
          const Offset(.9, .1),
          const Offset(.8, .9),
          const Offset(.2, .8),
        ],
        h = ImageTransform.fromQuad(q);
    const target = [Offset.zero, Offset(1, 0), Offset(1, 1), Offset(0, 1)];
    for (var i = 0; i < 4; i++) {
      expect((h.map(q[i]) - target[i]).distance, lessThan(1e-8));
      expect((h.inverse().map(target[i]) - q[i]).distance, lessThan(1e-8));
    }
    expect(
      () => ImageTransform.fromQuad([q[0], q[2], q[1], q[3]]),
      throwsFormatException,
    );
  });
  test('Identity real raster and 90-degree positions; fine rotation expands bounds; grayscale changes actual PNG pixels', () async {
    final image = await cleanupTestImage(),
        identity = await cleanupFloorImage(image, ImageCleanupSettings());
    expect(
      identity.asset.bytes,
      image.bytes,
    ); // Flutter PNG encoder is deterministic for identical pixels.
    final turn = await cleanupFloorImage(
      image,
      ImageCleanupSettings(quarterTurns: 1),
    );
    expect(turn.asset.width, 80);
    expect(turn.asset.height, 120);
    expect(
      (turn.edit.transform.map(const Offset(.1, .2)) - const Offset(.8, .1))
          .distance,
      lessThan(1e-8),
    );
    final angle = ImageCleanupSettings(degrees: 5).geometry(120, 80);
    expect(angle.width, greaterThan(120));
    expect(angle.height, greaterThan(80));
    final gray = await cleanupFloorImage(
      image,
      ImageCleanupSettings(grayscale: true, contrast: 1.2, brightness: .05),
    );
    expect(gray.asset.bytes, isNot(image.bytes));
    final codec = await ui.instantiateImageCodec(gray.asset.bytes),
        frame = (await codec.getNextFrame()).image,
        b = (await frame.toByteData())!;
    for (var p = 0; p < b.lengthInBytes; p += 4) {
      expect(b.getUint8(p), b.getUint8(p + 1));
      expect(b.getUint8(p), b.getUint8(p + 2));
    }
    frame.dispose();
    codec.dispose();
  });
  test('Atomic crop guard, graph/Room transform, second edit does not double transform; original and other floors survive v3', () async {
    final project = threeFloorProject(), d = project.floors[1];
    d.image = await cleanupTestImage();
    final original = d.image!,
        other = project.floors[2].encode(),
        ids = Map.of(d.nodeIds),
        edges = jsonEncode(d.edges.map((e) => e.toJson()).toList()),
        roomIds = d.places.single['entranceNodeIds'];
    final crop = await cleanupFloorImage(
      original,
      ImageCleanupSettings(
        corners: const [
          Offset(.05, .05),
          Offset(.95, .05),
          Offset(.95, .95),
          Offset(.05, .95),
        ],
      ),
    );
    d.applyImageCleanup(crop);
    expect(d.nodes.first.x, closeTo((.1 - .05) / .9, 1e-8));
    expect(d.nodeIds, ids);
    expect(d.places.single['entranceNodeIds'], roomIds);
    expect(jsonEncode(d.edges.map((e) => e.toJson()).toList()), edges);
    final turn = await cleanupFloorImage(
      original,
      ImageCleanupSettings(quarterTurns: 1),
    );
    d.applyImageCleanup(turn);
    expect(d.nodes.first.x, closeTo(.5, 1e-8));
    expect(d.nodes.first.y, closeTo(.1, 1e-8));
    expect(project.floors[2].encode(), other);
    final copy = await LocalMapProject.decode(project.encode());
    expect(copy.floors[1].imageEdit!.original.bytes, original.bytes);
    expect(copy.floors[1].image!.bytes, turn.asset.bytes);
    expect(copy.floors[1].nodeIds, ids);
    final route = (await LocalMapNavigation.fromProject(copy)).routeToRoom(
      copy.floors[0].nodeId('START'),
      copy.floors[2].places.single['id'],
    );
    expect(route.totalDistanceMeters, 30);
    final before = d.encode(),
        bad = await cleanupFloorImage(
          original,
          ImageCleanupSettings(
            corners: const [
              Offset(.6, .1),
              Offset(.95, .1),
              Offset(.95, .9),
              Offset(.6, .9),
            ],
          ),
        );
    expect(() => d.applyImageCleanup(bad), throwsFormatException);
    expect(d.encode(), before);
    d.applyImageCleanup(
      await cleanupFloorImage(original, ImageCleanupSettings()),
    );
    expect(d.nodes.first.x, closeTo(.1, 1e-8));
  });
  testWidgets(
    'Editor cancel/undo/reset never changes draft; preview outputs PNG and apply explicitly confirms',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final original = await t.runAsync(cleanupTestImage);
      CleanedFloorImage? result;
      final files = MemoryDraftFiles();
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FloorImageCleanupPage(
                        original: original!,
                        floorName: 'I',
                        files: files,
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      final corner=find.byKey(const Key('cleanup-corner-0'));
      final before=t.getCenter(corner);
      await t.drag(corner,const Offset(36,0));await t.pumpAndSettle();
      expect(t.getCenter(corner).dx,greaterThan(before.dx+8));
      await t.tap(find.text('Reset gốc'));await t.pumpAndSettle();
      final top=t.getCenter(corner).dy;
      await t.drag(corner,const Offset(0,36));await t.pumpAndSettle();
      expect(t.getCenter(corner).dy,greaterThan(top+8));
      await t.tap(find.text('Reset gốc'));await t.pumpAndSettle();
      await t.tap(find.text('Xoay 90° (0°)'));
      await t.pumpAndSettle();
      await t.tap(find.text('Undo'));
      await t.pumpAndSettle();
      expect(find.text('Xoay 90° (0°)'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(result, isNull);
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byKey(const Key('cleanup-preview')), 350);
      await t.runAsync(() async {
        await t.tap(find.byKey(const Key('cleanup-preview')));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await t.pumpAndSettle();
      expect(find.textContaining('120 × 80 PNG'), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const Key('cleanup-apply')), 350);
      await t.tap(find.byKey(const Key('cleanup-apply')));
      await t.pumpAndSettle();
      expect(find.text('Áp dụng ảnh và tọa độ?'), findsOneWidget);
      await t.tap(find.text('Áp dụng lên tầng này'));
      await t.pumpAndSettle();
      expect(result, isNotNull);
    },
  );
}
