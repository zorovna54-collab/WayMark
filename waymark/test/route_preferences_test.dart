import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/navigation/navigation_page.dart';
import 'package:waymark/features/route/route_preview_page.dart';
import 'package:waymark/services/waymark_api_service.dart';

import 'fixtures/routing_fixture.dart';

void main() {
  testWidgets(
    'Preference UI posts restriction and carries it into Navigation',
    (tester) async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          final id = int.parse(
            request.url.pathSegments[request.url.pathSegments.length - 2],
          );
          return http.Response(jsonEncode(floorGraphJson(id)), 200);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        bodies.add(body);
        final json = routeJson();
        json['options'] = body['options'];
        return http.Response(jsonEncode(json), 200);
      });
      addTearDown(client.close);
      for (final size in [const Size(390, 844), const Size(1200, 800)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(size),
            home: RoutePreviewPage(
              startWayMarkCode: startCode,
              destinationWayMarkCode: destinationCode,
              api: WayMarkApiService(client: client),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Tùy chọn tuyến'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(SwitchListTile, 'Tránh cầu thang'),
        );
        await tester.tap(find.text('Tìm tuyến theo tùy chọn'));
        await tester.pumpAndSettle();
        expect((bodies.last['options'] as Map)['avoidStairs'], true);
        await tester.tap(find.text('Bắt đầu dẫn đường'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationPage>(find.byType(NavigationPage))
              .route
              .options
              .avoidStairs,
          true,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'Wheelchair failure displays explicit message without automatic fallback',
    (tester) async {
      var posts = 0;
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(jsonEncode(floorGraphJson(1)), 200);
        }
        posts++;
        if ((jsonDecode(request.body)['options'] as Map?)?['wheelchair'] ==
            true) {
          return http.Response('{"code":"accessibility_not_verified"}', 422);
        }
        return http.Response(jsonEncode(routeJson()), 200);
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
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tùy chọn tuyến'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Chế độ xe lăn'));
      await tester.tap(find.text('Tìm tuyến theo tùy chọn'));
      await tester.pumpAndSettle();
      expect(posts, 2);
      expect(
        find.textContaining('chưa có dữ liệu xác minh cho xe lăn'),
        findsOneWidget,
      );
      expect(find.text('Bắt đầu dẫn đường'), findsNothing);
      await tester.pump(const Duration(minutes: 1));
      expect(posts, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
