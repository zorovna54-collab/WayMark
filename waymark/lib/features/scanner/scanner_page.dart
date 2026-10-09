import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_colors.dart';
import '../../services/waymark_api_service.dart';
import '../route/route_preview_page.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final MobileScannerController _cameraController = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  bool _lookupStarted = false;
  bool _isLoading = false;
  WayMark? _wayMark;
  String? _scannedCode;
  String? _message;
  bool _notFound = false;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_lookupStarted) return;
    final code = capture.barcodes
        .map((barcode) => barcode.rawValue?.trim())
        .whereType<String>()
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (code.isEmpty) return;

    _lookupStarted = true;
    setState(() {
      _isLoading = true;
      _scannedCode = code;
      _message = null;
      _notFound = false;
    });
    await _cameraController.stop();

    try {
      final wayMark = await WayMarkApiService().getWayMarkByCode(code);
      if (!mounted) return;
      setState(() {
        _wayMark = wayMark;
        _notFound = wayMark == null;
        _message = wayMark == null ? 'Không tìm thấy WayMark' : null;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message =
            'Không thể tra cứu WayMark. Vui lòng kiểm tra kết nối và thử lại.\n$error';
        _isLoading = false;
      });
    }
  }

  Future<void> _scanAgain() async {
    setState(() {
      _lookupStarted = false;
      _isLoading = false;
      _wayMark = null;
      _scannedCode = null;
      _message = null;
      _notFound = false;
    });
    try {
      await _cameraController.start();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message =
            'Không thể mở camera. Hãy kiểm tra quyền camera trong Cài đặt Android.\n$error';
      });
    }
  }

  void _openRoutePreview() {
    final wayMark = _wayMark;
    if (wayMark == null) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RoutePreviewPage(
          destination: wayMark.name,
          location: wayMark.location,
          wayMarkCode: wayMark.wayMarkCode,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasResult = _wayMark != null || _message != null;
    return Scaffold(
      backgroundColor: hasResult ? AppColors.background : Colors.black,
      body: hasResult || _isLoading ? _buildResult() : _buildScanner(),
    );
  }

  Widget _buildScanner() {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _cameraController,
          onDetect: _onDetect,
          errorBuilder: (context, error) => ColoredBox(
            color: const Color(0xFF0F172A),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.no_photography_outlined,
                      color: Colors.white,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Camera không khả dụng. Hãy cấp quyền Camera cho WayMark trong Cài đặt Android rồi thử lại.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _scanAgain,
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.24)),
        ),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _circleButton(Icons.close, () => Navigator.pop(context)),
                    const Text(
                      'Quét WayMark',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 44),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.accent,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(40),
                            ),
                          ),
                          Positioned.fill(
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.accent.withValues(
                                    alpha: 0.25,
                                  ),
                                  width: 4,
                                ),
                                borderRadius: BorderRadius.circular(44),
                              ),
                            ),
                          ),
                          Align(
                            child: Container(
                              height: 2,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.qr_code_2, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Hướng camera vào mã QR WayMark',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_isLoading)
          ColoredBox(
            color: Colors.black45,
            child: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 14),
                      Text('Đang tìm ${_scannedCode ?? 'WayMark'}...'),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildResult() {
    final wayMark = _wayMark;
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      wayMark == null
                          ? (_notFound
                                ? Icons.location_off_outlined
                                : Icons.error_outline)
                          : Icons.check_circle_outline,
                      size: 64,
                      color: wayMark == null
                          ? Colors.redAccent
                          : AppColors.accent,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _isLoading
                          ? 'Đang tra cứu WayMark...'
                          : wayMark != null
                          ? 'Quét thành công!'
                          : _notFound
                          ? 'Không tìm thấy WayMark'
                          : 'Không thể tra cứu WayMark',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    if (wayMark != null) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Bạn đang ở vị trí:',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 42,
                              color: AppColors.primary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              wayMark.name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              wayMark.location,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'WayMark ID: ${wayMark.wayMarkCode}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (_message != null) ...[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      if (_scannedCode != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Mã đã quét: $_scannedCode',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            decoration: const BoxDecoration(
              color: AppColors.card,
              border: Border(top: BorderSide(color: AppColors.border)),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                if (wayMark != null)
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _openRoutePreview,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: const Text('Xem đường đi'),
                    ),
                  ),
                if (wayMark != null) const SizedBox(height: 8),
                TextButton(
                  onPressed: _scanAgain,
                  child: const Text(
                    'Quét lại',
                    style: TextStyle(color: AppColors.accent),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onPressed) {
    return Material(
      color: Colors.black.withValues(alpha: 0.25),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white, size: 23),
        ),
      ),
    );
  }
}
