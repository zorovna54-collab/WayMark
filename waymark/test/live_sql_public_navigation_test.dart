import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:waymark/features/admin/map_project_cloud_page.dart'
    show nodeQrPng;
import 'package:waymark/features/navigation/navigation_page.dart';
import 'package:waymark/features/route/route_preview_page.dart';
import 'package:waymark/features/search/local_map_search_page.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/published_map_api_service.dart';

// Explicit opt-in, GET-only live API test. The private evidence file contains
// resource IDs/public QR only, never passwords or bearer tokens. No SQL access.
const _statePath = String.fromEnvironment('WAYMARK_LIVE_SQL_STATE');

// Use Dart's ordinary HTTP transport for this explicit live integration test;
// do not alter any certificate validation, OS policy or production client.
class _OrdinaryHttp extends HttpOverrides {}

class _GuestClient extends http.BaseClient {
  _GuestClient(this.inner, this.port);
  final http.Client inner;
  final int port;
  int requests = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.method != 'GET' ||
        request.url.scheme != 'http' ||
        request.url.host != '127.0.0.1' ||
        request.url.port != port ||
        request.headers.keys.any(
          (key) => key.toLowerCase() == 'authorization',
        )) {
      throw StateError('Live test permits only loopback Guest GET requests');
    }
    requests++;
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}

void main() {
  testWidgets(
    'Live SQL Guest QR -> Search -> Preview -> manual multi-floor Arrival',
    (tester) async {
      final state = jsonDecode(
        File(_statePath).readAsStringSync(),
      ) as Map<String, dynamic>;
      final port = state['port'] as int;
      final qr = (state['demoQr'] ?? state['qr']) as Map<String, dynamic>;
      final project = state['project'] as Map<String, dynamic>;
      final client = _GuestClient(
        IOClient(_OrdinaryHttp().createHttpClient(null)),
        port,
      );
      addTearDown(client.close);
      AuthSession.accessToken = 'preserved-test-session-marker';
      addTearDown(AuthSession.clear);
      final session = await tester.runAsync(
        () => PublishedMapApiService(
          client: client,
          baseUrl: 'http://127.0.0.1:$port/api',
        ).loadQr(qr['payload'] as String),
      );
      expect(session, isNotNull);
      expect(session!.mapId, project['id']);
      expect(session.nodeId, qr['nodeId']);
      expect(session.floorKey, qr['floorKey']);
      await tester.runAsync(() async {
        final png = await nodeQrPng(qr['payload'] as String);
        expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        await File('${File(_statePath).parent.path}/demo-start-qr.png')
            .writeAsBytes(png);
      });
      expect(session.project.floors.length, 2);
      expect(
        session.project.floors.every(
          (f) => f.image != null && f.places.isEmpty,
        ),
        isTrue,
      );
      final destination = session.map.destinationNodes.single;
      final route = session.map.routeToNode(
        session.startKey,
        destination.nodeId,
        destination.floorId,
      );
      expect(route.totalDistanceMeters, 13);
      expect(route.nodes.length, 4);
      expect(route.edges.length, 3);
      expect(route.nodes.map((n) => n.floor.floorCode).toSet(), {'G', 'L1'});
      expect(route.edges.where((edge) => edge.edgeType == 'Stairs').length, 1);
      final page = LocalMapSearchPage(
        map: session.map,
        destinationFloors: session.project.floors,
        initialStart: session.startKey,
      );
      final item = page.searchableNodeDestinations.single;
      expect(item.matches('destination'), isTrue);
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final context = tester.element(find.byType(LocalMapSearchPage));
        for (final floorId
            in route.nodes.map((node) => node.floor.id).toSet()) {
          await precacheImage(session.map.imageFor(floorId)!, context);
        }
      });
      final tile = find.byKey(
        ValueKey(
          'local-node-destination-${destination.floorId}-${destination.nodeId}',
        ),
      );
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.byType(RoutePreviewPage), findsOneWidget);
      await tester.ensureVisible(find.text('Bắt đầu dẫn đường'));
      await tester.tap(find.text('Bắt đầu dẫn đường'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationPage), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      expect(find.byKey(const Key('mobile-arrival-summary')), findsNothing);
      for (var step = 0; step < 3; step++) {
        await tester.ensureVisible(find.byKey(const Key('navigation-confirm')));
        await tester.tap(find.byKey(const Key('navigation-confirm')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('mobile-arrival-summary')), findsOneWidget);
      expect(AuthSession.accessToken, 'preserved-test-session-marker');
      expect(
        client.requests,
        greaterThanOrEqualTo(4),
      ); // QR, snapshot, both actual floor images.
    },
    skip: _statePath.isEmpty,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
