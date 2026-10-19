import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/navigation/navigation_page.dart';
import 'package:waymark/features/route/route_preview_page.dart';
import 'package:waymark/features/route/floor_route_map.dart';
import 'package:waymark/models/route_models.dart';
import 'package:waymark/services/waymark_api_service.dart';

import 'fixtures/routing_fixture.dart';
import 'manual_navigation_test.dart' show singleNodeRoute;

void main() {
  late MockClient client;
  late WayMarkApiService api;
  setUp(() {
    client = MockClient((request) async {
      expect(
        request.method,
        'GET',
        reason: 'Navigation reuses the route; no POST again',
      );
      final id = int.parse(
        request.url.pathSegments[request.url.pathSegments.length - 2],
      );
      return http.Response(jsonEncode(floorGraphJson(id)), 200);
    });
    api = WayMarkApiService(client: client);
  });
  tearDown(() => client.close());

  Future<void> open(
    WidgetTester tester,
    WayMarkRoute route, {
    Size size = const Size(430, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: NavigationPage(route: route, api: api),
      ),
    );
    await tester.pumpAndSettle();
  }

  FloorRoutePainter mapPainter(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(find.byKey(const Key('floor-route-canvas')))
              .painter!
          as FloorRoutePainter;

  testWidgets(
    'Explicit next/previous updates cards, progress and selected floor/node',
    (tester) async {
      await open(tester, WayMarkRoute.fromJson(routeJson()));
      expect(find.text('Chặng hiện tại'), findsOneWidget);
      expect(find.text('Chặng tiếp theo'), findsOneWidget);
      expect(find.text('Hành lang • 24.75 m'), findsOneWidget);
      expect(mapPainter(tester).activeNodeIndex, 0);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Bước trước'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('navigation-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Node đang chọn: Lift'), findsOneWidget);
      expect(mapPainter(tester).activeNodeIndex, 1);
      expect(find.text('Đã xác nhận 1/2 chặng (thủ công)'), findsOneWidget);
      expect(find.text('Chuyển tầng: Floor one → Floor two'), findsOneWidget);
      await tester.tap(find.byKey(const Key('navigation-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('navigation-complete')), findsOneWidget);
      expect(mapPainter(tester).activeNodeIndex, 2);
      expect(mapPainter(tester).geometry.stops.single.node.floor.id, 2);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('floor-2')))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<ElevatedButton>(find.byKey(const Key('navigation-confirm')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Bước trước'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('navigation-complete')), findsNothing);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('floor-1')))
            .selected,
        isTrue,
      );
      expect(mapPainter(tester).activeNodeIndex, 1);
    },
  );

  testWidgets('No timer or elapsed time advances navigation', (tester) async {
    await open(tester, WayMarkRoute.fromJson(routeJson()));
    await tester.pump(const Duration(minutes: 5));
    expect(find.text('Đã xác nhận 0/2 chặng (thủ công)'), findsOneWidget);
    expect(find.byKey(const Key('navigation-complete')), findsNothing);
    expect(mapPainter(tester).activeNodeIndex, 0);
    expect(find.byKey(const Key('manual-navigation-notice')), findsOneWidget);
  });

  testWidgets('One-node route waits for manual completion', (tester) async {
    await open(tester, singleNodeRoute());
    expect(find.byKey(const Key('navigation-complete')), findsNothing);
    expect(mapPainter(tester).geometry.stops, hasLength(1));
    expect(mapPainter(tester).geometry.segments, isEmpty);
    await tester.tap(find.text('Xác nhận hoàn tất tại điểm này'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('navigation-complete')), findsOneWidget);
  });

  testWidgets('Empty and incomplete route show errors, not action controls', (
    tester,
  ) async {
    final route = WayMarkRoute.fromJson(routeJson());
    for (final nodes in [<RouteNode>[], route.nodes]) {
      await open(
        tester,
        WayMarkRoute(
          start: route.start,
          destination: route.destination,
          totalDistanceMeters: 0,
          accessibleOnly: false,
          nodes: nodes,
          edges: [],
        ),
      );
      expect(find.byKey(const Key('navigation-error')), findsOneWidget);
      expect(find.byKey(const Key('navigation-confirm')), findsNothing);
      expect(find.byType(FloorRouteMap), findsNothing);
    }
  });

  testWidgets(
    'Manual floor browsing can return to current step without progressing',
    (tester) async {
      await open(tester, WayMarkRoute.fromJson(routeJson()));
      await tester.ensureVisible(find.byKey(const ValueKey('floor-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('floor-2')));
      await tester.pumpAndSettle();
      expect(find.text('Về tầng của bước hiện tại'), findsOneWidget);
      await tester.ensureVisible(find.text('Về tầng của bước hiện tại'));
      await tester.tap(find.text('Về tầng của bước hiện tại'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('floor-1')))
            .selected,
        isTrue,
      );
      expect(find.text('Đã xác nhận 0/2 chặng (thủ công)'), findsOneWidget);
    },
  );

  testWidgets('Responsive at narrow Android and wide Web sizes', (
    tester,
  ) async {
    await open(
      tester,
      WayMarkRoute.fromJson(routeJson()),
      size: const Size(320, 640),
    );
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Đã xác nhận 0/2 chặng (thủ công)'), findsOneWidget);
  });

  testWidgets(
    'Preview starts same route, Finish returns to Preview without recalculation',
    (tester) async {
      var posts = 0;
      final pending = Completer<http.Response>();
      final routingClient = MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          return pending.future;
        }
        final id = int.parse(
          request.url.pathSegments[request.url.pathSegments.length - 2],
        );
        return http.Response(jsonEncode(floorGraphJson(id)), 200);
      });
      addTearDown(routingClient.close);
      await tester.pumpWidget(
        MaterialApp(
          home: RoutePreviewPage(
            startWayMarkCode: startCode,
            destinationWayMarkCode: destinationCode,
            api: WayMarkApiService(client: routingClient),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Bắt đầu dẫn đường'), findsNothing);
      pending.complete(http.Response(jsonEncode(routeJson()), 200));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bắt đầu dẫn đường'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationPage), findsOneWidget);
      expect(find.text('Tổng khoảng cách tuyến: 40 m'), findsOneWidget);
      await tester.tap(find.text('Kết thúc'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationPage), findsNothing);
      expect(find.text('40 m'), findsOneWidget);
      expect(posts, 1);
    },
  );

  testWidgets(
    'Preview disables starting when response lacks required node metadata',
    (tester) async {
      final json = routeJson();
      (json['nodes'] as List).first['name'] = '';
      final invalidClient = MockClient(
        (request) async => http.Response(
          jsonEncode(request.method == 'POST' ? json : floorGraphJson(1)),
          200,
        ),
      );
      addTearDown(invalidClient.close);
      await tester.pumpWidget(
        MaterialApp(
          home: RoutePreviewPage(
            startWayMarkCode: startCode,
            destinationWayMarkCode: destinationCode,
            api: WayMarkApiService(client: invalidClient),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final start = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Bắt đầu dẫn đường'),
      );
      expect(start.onPressed, isNull);
      expect(
        find.text('Tuyến thiếu thông tin điểm hoặc tầng hợp lệ.'),
        findsOneWidget,
      );
      expect(find.byType(NavigationPage), findsNothing);
    },
  );
}
