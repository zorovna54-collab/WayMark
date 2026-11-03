// Test input only, generated under ignored build/. Never an app default map.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/admin/floor_plan_asset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Generate independent custom 900x598 clinic and single-floor directed graph', () async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))).load();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    final walls = Paint()
      ..color = Colors.blueGrey
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    canvas.drawRect(
      const Rect.fromLTWH(30, 200, 840, 130),
      Paint()..color = const Color(0xffe0f2ef),
    );
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(Rect.fromLTWH(50 + i * 280, 40, 230, 160), walls);
      final label = TextPainter(
        text: TextSpan(
          text: ['PHÒNG 101', 'PHÒNG 102', 'TIẾP NHẬN'][i],
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 26,
            color: Colors.black,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(58 + i * 280, 75));
      canvas.drawLine(
        Offset(140 + i * 280, 200),
        Offset(185 + i * 280, 200),
        Paint()
          ..color = const Color(0xffe0f2ef)
          ..strokeWidth = 10,
      );
    }
    final label = TextPainter(
      text: const TextSpan(
        text: 'ẢNH THỬ TỰ TẠO • KHÔNG PHẢI BẢN ĐỒ PRODUCTION',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 23,
          color: Colors.blueGrey,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, const Offset(40, 450));
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(900, 598);
    final bytes = (await rendered.toByteData(format: ui.ImageByteFormat.png))!;
    Directory('build/android-builder-evidence').createSync(recursive: true);
    File('build/android-builder-evidence/custom-clinic.png').writeAsBytesSync(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    final draft = DraftMap.local(
      'Khu vuc thu nghiem',
      'Toa nha rieng',
      'Tang 2',
      'T2',
    );
    draft.image = await FloorPlanAsset.validate(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      'custom-clinic.png',
      'image/png',
    );
    draft.putNode(
      const DraftNode('DOOR-101', 'Cua 101', .18, .334, 'Entrance'),
    );
    draft.putNode(const DraftNode('HALL', 'Hanh lang', .18, .44, 'Junction'));
    draft.putNode(
      const DraftNode('START', 'Diem bat dau', .75, .44, 'Entrance'),
    );
    draft.putNode(
      const DraftNode('ISOLATED', 'Diem co lap', .9, .8, 'Junction'),
    );
    draft.addEdge(const DraftEdge('START', 'HALL', 12, 'Corridor'));
    draft.addEdge(const DraftEdge('HALL', 'DOOR-101', 5.25, 'Door'));
    draft.places.add({
      'id': newDraftGuid(),
      'placeCode': '101',
      'name': 'Phong 101',
      'label': {'x': .06, 'y': .11},
      'polygon': [],
      'entranceNodeIds': [draft.nodeId('DOOR-101')],
      'accessibility': 'Unknown',
    });
    File('build/android-builder-evidence/custom-input-9b2.json')
        .writeAsBytesSync(draft.encode());
    rendered.dispose();
    picture.dispose();
  });
}
