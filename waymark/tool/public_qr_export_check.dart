import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:waymark/features/admin/draft_file_gateway.dart';
import 'package:waymark/features/admin/map_project_cloud_page.dart';

// Native Android decoder / document-picker rehearsal; no server writes.
const payload = String.fromEnvironment('WAYMARK_DEMO_PUBLIC_QR');
void main() => runApp(const MaterialApp(home: QrExportCheck()));

class QrExportCheck extends StatefulWidget {
  const QrExportCheck({super.key});
  @override
  State<QrExportCheck> createState() => _QrExportCheckState();
}

class _QrExportCheckState extends State<QrExportCheck> {
  Uint8List? _png;
  String _status = 'Đang tạo PNG và kiểm tra bằng native QR decoder…';
  final _camera = MobileScannerController(autoStart: false);
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final png = await nodeQrPng(payload);
      final file = File(
        '${Directory.systemTemp.path}/waymark-qr-${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(png, flush: true);
      final result = await _camera.analyzeImage(file.path);
      final matches =
          result?.barcodes.any((b) => b.rawValue == payload) == true;
      if (mounted) {
        setState(() {
          _png = png;
          _status = matches
              ? 'PASS • native decoder đọc đúng public QR từ PNG'
              : 'FAIL • native decoder không đọc được đúng payload';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Chưa kiểm chứng decoder: $e');
    }
  }

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('QR PNG • isolated native test')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(_status),
        QrImageView(
          data: payload,
          size: 280,
          backgroundColor: Colors.white,
          padding: const EdgeInsets.all(24),
        ),
        FilledButton(
          onPressed: _png == null
              ? null
              : () async {
                  try {
                    await const PlatformDraftFiles().save(
                      _png!,
                      'waymark-core-qr-${payload.substring(6, 14)}.png',
                      'image/png',
                    );
                    if (mounted) {
                      setState(
                        () =>
                            _status = 'Đã lưu PNG qua Android document picker.',
                      );
                    }
                  } catch (e) {
                    if (mounted) setState(() => _status = e.toString());
                  }
                },
          child: const Text('Lưu QR PNG trên Android'),
        ),
        const Text(
          'Đây là giải mã file PNG, chưa phải camera quét QR vật lý. Dữ liệu API fixture/SQLite cô lập.',
        ),
      ],
    ),
  );
}
