import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:waymark/features/navigation/navigation_page.dart';
import 'package:waymark/features/scanner/scanner_page.dart';
import 'package:waymark/models/route_models.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/waymark_api_service.dart';

import 'fixtures/qr_navigation_fixture.dart';
import 'fixtures/routing_fixture.dart';
import 'scanner_camera_test.dart' show CameraFake;
import 'manual_navigation_test.dart' show singleNodeRoute;

void main() {
  late MobileScannerPlatform previousCamera;
  late CameraFake camera;
  late MockClient client;
  late Map<String, dynamic> location;
  late int status;
  late bool offline;
  late int lookups;
  late int routePosts;
  late int routeStatus;
  late Map<String, dynamic> replacementJson;
  Completer<http.Response>? pendingRoute;
  setUp(() {
    previousCamera = MobileScannerPlatform.instance;
    camera = CameraFake();
    MobileScannerPlatform.instance = camera;
    AuthSession.accessToken = 'qr-navigation-test-token';
    AuthSession.username = 'qr-navigation-test-user';
    location = navigationQrJson(12, 1);
    status = 200;
    offline = false;
    lookups = 0;
    routePosts = 0;
    routeStatus = 200;
    replacementJson = routeJson();
    pendingRoute = null;
    client = MockClient((request) async {
      expect(
        request.headers['Authorization'],
        'Bearer qr-navigation-test-token',
      );
      if (request.method == 'POST') {
        routePosts++;
        expect(request.url.path, '/api/routes');
        expect(jsonDecode(request.body), {
          'startWayMarkCode': location['wayMarkCode'],
          'destinationWayMarkCode': destinationCode,
        });
        return pendingRoute == null
            ? http.Response(jsonEncode(replacementJson), routeStatus)
            : await pendingRoute!.future;
      }
      expect(request.method, 'GET');
      if (request.url.path.endsWith('/graph')) {
        final id = int.parse(
          request.url.pathSegments[request.url.pathSegments.length - 2],
        );
        return http.Response(jsonEncode(floorGraphJson(id)), 200);
      }
      lookups++;
      expect(
        request.url.path,
        '/api/WayMarks/code/${location['wayMarkCode']}/map-location',
      );
      if (offline) throw http.ClientException('offline');
      return http.Response(jsonEncode(location), status);
    });
  });
  tearDown(() async {
    expect(AuthSession.accessToken, 'qr-navigation-test-token');
    expect(AuthSession.username, 'qr-navigation-test-user');
    client.close();
    MobileScannerPlatform.instance = previousCamera;
    AuthSession.clear();
    await camera.captures.close();
  });

  Future<void> open(
    WidgetTester tester, {
    WayMarkRoute? route,
    ValueChanged<WayMarkRoute>? onRouteChanged,
  }) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: NavigationPage(
          route: route ?? WayMarkRoute.fromJson(routeJson()),
          api: WayMarkApiService(client: client),
          onRouteChanged: onRouteChanged,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openScanner(WidgetTester tester) async {
    await tester.tap(find.text('Quét QR xác nhận vị trí'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ScannerPage>(find.byType(ScannerPage)).verifyingNavigation,
      isTrue,
    );
  }

  Future<void> detect(WidgetTester tester) async {
    final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
    await tester.runAsync(() async {
      final callback =
          scanner.onDetect! as Future<void> Function(BarcodeCapture);
      await callback(
        BarcodeCapture(
          barcodes: [Barcode(rawValue: ' ${location['wayMarkCode']} ')],
        ),
      );
    });
    await tester.pumpAndSettle();
  }

  Future<void> scan(WidgetTester tester) async {
    await openScanner(tester);
    await detect(tester);
    expect(find.text('Sử dụng QR này'), findsOneWidget);
    expect(find.text('Chọn điểm đến'), findsNothing);
    await tester.tap(find.text('Sử dụng QR này'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Next QR uses authenticated map-location and updates one step; manual remains usable',
    (tester) async {
      await open(tester);
      await scan(tester);
      expect(find.text('Node đang chọn: Lift'), findsOneWidget);
      expect(
        find.textContaining('Nguồn xác nhận tại bước này: QR SCAN-12'),
        findsOneWidget,
      );
      expect(lookups, 1);
      await tester.tap(find.byKey(const Key('navigation-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('navigation-complete')), findsOneWidget);
      expect(
        find.textContaining('Nguồn xác nhận tại bước này: thủ công'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Tầng của bước hiện tại: Floor two'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Current QR verifies without progress; off-route QR does not change it',
    (tester) async {
      location = navigationQrJson(11, 1);
      await open(tester);
      await scan(tester);
      expect(find.textContaining('tiến độ giữ nguyên.'), findsOneWidget);
      expect(find.text('Node đang chọn: Entrance'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('navigation-progress')),
            )
            .value,
        0,
      );
      location = navigationQrJson(999, 1);
      await scan(tester);
      expect(find.textContaining('không thuộc tuyến'), findsOneWidget);
      expect(routePosts, 0);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(find.text('Node đang chọn: Entrance'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('navigation-progress')),
            )
            .value,
        0,
      );
    },
  );

  testWidgets(
    'Later QR requires confirmation; cancellation preserves state, accepting records gaps',
    (tester) async {
      location = navigationQrJson(13, 2);
      await open(tester);
      await scan(tester);
      expect(find.text('Chuyển tới bước 3?'), findsOneWidget);
      expect(find.text('Node đang chọn: Entrance'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(find.text('Node đang chọn: Entrance'), findsOneWidget);
      await scan(tester);
      await tester.tap(find.text('Xác nhận chuyển bước'));
      await tester.pumpAndSettle();
      expect(find.text('Node đang chọn: Arrival'), findsOneWidget);
      expect(
        find.textContaining('1 bước trung gian chưa được xác nhận'),
        findsOneWidget,
      );
      expect(find.text('Đã chọn điểm cuối tuyến'), findsOneWidget);
      expect(
        find.text('Vòng nét đứt: node đã đối chiếu QR tại thời điểm quét.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Bước trước'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('navigation-confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('(còn bước chưa xác nhận)'), findsOneWidget);
      expect(
        find.textContaining('1 bước trung gian chưa được xác nhận'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('floor-2')))
            .selected,
        isTrue,
      );
    },
  );

  testWidgets('Same node ID on different floor is rejected', (tester) async {
    location = navigationQrJson(12, 2);
    await open(tester);
    await scan(tester);
    expect(find.textContaining('không thuộc tuyến'), findsOneWidget);
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(find.text('Node đang chọn: Entrance'), findsOneWidget);
  });

  for (final outcome in [
    'success',
    '401',
    '404',
    '409',
    '422',
    '503',
    'invalid',
    'wrongFloor',
  ]) {
    testWidgets(
      'Confirmed off-route reroute: $outcome preserves state until valid response',
      (tester) async {
        location = navigationQrJson(999, 1);
        replacementJson['start'] = location;
        final first =
            (replacementJson['nodes'] as List).first as Map<String, dynamic>;
        first['id'] = 999;
        first['name'] = 'New start';
        ((replacementJson['edges'] as List).first
                as Map<String, dynamic>)['fromNodeId'] =
            999;
        if (outcome == 'invalid') replacementJson['nodes'] = [];
        if (outcome == 'wrongFloor') {
          first['floor'] = floorGraphJson(2)['floor'];
          ((replacementJson['edges'] as List).first
                  as Map<String, dynamic>)['fromFloorId'] =
              2;
          ((replacementJson['edges'] as List).first
                  as Map<String, dynamic>)['movement'] =
              'ChangeFloor';
        }
        routeStatus = int.tryParse(outcome) ?? 200;
        await open(tester);
        await tester.tap(find.byKey(const Key('navigation-confirm')));
        await tester.pumpAndSettle();
        await scan(tester);
        expect(routePosts, 0);
        expect(find.text('Node đang chọn: Lift'), findsOneWidget);
        await tester.tap(find.byKey(const Key('confirm-reroute')));
        await tester.pumpAndSettle();
        expect(routePosts, 1);
        if (outcome == 'success') {
          expect(find.text('Node đang chọn: New start'), findsOneWidget);
          expect(find.textContaining('Tiến độ bắt đầu lại'), findsOneWidget);
        } else {
          expect(find.text('Node đang chọn: Lift'), findsOneWidget);
          expect(find.textContaining('cũ giữ nguyên'), findsOneWidget);
        }
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byKey(const Key('navigation-progress')),
              )
              .value,
          outcome == 'success' ? 0 : .5,
        );
      },
    );
  }

  testWidgets(
    'Leaving during reroute ignores late response and retains session',
    (tester) async {
      location = navigationQrJson(999, 1);
      replacementJson['start'] = location;
      (replacementJson['nodes'] as List).first['id'] = 999;
      (replacementJson['edges'] as List).first['fromNodeId'] = 999;
      pendingRoute = Completer<http.Response>();
      var callbacks = 0;
      await open(tester, onRouteChanged: (_) => callbacks++);
      await scan(tester);
      await tester.tap(find.byKey(const Key('confirm-reroute')));
      await tester.pumpAndSettle();
      expect(routePosts, 1);
      expect(find.text('Node đang chọn: Entrance'), findsOneWidget);
      expect(callbacks, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      pendingRoute!.complete(http.Response(jsonEncode(replacementJson), 200));
      await tester.pumpAndSettle();
      expect(callbacks, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Repeated node requires choosing occurrence, then confirming distant jump',
    (tester) async {
      location = navigationQrJson(11, 1);
      await open(tester, route: repeatingNodeRoute());
      await scan(tester);
      expect(find.text('Node xuất hiện nhiều lần trên tuyến'), findsOneWidget);
      expect(find.text('Node đang chọn: Entrance'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('navigation-progress')),
            )
            .value,
        0,
      );
      await scan(tester);
      await tester.tap(find.byKey(const ValueKey('qr-occurrence-2')));
      await tester.pumpAndSettle();
      expect(find.text('Chuyển tới bước 3?'), findsOneWidget);
      await tester.tap(find.text('Xác nhận chuyển bước'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('navigation-complete')), findsOneWidget);
      expect(find.textContaining('QR khớp bước 3:'), findsOneWidget);
    },
  );

  testWidgets('One-node QR verifies the point but does not auto-complete', (
    tester,
  ) async {
    location = navigationQrJson(11, 1);
    await open(tester, route: singleNodeRoute());
    await scan(tester);
    expect(find.byKey(const Key('navigation-complete')), findsNothing);
    expect(
      find.text('Điểm duy nhất đã đối chiếu QR; chưa xác nhận hoàn tất.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('navigation-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('navigation-complete')), findsOneWidget);
  });

  for (final failure in ['401', '404', '503', 'unmapped', 'offline']) {
    testWidgets('Scanner $failure keeps Navigation progress unchanged', (
      tester,
    ) async {
      if (failure == 'unmapped') location['node'] = null;
      if (failure == 'offline') offline = true;
      status = int.tryParse(failure) ?? 200;
      await open(tester);
      await openScanner(tester);
      await detect(tester);
      expect(find.text('Sử dụng QR này'), findsNothing);
      expect(find.text('Quét lại'), findsOneWidget);
      if (failure == '401') {
        expect(find.textContaining('đăng nhập lại'), findsOneWidget);
      }
      if (failure == 'unmapped') {
        expect(find.textContaining('chưa được liên kết'), findsOneWidget);
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Node đang chọn: Entrance'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('navigation-progress')),
            )
            .value,
        0,
      );
      expect(
        find.textContaining('Chưa có QR hợp lệ được chọn'),
        findsOneWidget,
      );
    });
  }

  for (final failure in [
    MobileScannerErrorCode.permissionDenied,
    MobileScannerErrorCode.unsupported,
    MobileScannerErrorCode.genericError,
  ]) {
    testWidgets('Camera $failure cannot change Navigation progress', (
      tester,
    ) async {
      camera.failure = failure;
      await open(tester);
      await openScanner(tester);
      expect(find.text('Mã lỗi camera: ${failure.name}'), findsOneWidget);
      expect(lookups, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Node đang chọn: Entrance'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('navigation-progress')),
            )
            .value,
        0,
      );
    });
  }
}
