import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:waymark/features/scanner/scanner_page.dart';
import 'package:waymark/features/search/search_page.dart';
import 'package:waymark/features/route/route_preview_page.dart';
import 'package:waymark/features/navigation/navigation_page.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/waymark_api_service.dart';

import 'fixtures/routing_fixture.dart';

// Camera adapter only: no physical camera or browser permission is exercised.
class TestCamera extends MobileScannerPlatform {
  bool disposed = false;
  @override
  Stream<BarcodeCapture?> get barcodesStream => const Stream.empty();
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async =>
      const MobileScannerViewAttributes(
        cameraDirection: CameraFacing.back,
        currentTorchMode: TorchState.off,
        size: Size(640, 480),
      );
  @override
  Future<void> stop() async {}
  @override
  Future<void> updateScanWindow(Rect? window) async {}
  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  late MobileScannerPlatform original;
  late TestCamera camera;
  setUp(() {
    original = MobileScannerPlatform.instance;
    camera = TestCamera();
    MobileScannerPlatform.instance = camera;
    AuthSession.accessToken = 'widget-test-token';
  });
  tearDown(() {
    MobileScannerPlatform.instance = original;
    AuthSession.clear();
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> screen(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pumpAndSettle();
  }

  Future<void> decode(
    WidgetTester tester,
    String code, {
    bool twice = false,
  }) async {
    final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
    final capture = BarcodeCapture(barcodes: [Barcode(rawValue: code)]);
    await tester.runAsync(() async {
      final detect = scanner.onDetect! as Future<void> Function(BarcodeCapture);
      final pending = detect(capture);
      if (twice) await detect(capture);
      await pending;
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Scanner -> verified start -> Search -> real route preview; no auto Navigation',
    (tester) async {
      var lookups = 0;
      var routes = 0;
      final client = MockClient((r) async {
        expect(r.headers['Authorization'], 'Bearer widget-test-token');
        if (r.url.path.endsWith('/graph')) {
          return http.Response(jsonEncode(floorGraphJson(1)), 200);
        }
        if (r.url.path.endsWith('/map-location')) {
          lookups++;
          return http.Response(jsonEncode(mapLocationJson()), 200);
        }
        if (r.url.path.endsWith('/WayMarks')) {
          return http.Response(jsonEncode([pointJson(destination: true)]), 200);
        }
        expect(r.url.path, '/api/routes');
        expect(jsonDecode(r.body), {
          'startWayMarkCode': startCode,
          'destinationWayMarkCode': destinationCode,
        });
        expect(r.url.queryParameters['accessibleOnly'], 'true');
        routes++;
        return http.Response(jsonEncode(routeJson(accessibleOnly: true)), 200);
      });
      addTearDown(client.close);
      await screen(tester, ScannerPage(api: WayMarkApiService(client: client)));
      await decode(tester, ' $startCode ', twice: true);
      expect(lookups, 1);
      expect(find.text('Demo entrance'), findsOneWidget);
      await tester.tap(find.text('Chọn điểm đến'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchPage), findsOneWidget);
      expect(find.text('Từ: Demo entrance'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Demo destination'));
      await tester.pumpAndSettle();
      expect(find.byType(RoutePreviewPage), findsOneWidget);
      expect(find.text('40 m'), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('route-instructions')),
        const Offset(0, -450),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Thang máy • 15.25 m → Floor two'),
        160,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('route-instructions')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.textContaining('Thang máy • 15.25 m → Floor two'),
        findsOneWidget,
      );
      expect(routes, 1);
      await tester.pump(const Duration(seconds: 10));
      expect(find.byType(NavigationPage), findsNothing);
      expect(find.text('Đã đến nơi!'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(camera.disposed, isTrue);
    },
  );

  for (final status in [401, 404, 409]) {
    testWidgets('Scanner lookup HTTP $status never forwards to Search', (
      tester,
    ) async {
      final client = MockClient((r) async => http.Response('{}', status));
      addTearDown(client.close);
      await screen(tester, ScannerPage(api: WayMarkApiService(client: client)));
      await decode(tester, startCode);
      expect(find.text('Chọn điểm đến'), findsNothing);
      expect(find.text('Quét lại'), findsOneWidget);
      expect(find.byType(SearchPage), findsNothing);
    });
  }

  testWidgets('Unmapped QR is not accepted; retry can scan a mapped QR', (
    tester,
  ) async {
    var mapped = false;
    final client = MockClient(
      (r) async =>
          http.Response(jsonEncode(mapLocationJson(mapped: mapped)), 200),
    );
    addTearDown(client.close);
    await screen(tester, ScannerPage(api: WayMarkApiService(client: client)));
    await decode(tester, startCode);
    expect(find.textContaining('chưa được liên kết'), findsOneWidget);
    expect(find.text('Chọn điểm đến'), findsNothing);
    mapped = true;
    await tester.tap(find.text('Quét lại'));
    await tester.pumpAndSettle();
    await decode(tester, startCode);
    expect(find.text('Chọn điểm đến'), findsOneWidget);
  });

  testWidgets('Invalid QR is rejected without HTTP', (tester) async {
    final client = MockClient((r) async => fail('No HTTP for invalid QR'));
    addTearDown(client.close);
    await screen(tester, ScannerPage(api: WayMarkApiService(client: client)));
    await decode(tester, 'bad\u0001code');
    expect(find.textContaining('QR không chứa'), findsOneWidget);
    expect(find.text('Chọn điểm đến'), findsNothing);
  });

  testWidgets(
    'Search entered without start scans QR and resumes chosen destination',
    (tester) async {
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/graph')) {
          return http.Response(jsonEncode(floorGraphJson(1)), 200);
        }
        if (r.url.path.endsWith('/WayMarks')) {
          return http.Response(jsonEncode([pointJson(destination: true)]), 200);
        }
        if (r.url.path.endsWith('/map-location')) {
          return http.Response(jsonEncode(mapLocationJson()), 200);
        }
        return http.Response(jsonEncode(routeJson()), 200);
      });
      addTearDown(client.close);
      await screen(tester, SearchPage(api: WayMarkApiService(client: client)));
      await tester.tap(find.text('Demo destination'));
      await tester.pumpAndSettle();
      expect(find.byType(ScannerPage), findsOneWidget);
      await decode(tester, startCode);
      await tester.tap(find.text('Chọn điểm đến'));
      await tester.pumpAndSettle();
      expect(find.byType(RoutePreviewPage), findsOneWidget);
      expect(find.text('40 m'), findsOneWidget);
    },
  );

  for (final status in [401, 422, 503]) {
    testWidgets('Preview HTTP $status shows error and no fabricated route', (
      tester,
    ) async {
      final client = MockClient((r) async => http.Response('{}', status));
      addTearDown(client.close);
      await screen(
        tester,
        RoutePreviewPage(
          startWayMarkCode: startCode,
          destinationWayMarkCode: destinationCode,
          api: WayMarkApiService(client: client),
        ),
      );
      expect(find.byKey(const Key('route-distance')), findsNothing);
      expect(
        find.text(status == 401 ? 'Đăng nhập lại' : 'Thử lại'),
        findsOneWidget,
      );
      if (status == 422) {
        expect(find.textContaining('Không có tuyến đường'), findsOneWidget);
      }
    });
  }

  testWidgets('Preview loading, failed connection and retry', (tester) async {
    final pending = Completer<http.Response>();
    var count = 0;
    final client = MockClient((r) {
      if (r.url.path.endsWith('/graph')) {
        return Future.value(http.Response(jsonEncode(floorGraphJson(1)), 200));
      }
      count++;
      return count == 1
          ? pending.future
          : Future.value(http.Response(jsonEncode(routeJson()), 200));
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: RoutePreviewPage(
          startWayMarkCode: startCode,
          destinationWayMarkCode: destinationCode,
          api: WayMarkApiService(client: client),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Đang tìm tuyến đường...'), findsOneWidget);
    pending.completeError(http.ClientException('offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Không thể kết nối'), findsOneWidget);
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('40 m'), findsOneWidget);
    expect(count, 2);
  });

  testWidgets('Native Windows retains unsupported scanner message', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await screen(tester, const ScannerPage());
    expect(find.byType(MobileScanner), findsNothing);
    expect(find.textContaining('ứng dụng Windows'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  }, skip: kIsWeb);

  testWidgets('Web on Windows uses mobile_scanner instead of native fallback', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await screen(tester, const ScannerPage());
    expect(find.byType(MobileScanner), findsOneWidget);
    expect(find.textContaining('ứng dụng Windows'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  }, skip: !kIsWeb);
}
