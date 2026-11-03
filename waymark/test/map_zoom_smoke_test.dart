import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/admin/draft_map_editor.dart';
import 'package:waymark/features/route/floor_plan_canvas.dart';

import 'fixtures/map_draft_fixture.dart';

void main() {
  testWidgets(
    'Second finger cancels node drag without committing coordinates',
    (t) async {
      var cancelled = 0, committed = 0;
      final draft = localDraft();
      final before = jsonEncode(draft.toJson());
      await t.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(
            child: FloorPlanCanvas(
              painterBuilder: (scale) =>
                  DraftMapPainter(draft, null, viewScale: scale),
              onDragStart: (_) => true,
              onDragCancel: () => cancelled++,
              onDragEnd: () => committed++,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final center = t.getCenter(find.byKey(const Key('floor-route-canvas')));
      final first = await t.startGesture(
        center - const Offset(30, 0),
        pointer: 1,
      );
      await t.pump();
      final second = await t.startGesture(
        center + const Offset(30, 0),
        pointer: 2,
      );
      await t.pump();
      await first.moveBy(const Offset(-40, 0));
      await second.moveBy(const Offset(40, 0));
      await t.pump();
      await first.up();
      await second.up();
      await t.pumpAndSettle();
      expect(cancelled, 1);
      expect(committed, 0);
      expect(jsonEncode(draft.toJson()), before);
    },
  );
  testWidgets(
    '1x/2x/4x keep marker/edge pixels, anchors, hit coordinates and Fit',
    (t) async {
      final draft = DraftMap(siteId: 1, buildingId: 1, floor: draftFloor())
        ..putNode(const DraftNode('A', 'A', .4, .5, 'Junction'))
        ..putNode(const DraftNode('B', 'B', .6, .5, 'Junction'))
        ..addEdge(const DraftEdge('A', 'B', 5, 'Corridor'));
      final before = jsonEncode(draft.toJson());
      Offset? tapped, dragged;
      await t.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              height: 348,
              child: RepaintBoundary(
                key: const Key('proof'),
                child: ColoredBox(
                  color: Colors.white,
                  child: FloorPlanCanvas(
                    painterBuilder: (scale) =>
                        DraftMapPainter(draft, null, viewScale: scale),
                    onPoint: (p) => tapped = p,
                    onDragStart: (_) => true,
                    onDragUpdate: (p) => dragged = p,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final viewer = t.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final viewport = t.getSize(find.byType(InteractiveViewer));
      final origin = t.getTopLeft(find.byType(InteractiveViewer));
      for (final scale in [1.0, 2.0, 4.0]) {
        final matrix = Matrix4.diagonal3Values(scale, scale, 1)
          ..setEntry(0, 3, viewport.width * (1 - scale) / 2)
          ..setEntry(1, 3, viewport.height * (1 - scale) / 2);
        viewer.transformationController!.value = matrix;
        await t.pumpAndSettle();
        final node = Offset(
          viewport.width * (.5 + (.4 - .5) * scale),
          viewport.height / 2,
        );
        await t.tapAt(origin + node);
        await t.pumpAndSettle();
        expect(tapped!.dx, closeTo(.4, .001));
        expect(tapped!.dy, closeTo(.5, .001));
        final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('proof')),
        );
        final image = (await t.runAsync(
          () => boundary.toImage(pixelRatio: 1),
        ))!;
        final bytes = (await t.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        int coloredHeight(double x, {int radius = 22}) {
          var count = 0;
          for (var y = (node.dy - radius).round(); y < node.dy + radius; y++) {
            final i = (y * image.width + x.round()) * 4;
            if (bytes.getUint8(i) < 220 ||
                bytes.getUint8(i + 1) < 220 ||
                bytes.getUint8(i + 2) < 220) {
              count++;
            }
          }
          return count;
        }

        expect(
          coloredHeight(node.dx),
          inInclusiveRange(16, 20),
          reason: 'marker at ${scale}x',
        );
        expect(
          coloredHeight(node.dx + viewport.width * .2 * scale * .4, radius: 5),
          inInclusiveRange(2, 4),
          reason: 'edge at ${scale}x',
        );
        image.dispose();
        await t.dragFrom(origin + node, Offset(20 * scale, 0));
        await t.pumpAndSettle();
        expect(dragged!.dx, closeTo(.4 + 20 / viewport.width, .002));
      }
      // View operations never modify graph source coordinates, GUIDs or metres.
      expect(jsonEncode(draft.toJson()), before);
      await t.tap(find.byKey(const Key('fit-floor-image')));
      await t.pumpAndSettle();
      expect(viewer.transformationController!.value, Matrix4.identity());
      expect(t.takeException(), isNull);
    },
  );
}
