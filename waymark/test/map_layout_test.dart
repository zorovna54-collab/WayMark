import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/navigation/navigation_page.dart';
import 'package:waymark/features/route/route_preview_page.dart';
import 'package:waymark/models/route_models.dart';
import 'package:waymark/services/waymark_api_service.dart';

import 'fixtures/routing_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    expect(
      await rootBundle.loadString('assets/fonts/OFL.txt'),
      contains('SIL OPEN FONT LICENSE'),
    );
    final loader = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  for (final navigation in [false, true]) {
    testWidgets(
      'Map-first layout renders Inter at phone and Web sizes: navigation=$navigation',
      (tester) async {
        final client = MockClient((request) async {
          if (request.method == 'POST') {
            return http.Response(jsonEncode(routeJson()), 200);
          }
          final id = int.parse(
            request.url.pathSegments[request.url.pathSegments.length - 2],
          );
          return http.Response(jsonEncode(floorGraphJson(id)), 200);
        });
        addTearDown(client.close);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        for (final size in [const Size(390, 844), const Size(1200, 800)]) {
          tester.view.physicalSize = size;
          final boundary = GlobalKey();
          final api = WayMarkApiService(client: client);
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                home: navigation
                    ? NavigationPage(
                        route: WayMarkRoute.fromJson(routeJson()),
                        api: api,
                      )
                    : RoutePreviewPage(
                        startWayMarkCode: startCode,
                        destinationWayMarkCode: destinationCode,
                        api: api,
                      ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('floor-route-canvas')), findsOneWidget);
          if (!kIsWeb &&
              const bool.fromEnvironment('WAYMARK_CAPTURE_PREVIEWS')) {
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage()
                      .timeout(const Duration(seconds: 15));
              final bytes = await image
                  .toByteData(format: ui.ImageByteFormat.png)
                  .timeout(const Duration(seconds: 15));
              final directory = Directory('.dart_tool/sprint-previews');
              await directory.create(recursive: true);
              await File(
                '${directory.path}/${navigation ? 'navigation' : 'preview'}-${size.width.toInt()}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          if (!navigation) {
            await tester.tap(find.byTooltip('Mở/thu gọn hướng dẫn'));
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<DraggableScrollableSheet>(
                    find.byType(DraggableScrollableSheet),
                  )
                  .controller!
                  .size,
              greaterThan(.6),
            );
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
      },
    );
  }
}
