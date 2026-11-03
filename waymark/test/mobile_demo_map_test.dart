import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/navigation/navigation_page.dart';
import 'package:waymark/features/route/demo_floor_plan.dart';
import 'package:waymark/features/route/floor_plan_canvas.dart';
import 'package:waymark/features/route/floor_route_geometry.dart';
import 'package:waymark/features/route/floor_route_map.dart';
import 'package:waymark/features/route/route_preview_page.dart';
import 'package:waymark/features/search/search_page.dart';
import 'package:waymark/models/route_models.dart';

import '../tool/mobile_demo_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DemoHospitalMap bundle;
  late MobileDemoData api;
  setUp(() async {
    bundle = DemoHospitalMap.fromJson(
      jsonDecode(
        await rootBundle.loadString('assets/demo_maps/hospital_2a.json'),
      ) as Map<String, dynamic>,
    );
    api = MobileDemoData(bundle);
  });

  test(
    'Only the complete, coordinate-aligned demo graph receives an image',
    () {
      for (final graph in api.graphs.values) {
        expect(bundle.match(graph), isNotNull);
        expect(
          bundle.match(
            FloorMapData(
              floor: graph.floor,
              nodes: graph.nodes
                  .map(
                    (n) => MapNode(
                      id: n.id,
                      floorId: n.floorId,
                      nodeCode: graph.nodes.first.nodeCode,
                      name: n.name,
                      x: graph.nodes.first.x,
                      y: graph.nodes.first.y,
                      nodeType: graph.nodes.first.nodeType,
                    ),
                  )
                  .toList(),
            ),
          ),
          isNull,
        );
        final n = graph.nodes.first;
        final changed = MapNode(
          id: n.id,
          floorId: n.floorId,
          nodeCode: n.nodeCode,
          name: n.name,
          x: n.x + .01,
          y: n.y,
          nodeType: n.nodeType,
        );
        expect(
          bundle.match(
            FloorMapData(
              floor: graph.floor,
              nodes: [changed, ...graph.nodes.skip(1)],
              edges: graph.edges,
            ),
          ),
          isNull,
        );
        expect(
          bundle.match(
            FloorMapData(
              floor: graph.floor,
              nodes: graph.nodes,
              edges: graph.edges.skip(1).toList(),
            ),
          ),
          isNull,
        );
        final e = graph.edges.first;
        expect(
          bundle.match(
            FloorMapData(
              floor: graph.floor,
              nodes: graph.nodes,
              edges: [
                MapGraphEdge(
                  e.fromNodeId,
                  e.toNodeId,
                  e.distanceMeters,
                  e.edgeType,
                  false,
                ),
                ...graph.edges.skip(1),
              ],
            ),
          ),
          isNull,
        );
      }
    },
  );

  test('Room search resolves an actual entrance, never the room centre', () {
    final room = bundle.rooms.single;
    expect(room.matches('001'), isTrue);
    expect(room.matches('tiếp nhận'), isTrue);
    expect(room.matches('204'), isFalse);
    final location = api.location(MobileDemoData.start);
    final graph = api.graphs[location.node!.floorId]!;
    final verified = bundle.verifyRoom(room, location, graph)!;
    expect(verified.nodeId, location.node!.id);
    expect(location.node!.nodeType, 'Entrance');
    expect(location.node!.x, isNot((room.data['label'] as List).first));
    expect(
      bundle.verifyRoom(room, api.location(MobileDemoData.destination), graph),
      isNull,
    );
  });

  test(
    'Ordered 40m demo includes two floors with separate polylines',
    () async {
      final route = await api.findRoute(
        const RouteRequest(
          startWayMarkCode: MobileDemoData.destination,
          destinationWayMarkCode: MobileDemoData.start,
        ),
      );
      expect(route.totalDistanceMeters, 40);
      final entrance = api.location(MobileDemoData.start);
      expect(
        bundle
            .verifyRoom(
              bundle.rooms.single,
              entrance,
              api.graphs[entrance.node!.floorId]!,
            )!
            .matchesRoute(route),
        isTrue,
      );
      expect(route.nodes.last.nodeType, 'Entrance');
      for (final graph in api.graphs.values) {
        expect(bundle.match(graph, route: route), isNotNull);
        final geometry = FloorRouteGeometry.build(route, graph);
        expect(geometry.segments, hasLength(2));
        expect(geometry.transitions, hasLength(1));
        expect(
          geometry.segments.every(
            (s) => s.edge.fromFloorId == s.edge.toFloorId,
          ),
          isTrue,
        );
      }
    },
  );

  test('PNG corridor pixels share the exact graph coordinate system', () async {
    for (final floor in bundle.floors) {
      final bytes = await rootBundle.load(floor['image'] as String);
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 1000);
      expect(frame.image.height, 1000);
      final pixels = (await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      for (final segment in bundle.segments) {
        final localCodes = (floor['nodes'] as List).map((n) => n['code']);
        if (!localCodes.contains(segment['from']) ||
            !localCodes.contains(segment['to'])) {
          continue;
        }
        final a = bundle.node(segment['from'] as String)!,
            b = bundle.node(segment['to'] as String)!;
        // Every 10% must be corridor or lift interior, never a wall/room.
        for (var step = 1; step <= 9; step++) {
          final t = step / 10;
          final x = (((a['x'] as num) * (1 - t) + (b['x'] as num) * t) * 1000)
              .round();
          final y = (((a['y'] as num) * (1 - t) + (b['y'] as num) * t) * 1000)
              .round();
          final offset = (y * 1000 + x) * 4;
          expect(
            [
              pixels.getUint8(offset),
              pixels.getUint8(offset + 1),
              pixels.getUint8(offset + 2),
            ],
            anyOf(equals([224, 242, 239]), equals([237, 233, 254])),
            reason: '${floor['code']} $x,$y must be inside corridor',
          );
        }
      }
      frame.image.dispose();
      codec.dispose();
    }
  });

  testWidgets('Phone map paints image, switches floor, fits and resizes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final route = await api.findRoute(
      const RouteRequest(
        startWayMarkCode: MobileDemoData.destination,
        destinationWayMarkCode: MobileDemoData.start,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FloorRouteMap(route: route, api: api, compact: true),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await DemoHospitalMap.load();
      for (final floor in bundle.floors) {
        await precacheImage(
          AssetImage(floor['image'] as String),
          tester.element(find.byType(FloorRouteMap)),
        );
      }
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('verified-demo-map')), findsOneWidget);
    expect(find.byKey(const Key('floor-plan-image-layer')), findsOneWidget);
    final canvas = tester.widget<FloorPlanCanvas>(find.byType(FloorPlanCanvas));
    expect((canvas.image as AssetImage).assetName, contains('level1.png'));
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    viewer.transformationController!.value = Matrix4.diagonal3Values(2, 2, 1);
    await tester.pump();
    await tester.tap(find.byTooltip('Đặt lại thu phóng'));
    await tester.pumpAndSettle();
    expect(viewer.transformationController!.value, Matrix4.identity());
    await tester.tap(find.text('G'));
    await tester.pumpAndSettle();
    expect(
      (tester.widget<FloorPlanCanvas>(find.byType(FloorPlanCanvas)).image
              as AssetImage)
          .assetName,
      contains('ground.png'),
    );
    tester.view.physicalSize = const Size(600, 844);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('floor-plan-image-layer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Room 001 search keeps WayMark destination through Preview and Navigation',
    (tester) async {
      await tester.runAsync(() => DemoHospitalMap.load());
      await tester.pumpWidget(
        MaterialApp(
          home: SearchPage(
            api: api,
            start: api.location(MobileDemoData.destination),
            initialQuery: '001',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(bundle.rooms.single.name));
      await tester.pumpAndSettle();
      final preview = tester.widget<RoutePreviewPage>(
        find.byType(RoutePreviewPage),
      );
      expect(preview.destinationWayMarkCode, MobileDemoData.start);
      expect(preview.destinationRoom!.room.number, '001');
      await tester.tap(find.text('Bắt đầu dẫn đường'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationPage), findsOneWidget);
      expect(find.byKey(const Key('mobile-next-instruction')), findsOneWidget);
      await tester.pump(const Duration(minutes: 3));
      expect(find.textContaining('Bước 1/6'), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const Key('navigation-confirm')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('mobile-arrival-summary')), findsOneWidget);
      expect(find.text('Đã xác nhận điểm đến'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
