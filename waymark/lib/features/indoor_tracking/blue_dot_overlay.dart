import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../route/map_paint_scale.dart';
import 'indoor_position.dart';
import 'indoor_tracking_controller.dart';

Offset? blueDotScenePoint(IndoorPosition? p, String floorKey, Size size) {
  if (p == null ||
      p.floorKey != floorKey ||
      p.point == null ||
      p.kind == PositionKind.unknown ||
      size.isEmpty) {
    return null;
  }
  return Offset(p.point!.dx * size.width, p.point!.dy * size.height);
}

class BlueDotOverlay extends StatelessWidget {
  const BlueDotOverlay({
    super.key,
    required this.controller,
    required this.floorKey,
    required this.viewScale,
  });
  final IndoorTrackingController controller;
  final String floorKey;
  final double viewScale;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            key: const Key('live-blue-dot-layer'),
            painter: BlueDotPainter(controller, floorKey, viewScale),
          ),
        ),
        ValueListenableBuilder<IndoorPosition?>(
          valueListenable: controller.position,
          builder: (_, p, child) => p != null && p.floorKey != floorKey
              ? const Align(
                  alignment: Alignment.bottomCenter,
                  child: ColoredBox(
                    color: Color(0xeeffffff),
                    child: Text(
                      'Vị trí ở tầng khác — đổi sơ đồ tầng.',
                      key: Key('live-floor-mismatch'),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    ),
  );
}

class BlueDotPainter extends CustomPainter {
  BlueDotPainter(this.controller, this.floorKey, this.viewScale)
    : super(repaint: controller.position);
  final IndoorTrackingController controller;
  final String floorKey;
  final double viewScale;
  @override
  void paint(Canvas canvas, Size scene) {
    final p = controller.position.value;
    final size = beginScreenSizedMapPaint(canvas, scene, viewScale);
    final point = blueDotScenePoint(p, floorKey, size);
    if (point != null) {
      // Numbered exits are graph choices, not a claim that the person took
      // the recommended route. They share the exact image scene transform.
      if (p!.kind == PositionKind.nodeAnchor) {
        final choices = controller.candidates
            .where((e) => controller.graph.nodes[e.to]!.floorKey == floorKey)
            .toList();
        for (var i = 0; i < choices.length; i++) {
          final target = controller.graph.nodes[choices[i].to]!.point;
          final end = Offset(target.dx * size.width, target.dy * size.height);
          canvas.drawLine(
            point,
            end,
            Paint()
              ..color = Colors.indigo.withValues(alpha: .45)
              ..strokeWidth = 2,
          );
          final labelPoint = point + (end - point) * .55;
          final text = TextPainter(
            text: TextSpan(
              text: '${i + 1}',
              style: const TextStyle(
                color: Colors.indigo,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          text.paint(canvas, labelPoint);
        }
      }
      final uncertain = p.confidence == PositionConfidence.uncertain;
      final color = uncertain ? Colors.orange : Colors.blue;
      canvas.drawCircle(
        point,
        18,
        Paint()..color = color.withValues(alpha: .18),
      );
      canvas.drawCircle(point, 8, Paint()..color = color);
      canvas.drawCircle(
        point,
        8,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      if (!uncertain &&
          controller.showTravelArrow &&
          p.travelDirection != null) {
        final a = p.travelDirection!;
        final tip = point + Offset(math.cos(a), math.sin(a)) * 25;
        canvas.drawLine(
          point,
          tip,
          Paint()
            ..color = color
            ..strokeWidth = 3,
        );
        canvas.drawCircle(tip, 3, Paint()..color = color);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BlueDotPainter old) =>
      old.controller != controller ||
      old.floorKey != floorKey ||
      old.viewScale != viewScale;
}
