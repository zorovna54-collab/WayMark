import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/route/floor_route_geometry.dart';
import 'package:waymark/features/route/floor_route_map.dart';
import 'package:waymark/models/route_models.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/waymark_api_service.dart';

import 'fixtures/routing_fixture.dart';

void main() {
  tearDown(AuthSession.clear);

  test('Normalized coordinate conversion preserves top-left origin and scales on resize', () {
    expect(normalizedMapPoint(0, 0, const Size(200, 100)), Offset.zero);
    expect(
      normalizedMapPoint(1, 1, const Size(200, 100)),
      const Offset(200, 100),
    );
    expect(
      normalizedMapPoint(0.25, 0.6, const Size(200, 100)),
      const Offset(50, 60),
    );
    expect(
      normalizedMapPoint(0.25, 0.6, const Size(400, 200)),
      const Offset(100, 120),
    );
    for (final x in [-0.1, 1.1, double.nan, double.infinity]) {
      expect(normalizedMapPoint(x, 0.5, const Size(200, 100)), isNull);
      expect(normalizedMapPoint(0.5, x, const Size(200, 100)), isNull);
    }
    expect(normalizedMapPoint(0, 0, Size.zero), isNull);
  });

  test(
    'Ordered polyline uses only same-floor route edges, never graph edges',
    () {
      final route = WayMarkRoute.fromJson(routeJson());
      final geometry = FloorRouteGeometry.build(
        route,
        FloorMapData.fromJson(floorGraphJson(1)),
      );
      expect(geometry.stops.map((s) => s.node.id), [11, 12]);
      expect(geometry.segments.map((s) => s.edge.id), [21]);
      expect(geometry.segments.first.from.routeIndex, 0);
      expect(geometry.segments.first.to.routeIndex, 1);
      expect(geometry.transitions.single.edge.id, 22);
      expect(geometry.transitions.single.departing, isTrue);
      final second = FloorRouteGeometry.build(
        route,
        FloorMapData.fromJson(floorGraphJson(2)),
      );
      expect(second.segments, isEmpty);
      expect(second.transitions.single.at.node.id, 13);
      expect(second.transitions.single.departing, isFalse);
    },
  );

  test('Returning to a floor never connects disjoint visits', () {
    final json = jsonDecode(jsonEncode(routeJson())) as Map<String, dynamic>;
    final nodes = json['nodes'] as List;
    final floorOne = nodes.first['floor'];
    nodes.add({
      'id': 14,
      'nodeCode': 'RETURN',
      'name': 'Return',
      'nodeType': 'Destination',
      'floor': floorOne,
    });
    (json['edges'] as List).add({
      'sequence': 3,
      'id': 23,
      'fromNodeId': 13,
      'toNodeId': 14,
      'fromFloorId': 2,
      'toFloorId': 1,
      'edgeType': 'Elevator',
      'distanceMeters': 5,
      'isAccessible': true,
      'movement': 'ChangeFloor',
    });
    final graph = floorGraphJson(1);
    (graph['nodes'] as List).add({
      'id': 14,
      'floorId': 1,
      'nodeCode': 'RETURN',
      'name': 'Return',
      'x': 0.9,
      'y': 0.1,
      'nodeType': 'Destination',
    });
    final route = WayMarkRoute.fromJson(json);
    final visits = floorVisits(route);
    expect(visits.map((v) => v.floor.id), [1, 2, 1]);
    expect(visits.last.nodeIndices, [3]);
    final geometry = FloorRouteGeometry.build(
      route,
      FloorMapData.fromJson(graph),
    );
    expect(geometry.stops.map((s) => s.routeIndex), [0, 1, 3]);
    expect(geometry.segments.map((s) => s.edge.id), [21]);
    expect(geometry.transitions.map((t) => t.at.routeIndex), [1, 3]);
  });

  test('Same-floor polyline preserves two ordered edges; missing middle never becomes a shortcut', () {
    final json = jsonDecode(jsonEncode(routeJson())) as Map<String, dynamic>;
    final nodes = json['nodes'] as List;
    nodes.last['floor'] = nodes.first['floor'];
    (json['edges'] as List).last['toFloorId'] = 1;
    (json['edges'] as List).last['movement'] = 'SameFloor';
    final route = WayMarkRoute.fromJson(json);
    final graphJson = floorGraphJson(1);
    (graphJson['nodes'] as List).add({
      'id': 13,
      'floorId': 1,
      'nodeCode': 'TEST-2',
      'name': 'Arrival',
      'x': 0.1,
      'y': 0.9,
      'nodeType': 'Destination',
    });
    final complete = FloorRouteGeometry.build(
      route,
      FloorMapData.fromJson(graphJson),
    );
    expect(complete.segments.map((segment) => segment.edge.id), [21, 22]);
    expect(
      complete.segments.map(
        (segment) => [segment.from.node.id, segment.to.node.id],
      ),
      [
        [11, 12],
        [12, 13],
      ],
    );
    (graphJson['nodes'] as List).removeAt(1);
    final incomplete = FloorRouteGeometry.build(
      route,
      FloorMapData.fromJson(graphJson),
    );
    expect(incomplete.stops.map((stop) => stop.node.id), [11, 13]);
    expect(incomplete.segments, isEmpty);
    expect(incomplete.issues, hasLength(1));
  });

  test(
    'Missing node or invalid coordinate skips incident edge without bridging',
    () {
      for (final missing in [true, false]) {
        final json = floorGraphJson(1);
        if (missing) {
          (json['nodes'] as List).removeLast();
        } else {
          (json['nodes'] as List).last['x'] = 1.5;
        }
        final geometry = FloorRouteGeometry.build(
          WayMarkRoute.fromJson(routeJson()),
          FloorMapData.fromJson(json),
        );
        expect(geometry.stops.length, 1);
        expect(geometry.segments, isEmpty);
        expect(geometry.issues.single, contains('Thiếu tọa độ'));
      }
    },
  );

  test('Start = Destination has one marker and zero polyline segments', () {
    final json = routeJson();
    json['destination'] = json['start'];
    json['nodes'] = [(json['nodes'] as List).first];
    json['edges'] = [];
    json['totalDistanceMeters'] = 0;
    final geometry = FloorRouteGeometry.build(
      WayMarkRoute.fromJson(json),
      FloorMapData.fromJson(floorGraphJson(1)),
    );
    expect(geometry.stops.single.routeIndex, 0);
    expect(geometry.segments, isEmpty);
    expect(geometry.transitions, isEmpty);
  });

  test(
    'Floor graph request reuses API URL and JWT; rejects wrong floor metadata',
    () async {
      AuthSession.accessToken = 'test-floor-token';
      final client = MockClient((r) async {
        expect(r.method, 'GET');
        expect(
          r.url.toString(),
          '${WayMarkApiService.baseUrl}/Maps/floors/1/graph',
        );
        expect(r.headers['Authorization'], 'Bearer test-floor-token');
        return http.Response(jsonEncode(floorGraphJson(1)), 200);
      });
      addTearDown(client.close);
      final graph = await WayMarkApiService(client: client).getFloorGraph(1);
      expect(graph.nodes.first.x, 0.2);
      final badClient = MockClient(
        (r) async => http.Response(jsonEncode(floorGraphJson(2)), 200),
      );
      addTearDown(badClient.close);
      await expectLater(
        WayMarkApiService(client: badClient).getFloorGraph(1),
        throwsA(isA<WayMarkApiException>()),
      );
    },
  );

  for (final invalid in ['coordinate', 'duplicate', 'nodeFloor']) {
    test('Reject malformed graph: $invalid', () async {
      final json = floorGraphJson(1);
      if (invalid == 'coordinate') (json['nodes'] as List).first.remove('x');
      if (invalid == 'duplicate') {
        (json['nodes'] as List).add((json['nodes'] as List).first);
      }
      if (invalid == 'nodeFloor') (json['nodes'] as List).first['floorId'] = 2;
      final client = MockClient(
        (r) async => http.Response(jsonEncode(json), 200),
      );
      addTearDown(client.close);
      await expectLater(
        WayMarkApiService(client: client).getFloorGraph(1),
        throwsA(isA<WayMarkApiException>()),
      );
    });
  }

  FloorRoutePainter painter(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(find.byKey(const Key('floor-route-canvas')))
              .painter!
          as FloorRoutePainter;

  testWidgets(
    'Map changes floor, caches reads and resizes for Android/Web widths',
    (tester) async {
      final reads = <int>[];
      final client = MockClient((r) async {
        final id = int.parse(r.url.pathSegments[r.url.pathSegments.length - 2]);
        reads.add(id);
        return http.Response(jsonEncode(floorGraphJson(id)), 200);
      });
      addTearDown(client.close);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 850);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: FloorRouteMap(
                route: WayMarkRoute.fromJson(routeJson()),
                api: WayMarkApiService(client: client),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(painter(tester).geometry.segments.length, 1);
      expect(find.text('Sơ đồ node — chưa có ảnh tầng'), findsOneWidget);
      final smallSize = tester.getSize(
        find.byKey(const Key('floor-route-canvas')),
      );
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value = Matrix4.diagonal3Values(2, 2, 1)
        ..setTranslationRaw(-50, -40, 0);
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('floor-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('floor-2')));
      await tester.pumpAndSettle();
      expect(painter(tester).geometry.segments, isEmpty);
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController!
            .value,
        Matrix4.identity(),
      );
      expect(painter(tester).geometry.transitions.single.departing, isFalse);
      await tester.ensureVisible(find.byKey(const ValueKey('floor-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('floor-1')));
      await tester.pumpAndSettle();
      expect(reads, [1, 2]);
      tester.view.physicalSize = const Size(1100, 850);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('floor-route-canvas'))).width,
        greaterThan(smallSize.width),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Loading, floor read error, retry and missing coordinates are visible',
    (tester) async {
      final pending = Completer<http.Response>();
      var attempts = 0;
      final client = MockClient((r) async {
        attempts++;
        if (attempts == 1) return pending.future;
        final json = floorGraphJson(1);
        json['nodes'] = [];
        return http.Response(jsonEncode(json), 200);
      });
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FloorRouteMap(
                route: WayMarkRoute.fromJson(routeJson()),
                api: WayMarkApiService(client: client),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Đang tải tọa độ tầng...'), findsOneWidget);
      pending.complete(http.Response('{}', 404));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Không tìm thấy thông tin tầng'),
        findsOneWidget,
      );
      await tester.tap(find.text('Tải lại bản đồ'));
      await tester.pumpAndSettle();
      expect(
        find.text('Không có tọa độ tuyến hợp lệ trên tầng này.'),
        findsOneWidget,
      );
      expect(painter(tester).geometry.segments, isEmpty);
    },
  );

  testWidgets('A failed floor read does not block switching to another floor', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/floors/1/graph')) {
        return http.Response('{}', 503);
      }
      return http.Response(jsonEncode(floorGraphJson(2)), 200);
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FloorRouteMap(
              route: WayMarkRoute.fromJson(routeJson()),
              api: WayMarkApiService(client: client),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Không thể hiển thị bản đồ tầng'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('floor-2')));
    await tester.pumpAndSettle();
    expect(painter(tester).geometry.transitions.single.at.node.floor.id, 2);
    expect(find.textContaining('Không thể hiển thị bản đồ tầng'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Empty route shows explicit state and never requests a graph', (
    tester,
  ) async {
    final route = WayMarkRoute.fromJson(routeJson());
    final empty = WayMarkRoute(
      start: route.start,
      destination: route.destination,
      totalDistanceMeters: 0,
      accessibleOnly: false,
      nodes: [],
      edges: [],
    );
    final client = MockClient(
      (r) async => fail('No floor request for an empty route'),
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: FloorRouteMap(
          route: empty,
          api: WayMarkApiService(client: client),
        ),
      ),
    );
    expect(find.textContaining('Tuyến rỗng'), findsOneWidget);
  });
}
