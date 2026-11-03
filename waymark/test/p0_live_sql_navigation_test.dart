import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:waymark/features/admin/map_project_cloud_page.dart'
    show nodeQrPng;
import 'package:waymark/features/navigation/navigation_page.dart';
import 'package:waymark/features/search/local_map_search_page.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/published_map_api_service.dart';

const _path = String.fromEnvironment('WAYMARK_LIVE_SQL_STATE');

class _NormalHttp extends HttpOverrides {}

class _ReadOnlyGuest extends http.BaseClient {
  _ReadOnlyGuest(this.inner);
  final http.Client inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.method != 'GET' ||
        request.url.host != '127.0.0.1' ||
        request.url.port != 5121 ||
        request.url.scheme != 'http' ||
        request.headers.keys.any((h) => h.toLowerCase() == 'authorization')) {
      throw StateError('Only loopback Guest GET allowed');
    }
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}

void main() {
  testWidgets(
    'P0 real SQL Guest snapshot -> Search -> 12m Preview -> manual Arrival (no camera)',
    (t) async {
      final state = jsonDecode(
        File(_path).readAsStringSync().replaceFirst('\uFEFF', ''),
      ) as Map<String, dynamic>;
      final client = _ReadOnlyGuest(
        IOClient(_NormalHttp().createHttpClient(null)),
      );
      addTearDown(client.close);
      AuthSession.clear();
      final qr = state['qr'] as Map<String, dynamic>;
      final session = (await t.runAsync(
        () => PublishedMapApiService(
          client: client,
          baseUrl: 'http://127.0.0.1:5121/api',
        ).loadQr(qr['payload'] as String),
      ))!;
      expect(session.mapId, state['project']['id']);
      expect(session.nodeId, qr['nodeId']);
      expect(session.project.floors, hasLength(1));
      final floor = session.project.floors.single;
      expect(floor.image, isNotNull);
      expect(floor.nodes, hasLength(3));
      expect(floor.edges, hasLength(2));
      expect(floor.destinationCount, 1);
      final destination = session.map.destinationNodes.single;
      final route = session.map.routeToNode(
        session.startKey,
        destination.nodeId,
        destination.floorId,
      );
      expect(route.totalDistanceMeters, 12);
      expect(route.nodes, hasLength(3));
      expect(route.edges, hasLength(2));
      final evidence = File(_path).parent;
      await t.runAsync(() async {
        await File('${evidence.path}/start-qr.png')
            .writeAsBytes(await nodeQrPng(qr['payload'] as String));
      for (final family in ['Roboto', 'Inter']) {
        await (FontLoader(family)..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))).load();
      }
      await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            home: LocalMapSearchPage(
              map: session.map,
              destinationFloors: session.project.floors,
              initialStart: session.startKey,
            ),
          ),
        ),
      );
      await t.runAsync(
        () => precacheImage(
          session.map.image!,
          t.element(find.byType(LocalMapSearchPage)),
        ),
      );
      await t.pumpAndSettle();
      final target = find.text('P0 Destination (DEST)');
      await t.scrollUntilVisible(
        target,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(target);
      await t.pumpAndSettle();
      expect(find.text('12 m'), findsWidgets);
      await t.tap(find.text('Bắt đầu dẫn đường'));
      await t.pumpAndSettle();
      expect(find.byType(NavigationPage), findsOneWidget);
      await t.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        try {
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          await File('${evidence.path}/live-sql-widget-navigation.png')
              .writeAsBytes(
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              );
        } finally {
          image.dispose();
        }
      });
      for (var i = 0; i < 2; i++) {
        await t.tap(find.byKey(const Key('navigation-confirm')));
        await t.pumpAndSettle();
      }
      expect(find.byKey(const Key('navigation-complete')), findsOneWidget);
      expect(AuthSession.accessToken, isNull);
      expect(t.takeException(), isNull);
    },
    skip: _path.isEmpty,
  );
}
