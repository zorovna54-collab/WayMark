import 'dart:ui';

/// Transform centers with the image, but draw annotations in screen logical
/// pixels. Caller restores the canvas after painting. Never mutates graph data.
Size beginScreenSizedMapPaint(Canvas canvas, Size scene, double viewScale) {
  final scale = viewScale.isFinite && viewScale > 0 ? viewScale : 1.0;
  canvas.save();
  canvas.scale(1 / scale);
  return scene * scale;
}
