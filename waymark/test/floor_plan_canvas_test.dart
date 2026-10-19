import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/route/floor_plan_canvas.dart';

class _Painter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void main() {
  test(
    'Contain transform preserves ratio in portrait and landscape viewports',
    () {
      expect(
        containedFloorSize(const Size(1000, 500), const Size(300, 300)),
        const Size(300, 150),
      );
      expect(
        containedFloorSize(const Size(500, 1000), const Size(600, 300)),
        const Size(150, 300),
      );
      expect(containedFloorSize(Size.zero, const Size(300, 300)), Size.zero);
    },
  );

  testWidgets(
    'Image and overlay share exact fitted bounds through zoom and resize',
    (tester) async {
      final bytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.white, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(100, 50);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        image.dispose();
        picture.dispose();
        return bytes;
      });
      final provider = MemoryImage(bytes!);
      Offset? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 300,
              child: FloorPlanCanvas(
                image: provider,
                painter: _Painter(),
                onPoint: (point) => selected = point,
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          provider,
          tester.element(find.byType(FloorPlanCanvas)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('floor-route-canvas'))),
        const Size(300, 150),
      );
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      viewer.transformationController!.value = Matrix4.diagonal3Values(2, 2, 1)
        ..setTranslationRaw(-80, -60, 0);
      await tester.pump();
      final imageRect = tester.getRect(
        find.byKey(const Key('floor-plan-image-layer')),
      );
      final overlayRect = tester.getRect(
        find.byKey(const Key('floor-route-canvas')),
      );
      expect(overlayRect, imageRect);
      // Tap a known image coordinate after both zoom and pan. Hit testing must
      // undo the viewer transform before the editor normalizes the point.
      await tester.tapAt(
        overlayRect.topLeft +
            Offset(overlayRect.width * .25, overlayRect.height * .4),
      );
      await tester.pump();
      expect(selected!.dx, closeTo(.25, .000001));
      expect(selected!.dy, closeTo(.4, .000001));
      await tester.tap(find.byTooltip('Đặt lại thu phóng'));
      await tester.pumpAndSettle();
      expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 600,
              height: 300,
              child: FloorPlanCanvas(image: provider, painter: _Painter()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('floor-route-canvas'))),
        containedFloorSize(
          const Size(100, 50),
          tester.getSize(find.byType(InteractiveViewer)),
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
