import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:waymark/features/scanner/scanner_page.dart';

class CameraFake extends MobileScannerPlatform {
  MobileScannerErrorCode? failure;
  Exception? unexpectedFailure;
  int? cameraCount = 2;
  int stops = 0;
  bool disposed = false;
  final starts = <CameraFacing>[];
  final captures = StreamController<BarcodeCapture?>.broadcast();
  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts.add(options.cameraDirection);
    if (unexpectedFailure != null) throw unexpectedFailure!;
    if (failure != null) throw MobileScannerException(errorCode: failure!);
    return MobileScannerViewAttributes(
      cameraDirection: options.cameraDirection,
      currentTorchMode: TorchState.off,
      size: const Size(640, 480),
      numberOfCameras: cameraCount,
    );
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> updateScanWindow(Rect? window) async {}
  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  late MobileScannerPlatform original;
  late CameraFake camera;
  setUp(() {
    original = MobileScannerPlatform.instance;
    camera = CameraFake();
    MobileScannerPlatform.instance = camera;
  });
  tearDown(() async {
    MobileScannerPlatform.instance = original;
    await camera.captures.close();
  });

  Future<void> open(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(const MaterialApp(home: ScannerPage()));
    await tester.pumpAndSettle();
  }

  for (final error in [
    MobileScannerErrorCode.permissionDenied,
    MobileScannerErrorCode.unsupported,
    MobileScannerErrorCode.genericError,
  ]) {
    testWidgets(
      'Startup $error shows readable camera error and retry remains tappable',
      (tester) async {
        camera.failure = error;
        await open(tester);
        expect(find.text('Mã lỗi camera: ${error.name}'), findsOneWidget);
        final text = switch (error) {
          MobileScannerErrorCode.permissionDenied =>
            'Quyền camera đã bị từ chối',
          MobileScannerErrorCode.unsupported => 'Không có camera khả dụng',
          _ => 'Không thể khởi tạo camera',
        };
        expect(find.textContaining(text), findsOneWidget);
        expect(find.text('Đang khởi tạo camera...'), findsNothing);
        expect(find.byTooltip('Chuyển camera trước/sau'), findsNothing);
        camera.failure = null;
        await tester.tap(find.text('Thử lại'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Mã lỗi camera'), findsNothing);
        expect(find.byTooltip('Chuyển camera trước/sau'), findsOneWidget);
        expect(camera.starts.length, 2);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(camera.disposed, isTrue);
      },
    );
  }

  testWidgets(
    'Unexpected startup exception allows a fresh controller on retry',
    (tester) async {
      camera.unexpectedFailure = Exception('test startup exception');
      await open(tester);
      expect(find.textContaining('Không thể khởi tạo camera'), findsOneWidget);
      camera.unexpectedFailure = null;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Chuyển camera trước/sau'), findsOneWidget);
      expect(camera.starts.length, 2);
    },
  );

  testWidgets(
    'Back camera by default; switch front/back only with confirmed support',
    (tester) async {
      await open(tester);
      expect(camera.starts, [CameraFacing.back]);
      await tester.tap(find.byTooltip('Chuyển camera trước/sau'));
      await tester.pumpAndSettle();
      expect(camera.starts, [CameraFacing.back, CameraFacing.front]);
      await tester.tap(find.byTooltip('Chuyển camera trước/sau'));
      await tester.pumpAndSettle();
      expect(camera.starts.last, CameraFacing.back);
      expect(camera.stops, 2);
    },
  );

  for (final count in <int?>[1, null]) {
    testWidgets('Camera count $count does not advertise unsupported switch', (
      tester,
    ) async {
      camera.cameraCount = count;
      await open(tester);
      expect(find.byTooltip('Chuyển camera trước/sau'), findsNothing);
    });
  }

  testWidgets('Switch failure has camera-specific error and can retry', (
    tester,
  ) async {
    await open(tester);
    camera.failure = MobileScannerErrorCode.genericError;
    await tester.tap(find.byTooltip('Chuyển camera trước/sau'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Không thể khởi tạo camera'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
  });

  testWidgets(
    'Lifecycle stops camera and resumes once; permission error does not auto-prompt',
    (tester) async {
      await open(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(camera.stops, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(camera.starts.length, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      camera.failure = MobileScannerErrorCode.permissionDenied;
      await open(tester);
      final attempts = camera.starts.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(camera.starts.length, attempts);
    },
  );

  testWidgets(
    'Frame decoding errors are visible once and do not trigger API lookup',
    (tester) async {
      await open(tester);
      camera.captures.addError(
        const MobileScannerBarcodeException('test frame failure'),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Không thể xử lý khung hình QR'),
        findsOneWidget,
      );
      expect(find.text('Chọn điểm đến'), findsNothing);
    },
  );
}
