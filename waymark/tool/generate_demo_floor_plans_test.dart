// Explicit asset generator, outside test/: flutter test tool/generate_demo_floor_plans_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Generate synthetic PNGs from the same normalized graph manifest',
    () async {
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))).load();
      final manifest = jsonDecode(
        File('assets/demo_maps/hospital_2a.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final size = manifest['size'] as int;
      for (final floor in manifest['floors'] as List) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(const Color(0xfff8fafc), BlendMode.src);
        void label(
          String text,
          double x,
          double y, {
          double width = 850,
          double font = 28,
        }) {
          final painter = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: font,
                color: const Color(0xff334155),
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: width);
          painter.paint(canvas, Offset(x, y));
        }

        label('DEMO MAP / ${floor['code']}', 45, 35, font: 38);
        label(
          'Sơ đồ tổng hợp • Không phải mặt bằng bệnh viện thật',
          45,
          90,
          font: 24,
        );
        final nodes = {
          for (final n in floor['nodes'] as List) n['code'] as String: n,
        };
        Offset point(dynamic n) => Offset(
          (n['x'] as num).toDouble() * size,
          (n['y'] as num).toDouble() * size,
        );
        final corridor = Paint()
          ..color = const Color(0xffe0f2ef)
          ..strokeWidth = 80
          ..strokeCap = StrokeCap.round;
        final wall = Paint()
          ..color = const Color(0xff94a3b8)
          ..strokeWidth = 5
          ..style = PaintingStyle.stroke;
        for (final edge in manifest['segments'] as List) {
          if (nodes.containsKey(edge['from']) &&
              nodes.containsKey(edge['to'])) {
            canvas.drawLine(
              point(nodes[edge['from']]),
              point(nodes[edge['to']]),
              corridor,
            );
          }
        }
        for (final room in manifest['rooms'] as List) {
          if (room['floor'] != floor['code']) continue;
          final b = room['bounds'] as List;
          final rect = Rect.fromLTRB(
            (b[0] as num) * size.toDouble(),
            (b[1] as num) * size.toDouble(),
            (b[2] as num) * size.toDouble(),
            (b[3] as num) * size.toDouble(),
          );
          final at = point(nodes[room['entrance']]);
          // Recess the lower wall above the horizontal passage; the vestibule
          // ends at the Entrance node, leaving the corridor clear to its right.
          final outline = Path()
            ..moveTo(rect.left, rect.top)
            ..lineTo(rect.right, rect.top)
            ..lineTo(rect.right, rect.bottom - 48)
            ..lineTo(at.dx + 40, rect.bottom - 48)
            ..lineTo(at.dx + 40, rect.bottom)
            ..lineTo(rect.left, rect.bottom)
            ..close();
          canvas.drawPath(outline, Paint()..color = Colors.white);
          canvas.drawPath(outline, wall);
          canvas.drawLine(
            at - const Offset(0, 7),
            at + const Offset(0, 7),
            corridor,
          );
          label(
            'PHÒNG ${room['number']}',
            rect.left + 12,
            rect.top + 55,
            width: rect.width - 24,
            font: 28,
          );
          label(
            'Tiếp nhận\n(Demo)',
            rect.left + 12,
            rect.top + 100,
            width: rect.width - 24,
            font: 24,
          );
        }
        for (final n in nodes.values) {
          final p = point(n);
          if (n['type'] == 'Elevator') {
            final rect = Rect.fromCenter(center: p, width: 130, height: 130);
            canvas.drawRect(rect, Paint()..color = const Color(0xffede9fe));
            canvas.drawRect(rect, wall);
            // Open the lift doorway where this floor's passage reaches it.
            for (final edge in manifest['segments'] as List) {
              final otherCode = edge['from'] == n['code']
                  ? edge['to']
                  : edge['to'] == n['code']
                  ? edge['from']
                  : null;
              if (otherCode == null || !nodes.containsKey(otherCode)) continue;
              final delta = point(nodes[otherCode]) - p;
              final direction = delta / delta.distance;
              canvas.drawLine(p + direction * 60, p + direction * 70, corridor);
            }
            label('LIFT', rect.left + 17, rect.top + 10, width: 110, font: 30);
          } else if ((n['code'] as String).endsWith('ISOLATED')) {
            canvas.drawRect(
              Rect.fromCenter(center: p, width: 130, height: 90),
              wall,
            );
            label('Cô lập', p.dx - 45, p.dy - 20, width: 110, font: 24);
          } else if ((n['code'] as String).endsWith('L1-DEST')) {
            label(
              'Điểm WayMark đích\nChưa có Room mapping',
              600,
              780,
              width: 340,
              font: 26,
            );
          }
        }
        label('X/Y là tọa độ ảnh • Khoảng cách lấy từ API', 45, 945, font: 25);
        final picture = recorder.endRecording();
        final image = await picture.toImage(size, size);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        File(floor['image'] as String).writeAsBytesSync(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        image.dispose();
        picture.dispose();
      }
    },
  );
}
