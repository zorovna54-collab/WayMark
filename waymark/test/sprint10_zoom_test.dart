import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/route/floor_route_map.dart';
import 'package:waymark/features/route/floor_route_geometry.dart';
import 'package:waymark/features/route/floor_plan_canvas.dart';
import 'package:waymark/models/route_models.dart';

import 'fixtures/routing_fixture.dart';

void main() {
  testWidgets(
    'Visitor raster marker diameter and cyan stroke remain screen-sized at 1x/2x/4x plus pan',
    (t) async {
      final data = floorGraphJson(1);
      for (final node in data['nodes'] as List) {
        node['y'] = .5;
      }
      final route = WayMarkRoute.fromJson(routeJson());
      final geometry = FloorRouteGeometry.build(
        route,
        FloorMapData.fromJson(data),
      );
      final dimensions = <int>[], strokes = <int>[];
      for (final zoom in [1.0, 2.0, 4.0]) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(Colors.white, BlendMode.src);
        const pan = Offset(30, 20);
        canvas.translate(pan.dx, pan.dy);
        canvas.scale(zoom);
        FloorRoutePainter(
          geometry: geometry,
          lastRouteIndex: 2,
          viewScale: zoom,
        ).paint(canvas, const Size(200, 100));
        final picture = recorder.endRecording();
        final image = (await t.runAsync(() => picture.toImage(900, 500)))!;
        final bytes = (await t.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        bool pixel(int x, int y, bool cyan) {
          final n = (y * 900 + x) * 4;
          final r = bytes.getUint8(n),
              g = bytes.getUint8(n + 1),
              b = bytes.getUint8(n + 2);
          return cyan
              ? r < 100 && g > 100 && b > 100
              : r < 50 && g < 80 && b < 110;
        }

        final x = (30 + 40 * zoom).round(), y = (20 + 50 * zoom).round();
        final marker = [
          for (var dx = -15; dx <= 15; dx++)
            if (pixel(x + dx, y, false)) dx,
        ];
        expect(marker, isNotEmpty);
        dimensions.add(marker.last - marker.first + 1);
        final lineX = (30 + 70 * zoom).round();
        final line = [
          for (var dy = -12; dy <= 12; dy++)
            if (pixel(lineX, y + dy, true)) dy,
        ];
        expect(line, isNotEmpty);
        strokes.add(line.last - line.first + 1);
        image.dispose();
        picture.dispose();
      }
      expect(
        dimensions.every((v) => (v - dimensions.first).abs() <= 1),
        isTrue,
        reason: 'Raster diameters $dimensions',
      );
      expect(
        strokes.every((v) => (v - strokes.first).abs() <= 1),
        isTrue,
        reason: 'Raster cyan strokes $strokes',
      );
    },
  );
  testWidgets(
    'Viewer zoom/pan keeps route, fit resets scale; switching floor uses a different keyed canvas',
    (t) async {
      final route = WayMarkRoute.fromJson(routeJson());
      final geometry = FloorRouteGeometry.build(
        route,
        FloorMapData.fromJson(floorGraphJson(1)),
      );
      double seenScale = 1;
      await t.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 400,
            child: FloorPlanCanvas(
              painterBuilder: (s) {
                seenScale = s;
                return FloorRoutePainter(
                  geometry: geometry,
                  lastRouteIndex: 2,
                  viewScale: s,
                );
              },
            ),
          ),
        ),
      );
      final controller = t
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      for (final scale in [2.0, 4.0]) {
        controller.value = Matrix4.identity()
          ..translateByDouble(15.0, 20.0, 0.0, 1.0)
          ..scaleByDouble(scale, scale, 1, 1);
        await t.pump();
        expect(controller.value.getMaxScaleOnAxis(), scale);
        expect(seenScale, scale);
        expect(geometry.segments, hasLength(1));
      }
      await t.tap(find.text('Fit Image'));
      await t.pump();
      expect(controller.value.getMaxScaleOnAxis(), 1);
    },
  );
}
