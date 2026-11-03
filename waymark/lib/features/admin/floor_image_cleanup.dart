import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;

import 'floor_plan_asset.dart';

/// Row-major homography on normalized IMAGE coordinates, never physical meters.
class ImageTransform {
  ImageTransform(List<double> values) : m = List.unmodifiable(values) {
    if (m.length != 9 || m.any((v) => !v.isFinite)) {
      throw const FormatException('Phép biến đổi ảnh không hợp lệ.');
    }
  }
  final List<double> m;
  static ImageTransform get identity =>
      ImageTransform([1, 0, 0, 0, 1, 0, 0, 0, 1]);
  ui.Offset map(ui.Offset p) {
    final z = m[6] * p.dx + m[7] * p.dy + m[8];
    if (!z.isFinite || z.abs() < 1e-9) {
      throw const FormatException('Điểm nằm ở phép chiếu suy biến.');
    }
    final r = ui.Offset(
      (m[0] * p.dx + m[1] * p.dy + m[2]) / z,
      (m[3] * p.dx + m[4] * p.dy + m[5]) / z,
    );
    if (!r.dx.isFinite || !r.dy.isFinite) {
      throw const FormatException('Tọa độ sau chỉnh không hữu hạn.');
    }
    return r;
  }

  ImageTransform then(ImageTransform next) => ImageTransform([
    for (var row = 0; row < 3; row++)
      for (var col = 0; col < 3; col++)
        List.generate(
          3,
          (k) => next.m[row * 3 + k] * m[k * 3 + col],
        ).reduce((a, b) => a + b),
  ]);
  ImageTransform inverse() {
    final a = m[0],
        b = m[1],
        c = m[2],
        d = m[3],
        e = m[4],
        f = m[5],
        g = m[6],
        h = m[7],
        i = m[8];
    final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    if (!det.isFinite || det.abs() < 1e-10) {
      throw const FormatException('Không thể đảo phép biến đổi ảnh.');
    }
    return ImageTransform(
      [
        e * i - f * h,
        c * h - b * i,
        b * f - c * e,
        f * g - d * i,
        a * i - c * g,
        c * d - a * f,
        d * h - e * g,
        b * g - a * h,
        a * e - b * d,
      ].map((v) => v / det).toList(),
    );
  }

  static ImageTransform fromQuad(List<ui.Offset> q) {
    if (q.length != 4 || q.any((p) => !inside(p))) {
      throw const FormatException('Cần bốn góc trong ảnh.');
    }
    // Clockwise TL/TR/BR/BL, convex, sufficient area. Bow ties cannot be rectified.
    var area = 0.0;
    for (var n = 0; n < 4; n++) {
      final a = q[n], b = q[(n + 1) % 4], c = q[(n + 2) % 4];
      if ((b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx) <
          .0001) {
        throw const FormatException(
          'Bốn góc phải lồi và theo thứ tự trên trái → trên phải → dưới phải → dưới trái.',
        );
      }
      area += a.dx * b.dy - b.dx * a.dy;
    }
    if (area < .02) throw const FormatException('Vùng crop quá nhỏ.');
    const dest = [
      ui.Offset(0, 0),
      ui.Offset(1, 0),
      ui.Offset(1, 1),
      ui.Offset(0, 1),
    ];
    final rows = <List<double>>[];
    for (var n = 0; n < 4; n++) {
      final x = q[n].dx, y = q[n].dy, u = dest[n].dx, v = dest[n].dy;
      rows.add([x, y, 1, 0, 0, 0, -u * x, -u * y, u]);
      rows.add([0, 0, 0, x, y, 1, -v * x, -v * y, v]);
    }
    for (var c = 0; c < 8; c++) {
      var pivot = c;
      for (var r = c + 1; r < 8; r++) {
        if (rows[r][c].abs() > rows[pivot][c].abs()) pivot = r;
      }
      if (rows[pivot][c].abs() < 1e-10) {
        throw const FormatException('Góc phối cảnh suy biến.');
      }
      final temp = rows[c];
      rows[c] = rows[pivot];
      rows[pivot] = temp;
      final divisor = rows[c][c];
      for (var k = c; k < 9; k++) {
        rows[c][k] /= divisor;
      }
      for (var r = 0; r < 8; r++) {
        if (r == c) continue;
        final factor = rows[r][c];
        for (var k = c; k < 9; k++) {
          rows[r][k] -= factor * rows[c][k];
        }
      }
    }
    return ImageTransform([...rows.map((r) => r[8]), 1]);
  }

  static bool inside(ui.Offset p) =>
      p.dx >= -1e-7 &&
      p.dx <= 1.0000001 &&
      p.dy >= -1e-7 &&
      p.dy <= 1.0000001 &&
      p.dx.isFinite &&
      p.dy.isFinite;
}

class ImageCleanupSettings {
  ImageCleanupSettings({
    List<ui.Offset>? corners,
    this.quarterTurns = 0,
    this.degrees = 0,
    this.brightness = 0,
    this.contrast = 1,
    this.grayscale = false,
  }) : corners = List.unmodifiable(
         corners ??
             const [
               ui.Offset(0, 0),
               ui.Offset(1, 0),
               ui.Offset(1, 1),
               ui.Offset(0, 1),
             ],
       );
  final List<ui.Offset> corners;
  final int quarterTurns;
  final double degrees, brightness, contrast;
  final bool grayscale;
  ImageCleanupSettings copyWith({
    List<ui.Offset>? corners,
    int? quarterTurns,
    double? degrees,
    double? brightness,
    double? contrast,
    bool? grayscale,
  }) => ImageCleanupSettings(
    corners: corners ?? this.corners,
    quarterTurns: quarterTurns ?? this.quarterTurns,
    degrees: degrees ?? this.degrees,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    grayscale: grayscale ?? this.grayscale,
  );
  Map<String, dynamic> toJson() => {
    'corners': corners.map((p) => [p.dx, p.dy]).toList(),
    'quarterTurns': quarterTurns,
    'degrees': degrees,
    'brightness': brightness,
    'contrast': contrast,
    'grayscale': grayscale,
  };
  factory ImageCleanupSettings.fromJson(Map<String, dynamic> j) =>
      ImageCleanupSettings(
        corners: (j['corners'] as List)
            .map(
              (p) =>
                  ui.Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
            )
            .toList(),
        quarterTurns: j['quarterTurns'] as int,
        degrees: (j['degrees'] as num).toDouble(),
        brightness: (j['brightness'] as num).toDouble(),
        contrast: (j['contrast'] as num).toDouble(),
        grayscale: j['grayscale'] as bool,
      );
  ({ImageTransform transform, int width, int height}) geometry(int sw, int sh) {
    if (quarterTurns < 0 ||
        quarterTurns > 3 ||
        !degrees.isFinite ||
        degrees.abs() > 15 ||
        !brightness.isFinite ||
        brightness.abs() > .5 ||
        !contrast.isFinite ||
        contrast < .5 ||
        contrast > 2) {
      throw const FormatException('Thông số chỉnh ảnh ngoài giới hạn.');
    }
    final perspective = ImageTransform.fromQuad(corners);
    double length(int a, int b) => ui.Offset(
      (corners[a].dx - corners[b].dx) * sw,
      (corners[a].dy - corners[b].dy) * sh,
    ).distance;
    final w = (length(0, 1) + length(3, 2)) / 2,
        h = (length(0, 3) + length(1, 2)) / 2;
    final angle = (quarterTurns * 90 + degrees) * math.pi / 180,
        c = math.cos(angle),
        s = math.sin(angle);
    final ow = (c.abs() * w + s.abs() * h - 1e-8).ceil(),
        oh = (s.abs() * w + c.abs() * h - 1e-8).ceil();
    if (ow < 16 || oh < 16 || ow > 8192 || oh > 8192 || ow * oh > 12000000) {
      throw const FormatException(
        'Ảnh đầu ra cần 16–8192 px/chiều, tối đa 12 triệu pixel.',
      );
    }
    final rotate = ImageTransform([
      c * w / ow,
      -s * h / ow,
      .5 - (c * w * .5 - s * h * .5) / ow,
      s * w / oh,
      c * h / oh,
      .5 - (s * w * .5 + c * h * .5) / oh,
      0,
      0,
      1,
    ]);
    return (transform: perspective.then(rotate), width: ow, height: oh);
  }
}

class FloorImageEdit {
  FloorImageEdit(
    this.original,
    this.settings,
    this.transform, {
    String? frameId,
  }) : frameId =
           frameId ??
           List.generate(
             16,
             (_) => math.Random.secure().nextInt(256),
           ).map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  final String frameId;
  final FloorPlanAsset original;
  final ImageCleanupSettings settings;
  final ImageTransform transform;
  Map<String, dynamic> toJson() => {
    'version': 1,
    'processedFrameId': frameId,
    'original': {
      'name': original.name,
      'mime': original.mime,
      'dataBase64': base64Encode(original.bytes),
      'width': original.width,
      'height': original.height,
    },
    'settings': settings.toJson(),
    'sourceToProcessed': transform.m,
  };
  static Future<FloorImageEdit> decode(
    Map<String, dynamic> j,
    FloorPlanAsset processed,
  ) async {
    if (j['version'] != 1) {
      throw const FormatException('Phiên bản chỉnh ảnh chưa hỗ trợ.');
    }
    final o = j['original'] as Map<String, dynamic>;
    final original = await FloorPlanAsset.validate(
      base64Decode(o['dataBase64'] as String),
      o['name'] as String,
      o['mime'] as String,
    );
    final settings = ImageCleanupSettings.fromJson(
      j['settings'] as Map<String, dynamic>,
    );
    final geometry = settings.geometry(original.width, original.height);
    final saved = (j['sourceToProcessed'] as List).cast<num>();
    if (original.width != o['width'] ||
        original.height != o['height'] ||
        geometry.width != processed.width ||
        geometry.height != processed.height ||
        saved.length != 9 ||
        List.generate(
          9,
          (i) =>
              !saved[i].isFinite ||
              (saved[i] - geometry.transform.m[i]).abs() > 1e-8,
        ).any((v) => v)) {
      throw const FormatException('Metadata transform không khớp ảnh.');
    }
    final frameId = j['processedFrameId'];
    if (frameId is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(frameId)) {
      throw const FormatException('Thiếu định danh hệ tọa độ ảnh đã xử lý.');
    }
    return FloorImageEdit(
      original,
      settings,
      geometry.transform,
      frameId: frameId,
    );
  }
}

class CleanedFloorImage {
  CleanedFloorImage(this.asset, this.edit);
  final FloorPlanAsset asset;
  final FloorImageEdit edit;
}

/// Actual raster output. Geometry is deterministic; no AI/content inference.
Future<CleanedFloorImage> cleanupFloorImage(
  FloorPlanAsset original,
  ImageCleanupSettings settings,
) async {
  if (original.width * original.height > 12000000) {
    throw const FormatException(
      'Chỉnh ảnh tối đa 12 triệu pixel; hãy giảm kích thước ảnh trước.',
    );
  }
  final geometry = settings.geometry(original.width, original.height);
  final codec = await ui.instantiateImageCodec(original.bytes);
  ui.Image? source, output;
  try {
    source = (await codec.getNextFrame()).image;
    final rgba = (await source.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final pixels = await compute(_warpPixels, {
      'bytes': Uint8List.fromList(
        rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
      ),
      'sw': source.width,
      'sh': source.height,
      'ow': geometry.width,
      'oh': geometry.height,
      'inverse': geometry.transform.inverse().m,
      'brightness': settings.brightness,
      'contrast': settings.contrast,
      'gray': settings.grayscale,
    });
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: geometry.width,
      height: geometry.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final encoder = await descriptor.instantiateCodec();
    try {
      output = (await encoder.getNextFrame()).image;
    } finally {
      encoder.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
    final png = (await output.toByteData(format: ui.ImageByteFormat.png))!;
    final asset = await FloorPlanAsset.validate(
      Uint8List.fromList(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      ),
      'cleaned-floor.png',
      'image/png',
    );
    return CleanedFloorImage(
      asset,
      FloorImageEdit(original, settings, geometry.transform),
    );
  } finally {
    source?.dispose();
    output?.dispose();
    codec.dispose();
  }
}

Uint8List _warpPixels(Map<String, dynamic> j) {
  final src = j['bytes'] as Uint8List,
      sw = j['sw'] as int,
      sh = j['sh'] as int,
      ow = j['ow'] as int,
      oh = j['oh'] as int;
  final m = (j['inverse'] as List).cast<double>(),
      brightness = j['brightness'] as double,
      contrast = j['contrast'] as double,
      gray = j['gray'] as bool;
  final out = Uint8List(ow * oh * 4);
  for (var y = 0; y < oh; y++) {
    for (var x = 0; x < ow; x++) {
      final u = (x + .5) / ow,
          v = (y + .5) / oh,
          z = m[6] * u + m[7] * v + m[8],
          sx = (m[0] * u + m[1] * v + m[2]) / z,
          sy = (m[3] * u + m[4] * v + m[5]) / z;
      final pos = (y * ow + x) * 4;
      out[pos + 3] = 255;
      if (!sx.isFinite ||
          !sy.isFinite ||
          sx < 0 ||
          sy < 0 ||
          sx > 1 ||
          sy > 1) {
        out[pos] = out[pos + 1] = out[pos + 2] = 255;
        continue;
      }
      final fx = (sx * sw - .5).clamp(0.0, sw - 1.0),
          fy = (sy * sh - .5).clamp(0.0, sh - 1.0),
          x0 = fx.floor(),
          y0 = fy.floor(),
          x1 = math.min(x0 + 1, sw - 1),
          y1 = math.min(y0 + 1, sh - 1),
          dx = fx - x0,
          dy = fy - y0;
      final rgb = <double>[];
      for (var c = 0; c < 3; c++) {
        double at(int xx, int yy) {
          final i = (yy * sw + xx) * 4;
          return (src[i + c] + 255 - src[i + 3]).toDouble();
        }

        rgb.add(
          (at(x0, y0) * (1 - dx) + at(x1, y0) * dx) * (1 - dy) +
              (at(x0, y1) * (1 - dx) + at(x1, y1) * dx) * dy,
        );
      }
      if (gray) {
        final g = .2126 * rgb[0] + .7152 * rgb[1] + .0722 * rgb[2];
        rgb.fillRange(0, 3, g);
      }
      for (var c = 0; c < 3; c++) {
        out[pos + c] =
            (((rgb[c] / 255 - .5) * contrast + .5 + brightness).clamp(
                      0.0,
                      1.0,
                    ) *
                    255)
                .round();
      }
    }
  }
  return out;
}

/// Contract only for a later AI adapter. Never auto-applied to the graph.
class UnverifiedMapSuggestion {
  UnverifiedMapSuggestion({
    required this.kind,
    required this.floorWorkspaceId,
    required this.processedFrameId,
    required this.processedImagePoints,
    this.confidence,
  }) {
    if (floorWorkspaceId.isEmpty ||
        processedFrameId.isEmpty ||
        ![
          'Room',
          'Entrance',
          'Corridor',
          'Stairs',
          'Elevator',
        ].contains(kind) ||
        processedImagePoints.isEmpty ||
        processedImagePoints.any((p) => !ImageTransform.inside(p)) ||
        (confidence != null &&
            (!confidence!.isFinite || confidence! < 0 || confidence! > 1))) {
      throw const FormatException('Đề xuất chưa xác minh không hợp lệ.');
    }
  }
  final String kind;
  final String floorWorkspaceId, processedFrameId;
  final List<ui.Offset> processedImagePoints;
  final double? confidence;
  String get status => 'Unverified';
}
