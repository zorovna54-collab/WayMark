import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:waymark/features/admin/map_project_cloud_page.dart';
import 'package:waymark/features/scanner/scanner_page.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/map_draft_api_service.dart';
import 'package:waymark/services/published_map_api_service.dart';

import 'fixtures/published_map_fixture.dart';
import 'floor_image_cleanup_test.dart' show cleanupTestImage;
import 'scanner_camera_test.dart' show CameraFake;

class PendingPublicRead extends PublishedMapApiService {
  PendingPublicRead({super.client});
  final results = <Completer<PublishedMapSession>>[];
  @override
  Future<PublishedMapSession> loadQr(String payload) {
    final result = Completer<PublishedMapSession>();
    results.add(result);
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(AuthSession.clear);

  testWidgets(
    'Camera burst resolves once; retry and revoked QR retain AuthSession',
    (t) async {
      final original = MobileScannerPlatform.instance, camera = CameraFake();
      var historyPosts = 0;
      final api = PendingPublicRead(
        client: MockClient((r) async {
          if (r.method == 'POST') historyPosts++;
          return http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      MobileScannerPlatform.instance = camera;
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        MobileScannerPlatform.instance = original;
        await camera.captures.close();
      });
      final fixture = PublishedMapFixture(
        (await t.runAsync(cleanupTestImage))!,
      );
      final session = (await t.runAsync(
        () => fixture.api.loadQr(fixture.payload),
      ))!;
      AuthSession.accessToken = 'session-must-survive-public-camera';
      await t.pumpWidget(MaterialApp(home: ScannerPage(publishedApi: api)));
      await t.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        camera.captures.add(
          BarcodeCapture(barcodes: [Barcode(rawValue: fixture.payload)]),
        );
      }
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(api.results, hasLength(1));
      expect(camera.stops, greaterThanOrEqualTo(1));
      api.results.single.complete(session);
      await t.pumpAndSettle();
      await t.runAsync(() => session.map.historySession!.scanned());
      expect(historyPosts, 1);
      expect(find.text('Đã tải snapshot Published'), findsOneWidget);
      await t.tap(find.text('Quét lại'));
      await t.pumpAndSettle();
      camera.captures.add(
        BarcodeCapture(barcodes: [Barcode(rawValue: fixture.payload)]),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(api.results, hasLength(2));
      api.results.last.completeError(
        const MapDraftApiException('QR đã bị thu hồi.', status: 410),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('thu hồi'), findsWidgets);
      expect(find.text('Đã tải snapshot Published'), findsNothing);
      expect(find.text('Chọn điểm đến'), findsNothing);
      expect(AuthSession.accessToken, 'session-must-survive-public-camera');
      expect(
        historyPosts,
        1,
      ); // Revoked retry did not add another successful scan.
      expect(t.takeException(), isNull);
    },
  );

  // Opt-in evidence: render with the same Builder function as production.
  // Public fixture locator only. No JWT or embedded map. Never reads SQL.
  const payload = String.fromEnvironment('WAYMARK_DEMO_PUBLIC_QR');
  if (payload.isNotEmpty) {
    test('Export Builder QR PNG for emulator camera input', () async {
      expect(publicQrToken(payload), isNotNull);
      final bytes = await nodeQrPng(payload);
      final target = File('build/core-verification-evidence/camera-qr.png');
      await target.parent.create(recursive: true);
      await target.writeAsBytes(bytes, flush: true);
      expect(await target.length(), greaterThan(1000));
    });
  }
}
