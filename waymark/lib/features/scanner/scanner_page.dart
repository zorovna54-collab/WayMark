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
  const ScannerPage({super.key, this.api, this.selectStartOnly = false})
    : verifyingNavigation = false;
  const ScannerPage.verifyLocation({super.key, this.api})
    : selectStartOnly = true,
      verifyingNavigation = true;
  final WayMarkApiService? api;
  final bool selectStartOnly;
  final bool verifyingNavigation;

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  static MobileScannerController _newController() => MobileScannerController(
    autoStart: false,
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
  );
  MobileScannerController _cameraController = _newController();
  bool _resetControllerOnRetry = false;
  bool _retryingCamera = false;

  bool _lookupStarted = false;
  bool _isLoading = false;
  bool _cameraStarting = true;
  bool _cameraSwitching = false;
  bool _appActive = true;
  bool _frameErrorShown = false;
  String? _cameraOperationError;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          (kIsWeb || defaultTargetPlatform != TargetPlatform.windows)) {
        unawaited(_startCameraIfNeeded());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _appActive = false;
        unawaited(_stopCameraForLifecycle());
      case AppLifecycleState.resumed:
        _appActive = true;
        if (!_lookupStarted &&
            _cameraController.value.hasCameraPermission &&
            _cameraController.value.error == null) {
          unawaited(_startCameraIfNeeded());
        }
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
        !_appActive ||
        _lookupStarted ||
        _cameraController.value.isRunning ||
        _cameraController.value.isStarting) {
      return;
    }
    try {
      await _cameraController.start();
      if (mounted && (!_appActive || _lookupStarted)) {
        await _stopCameraForLifecycle();
      }
    } on Exception {
      // An unexpected plugin exception may leave isStarting set. A fresh owned
      // controller on explicit retry avoids getting stuck in that state.
      _resetControllerOnRetry = _cameraController.value.isStarting;
      if (mounted) {
        setState(() {
          _cameraOperationError = 'Không thể khởi tạo camera. Hãy kiểm tra camera, quyền truy cập và thử lại.';
          _cameraStarting = false;
        });
      }
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
    if (_lookupStarted || !mounted || !_appActive || _cameraSwitching) return;
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
      _cameraOperationError = null;
      _frameErrorShown = false;
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
      if (wayMark.node!.id <= 0 || wayMark.node!.floorId <= 0) {
        throw const WayMarkApiException(
          'Liên kết node hoặc tầng của QR không hợp lệ.',
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
    if (!mounted || _retryingCamera) return;
    _retryingCamera = true;
    try {
      if (_resetControllerOnRetry) {
        final previous = _cameraController;
        previous.removeListener(_onCameraStateChanged);
        await previous.dispose();
        if (!mounted) return;
        _cameraController = _newController();
        _cameraController.addListener(_onCameraStateChanged);
        _resetControllerOnRetry = false;
      }
      setState(() {
        _lookupStarted = false;
        _isLoading = false;
        _cameraStarting = true;
        _wayMark = null;
        _scannedCode = null;
        _message = null;
        _notFound = false;
        _cameraOperationError = null;
        _frameErrorShown = false;
      });
      // Wait for MobileScanner to be attached again before explicitly starting.
      await _startCameraIfNeeded();
    } finally {
      _retryingCamera = false;
    }
  }

  Future<void> _switchCamera() async {
    if (_cameraSwitching ||
        _lookupStarted ||
        !_cameraController.value.isRunning) {
      return;
    }
    setState(() => _cameraSwitching = true);
    try {
      await _cameraController.switchCamera();
      if (mounted && !_appActive) await _stopCameraForLifecycle();
    } on Exception {
      _resetControllerOnRetry = _cameraController.value.isStarting;
      if (mounted) {
        setState(
          () => _cameraOperationError = 'Không thể chuyển camera. Hãy kiểm tra camera trước/sau rồi thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _cameraSwitching = false);
    }
  }

  void _onFrameError(Object error, StackTrace stack) {
    if (!mounted || _lookupStarted || _frameErrorShown) return;
    _frameErrorShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Không thể xử lý khung hình QR. Hãy thử quét lại hoặc đổi camera.',
        ),
      ),
    );
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

    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: _cameraController,
      builder: (context, cameraState, child) {
        final hasCameraError =
            cameraState.error != null || _cameraOperationError != null;
        final canSwitch =
            cameraState.isRunning &&
            (cameraState.availableCameras ?? 0) > 1 &&
            (cameraState.cameraDirection == CameraFacing.back ||
                cameraState.cameraDirection == CameraFacing.front);
        return Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              key: ObjectKey(_cameraController),
              controller: _cameraController,
              onDetect: _onDetect,
              onDetectError: _onFrameError,
              errorBuilder: (context, error) => _cameraErrorView(
                _cameraErrorMessage(error),
                code: error.errorCode.name,
              ),
            ),
            if (_cameraOperationError != null)
              _cameraErrorView(_cameraOperationError!),
            if (!hasCameraError)
              IgnorePointer(
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.24)),
              ),
            if (!hasCameraError)
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _circleButton(
                            Icons.close,
                            () => Navigator.pop(context),
                          ),
                          const Text(
                            'Quét WayMark',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (canSwitch && !_cameraSwitching && !_lookupStarted)
                            Tooltip(
                              message: 'Chuyển camera trước/sau',
                              child: _circleButton(
                                Icons.cameraswitch_outlined,
                                _switchCamera,
                              ),
                            )
                          else
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
                            Icon(
                              Icons.qr_code_2,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Hướng camera vào mã QR WayMark',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
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
            if (_cameraStarting && !_isLoading && !hasCameraError)
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
      },
    );
  }

  String _cameraErrorMessage(MobileScannerException error) =>
      switch (error.errorCode) {
        MobileScannerErrorCode.permissionDenied => 'Quyền camera đã bị từ chối. Hãy cấp quyền camera cho WayMark trong cài đặt ứng dụng Android hoặc quyền trang web trên trình duyệt, rồi thử lại.',
        MobileScannerErrorCode.unsupported => 'Không có camera khả dụng hoặc thiết bị/trình duyệt không hỗ trợ quét. Với Android Emulator, hãy kiểm tra cấu hình camera của AVD.',
        _ => 'Không thể khởi tạo camera. Camera có thể đang được ứng dụng khác sử dụng hoặc cấu hình chưa hợp lệ. Hãy kiểm tra camera rồi thử lại.',
      };

  Widget _cameraErrorView(String message, {String? code}) => ColoredBox(
    color: const Color(0xFF0F172A),
    child: SafeArea(
      child: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 76, 28, 28),
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
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                  if (code != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Mã lỗi camera: $code',
                        style: const TextStyle(color: Colors.white70),
                      ),
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
          Positioned(
            top: 16,
            left: 24,
            child: _circleButton(Icons.close, () => Navigator.pop(context)),
          ),
        ],
      ),
    ),
  );

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
                          ? widget.verifyingNavigation
                                ? 'Đã tra cứu QR'
                                : 'Quét thành công!'
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
                      Text(
                        widget.verifyingNavigation
                            ? 'Điểm liên kết với QR (chưa đối chiếu tuyến):'
                            : 'Bạn đang ở vị trí:',
                        style: const TextStyle(color: AppColors.textSecondary),
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
                      child: Text(
                        widget.verifyingNavigation
                            ? 'Sử dụng QR này'
                            : 'Chọn điểm đến',
                      ),
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
