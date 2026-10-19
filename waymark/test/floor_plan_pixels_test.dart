import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/route/floor_plan_canvas.dart';
import 'package:waymark/features/admin/floor_plan_asset.dart';

class _Graph extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(size.width * .2, size.height * .55),
      Offset(size.width * .8, size.height * .55),
      Paint()
        ..color = Colors.purple
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      Offset(size.width * .2, size.height * .55),
      6,
      Paint()..color = Colors.purple,
    );
  }

  @override
  bool shouldRepaint(covariant _Graph oldDelegate) => false;
}

class _Frames extends ImageStreamCompleter {
  void emit(ui.Image image) => setImage(ImageInfo(image: image));
}

class _ControlledImage extends ImageProvider<_ControlledImage> {
  final frames = _Frames();
  @override
  Future<_ControlledImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    _ControlledImage key,
    ImageDecoderCallback decode,
  ) => frames;
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    ImageProvider? image, {
    double width = 700,
    double height = 520,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: FloorPlanCanvas(image: image, painter: _Graph()),
          ),
        ),
      ),
    );
    if (image is MemoryImage) {
      await tester.runAsync(
        () =>
            precacheImage(image, tester.element(find.byType(FloorPlanCanvas))),
      );
    }
    await tester.pumpAndSettle();
  }

  Future<void> assertCorners(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('floor-plan-surface')),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final colors = [
      const Color(0xFFFF0000),
      const Color(0xFF00FF00),
      const Color(0xFF0000FF),
      const Color(0xFFFFFF00),
    ];
    final points = [
      const Offset(.04, .04),
      const Offset(.96, .04),
      const Offset(.04, .90),
      const Offset(.96, .90),
    ];
    for (var i = 0; i < points.length; i++) {
      final x = (points[i].dx * image.width).floor();
      final y = (points[i].dy * image.height).floor();
      final offset = (y * image.width + x) * 4;
      final actual = [
        data!.getUint8(offset),
        data.getUint8(offset + 1),
        data.getUint8(offset + 2),
      ];
      final expected = [
        colors[i].r * 255,
        colors[i].g * 255,
        colors[i].b * 255,
      ];
      for (var channel = 0; channel < 3; channel++) {
        expect(
          actual[channel],
          closeTo(expected[channel], 18),
          reason: 'visible corner $i, channel $channel',
        );
      }
    }
    image.dispose();
  }

  for (final extension in ['png', 'jpg']) {
    testWidgets(
      '900x598 clinic $extension paints all corners on MAIN canvas, fit, hide, resize',
      (tester) async {
        final bytes = File('test/fixtures/floor_plan_render_probe.$extension')
            .readAsBytesSync();
        final asset = await tester.runAsync(
          () => FloorPlanAsset.validate(
            bytes,
            'probe.$extension',
            extension == 'png' ? 'image/png' : 'image/jpeg',
          ),
        );
        final provider = asset!.imageProvider;
        await mount(tester, provider);
        var rect = tester.getRect(
          find.byKey(const Key('floor-plan-image-layer')),
        );
        expect(rect.width / rect.height, closeTo(900 / 598, .00001));
        expect(
          rect,
          tester.getRect(find.byKey(const Key('floor-route-canvas'))),
        );
        await tester.runAsync(() => assertCorners(tester));
        if (extension == 'png') {
          await expectLater(
            find.byKey(const Key('floor-plan-surface')),
            matchesGoldenFile('goldens/floor_plan_clinic_canvas.png'),
          );
        }
        final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        viewer.transformationController!.value = Matrix4.diagonal3Values(
          2,
          2,
          1,
        )..setTranslationRaw(-80, -50, 0);
        await tester.pump();
        expect(
          tester.getRect(find.byKey(const Key('floor-plan-image-layer'))),
          tester.getRect(find.byKey(const Key('floor-route-canvas'))),
        );
        await tester.tap(find.byKey(const Key('toggle-floor-image')));
        await tester.pump();
        expect(find.byKey(const Key('floor-plan-image-layer')), findsNothing);
        await tester.tap(find.byKey(const Key('toggle-floor-image')));
        await tester.tap(find.byKey(const Key('fit-floor-image')));
        await tester.pumpAndSettle();
        expect(viewer.transformationController!.value, Matrix4.identity());
        await tester.runAsync(() => assertCorners(tester));
        viewer.transformationController!.value = Matrix4.diagonal3Values(
          2,
          2,
          1,
        );
        await mount(tester, provider, width: 340, height: 550);
        expect(viewer.transformationController!.value, Matrix4.identity());
        rect = tester.getRect(find.byKey(const Key('floor-plan-image-layer')));
        expect(rect.width / rect.height, closeTo(900 / 598, .00001));
        await tester.runAsync(() => assertCorners(tester));
        final replacement = MemoryImage(
          File('test/fixtures/floor_plan_render_probe.png').readAsBytesSync(),
        );
        viewer.transformationController!.value = Matrix4.diagonal3Values(
          3,
          3,
          1,
        );
        await mount(tester, replacement);
        expect(viewer.transformationController!.value, Matrix4.identity());
        await tester.runAsync(() => assertCorners(tester));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'image error followed by valid frame clears fallback; old stream cannot replace new image',
    (tester) async {
      final source = _ControlledImage();
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 600,
            height: 500,
            child: FloorPlanCanvas(image: source, painter: _Graph()),
          ),
        ),
      );
      source.frames.reportError(
        context: ErrorDescription('test image failure'),
        exception: StateError('test decode failure'),
        silent: true,
      );
      await tester.pump();
      expect(find.textContaining('Không render được ảnh'), findsOneWidget);
      final frame = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(
          File('test/fixtures/floor_plan_render_probe.png').readAsBytesSync(),
        );
        final decoded = await codec.getNextFrame();
        codec.dispose();
        return decoded.image;
      });
      source.frames.emit(frame!);
      await tester.pumpAndSettle();
      expect(find.textContaining('Không render được ảnh'), findsNothing);
      await tester.runAsync(() => assertCorners(tester));
      await mount(tester, null);
      source.frames.emit(frame.clone());
      await tester.pump();
      expect(find.byKey(const Key('floor-plan-image-layer')), findsNothing);
      expect(find.textContaining('chưa có ảnh tầng'), findsOneWidget);
    },
  );
}
