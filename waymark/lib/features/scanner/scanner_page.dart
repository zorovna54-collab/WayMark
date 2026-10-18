import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_colors.dart';
import '../../services/waymark_api_service.dart';
import '../../models/route_models.dart';
import '../search/search_page.dart';

/// WayMarkCode has no narrower format constraint in the API model.
/// Keep its server contract: a trimmed, non-empty value of at most 100
/// characters, excluding control characters that cannot be useful as a code.
String? normalizeWayMarkQrCode(String? rawValue) {
  final code = rawValue?.trim();
  if (code == null ||
      code.isEmpty ||
      code.length > 100 ||
      RegExp(r'[\x00-\x1F\x7F]').hasMatch(code)) {
    return null;
  }
  return code;
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key, this.api, this.selectStartOnly = false});
  final WayMarkApiService? api;
  final bool selectStartOnly;

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  final MobileScannerController _cameraController = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  bool _lookupStarted = false;
  bool _isLoading = false;
  bool _cameraStarting = true;
  late final WayMarkApiService _api = widget.api ?? WayMarkApiService();
  WayMarkMapLocation? _wayMark;
  String? _scannedCode;
  String? _message;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cameraController.addListener(_onCameraStateChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_stopCameraForLifecycle());
      case AppLifecycleState.resumed:
        if (!_lookupStarted) unawaited(_startCameraIfNeeded());
    }
  }

  Future<void> _stopCameraForLifecycle() async {
    try {
      if (_cameraController.value.isRunning) {
        await _cameraController.stop();
      }
    } on Exception {
      // The platform may already have stopped the camera while backgrounding.
    }
  }

  Future<void> _startCameraIfNeeded() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        _lookupStarted ||
        _cameraController.value.isRunning ||
        _cameraController.value.isStarting) {
      return;
    }
    try {
      await _cameraController.start();
    } on Exception {
      // MobileScanner exposes startup failures through its error builder.
    }
  }

  void _onCameraStateChanged() {
    if (!mounted) return;
    final cameraState = _cameraController.value;
    final isStarting =
        cameraState.isStarting ||
        (!cameraState.isInitialized && cameraState.error == null);
    if (_cameraStarting != isStarting) {
      setState(() => _cameraStarting = isStarting);
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_lookupStarted || !mounted) return;
    final rawValue = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
    if (rawValue.isEmpty) return;

    _lookupStarted = true;
    setState(() {
      _isLoading = true;
      _scannedCode = rawValue.trim();
      _message = null;
      _notFound = false;
    });

    try {
      await _stopCameraForLifecycle();
      final code = normalizeWayMarkQrCode(rawValue);
      if (code == null) {
        if (!mounted) return;
        setState(() {
          _message =
              'QR không chứa mã WayMark hợp lệ. Mã phải có từ 1 đến 100 ký tự.';
          _isLoading = false;
        });
        return;
      }

      final wayMark = await _api.getMapLocation(code);
      if (wayMark.node == null) {
        throw const WayMarkApiException(
          'WayMark này chưa được liên kết với node bản đồ. Hãy quét QR tại vị trí khác.',
          statusCode: 409,
        );
      }
      if (!mounted) return;
      setState(() {
        _wayMark = wayMark;
        _notFound = false;
        _message = null;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _notFound = error is WayMarkApiException && error.statusCode == 404;
        _message = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _scanAgain() async {
    if (!mounted) return;
    setState(() {
      _lookupStarted = false;
      _isLoading = false;
      _cameraStarting = true;
      _wayMark = null;
      _scannedCode = null;
      _message = null;
      _notFound = false;
    });
    try {
      // The MobileScanner widget auto-starts when it is inserted again.
      // If it stayed mounted after a camera error, restart it after the frame.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          _cameraController.value.isRunning ||
          _cameraController.value.isStarting) {
        return;
      }
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
    if (widget.selectStartOnly) {
      Navigator.pop(context, wayMark);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SearchPage(start: wayMark, api: _api),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController.removeListener(_onCameraStateChanged);
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasResult = _wayMark != null || _message != null;
    return Scaffold(
      backgroundColor: hasResult ? AppColors.background : Colors.black,
      body: hasResult ? _buildResult() : _buildScanner(),
    );
  }

  Widget _buildScanner() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return ColoredBox(
        color: const Color(0xFF0F172A),
        child: SafeArea(
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
                    'Quét camera chưa được hỗ trợ trên ứng dụng Windows. Hãy mở WayMark bằng Android hoặc trình duyệt Web có quyền camera.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Quay lại'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

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
                    Text(
                      switch (error.errorCode) {
                        MobileScannerErrorCode.permissionDenied => 'Quyền camera đã bị từ chối. Hãy cấp quyền camera cho ứng dụng rồi thử lại.',
                        MobileScannerErrorCode.unsupported =>
                          'Thiết bị hoặc trình duyệt này không hỗ trợ camera.',
                        _ => 'Không thể khởi tạo camera. Hãy kiểm tra quyền camera và thiết bị rồi thử lại.',
                      },
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
                      Flexible(
                        child: Text(
                          'Hướng camera vào mã QR WayMark',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
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
        if (_cameraStarting && !_isLoading)
          const ColoredBox(
            color: Colors.black45,
            child: Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 14),
                      Text('Đang khởi tạo camera...'),
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
                              'Mã WayMark: ${wayMark.wayMarkCode}',
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
                      child: const Text('Chọn điểm đến'),
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
