import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/models/account_profile.dart';
import 'package:waymark/features/admin/create_map_page.dart';
import 'package:waymark/features/admin/my_maps_page.dart';
import 'package:waymark/features/admin/map_project_cloud_page.dart';
import 'package:waymark/features/home/home_page.dart';
import 'package:waymark/features/search/local_map_search_page.dart';
import 'package:waymark/features/route/route_preview_page.dart';
import 'package:waymark/features/navigation/navigation_page.dart';
import 'package:waymark/features/indoor_tracking/live_tracking_panel.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/navigation_history_service.dart';
import 'package:waymark/services/published_map_api_service.dart';

import 'fixtures/published_map_fixture.dart';
import 'floor_image_cleanup_test.dart' show cleanupTestImage;
import 'map_project_cloud_test.dart' show SiteFixtureApi, StartQrFixtureApi;
import 'support/live_tracking_replay.dart';
import 'support/fake_sensor_provider.dart';
import 'live_navigation_ui_test.dart' show closeTracking, unmountLive;

class _NoMaps extends PublishedMapApiService {
  @override
  Future<List<Map<String, dynamic>>> list() async => [];
}

class _NoHistory extends NavigationHistoryService {
  @override
  Future<List<Map<String, dynamic>>> list() async => [];
}

const profile = AccountProfile(
  userName: 'A',
  displayName: 'A',
  email: null,
  emailVerified: false,
  roles: [],
);
void main() {
  setUp(() => AuthSession.establish('fixture', 'A'));
  tearDown(AuthSession.clear);
  for (final name in [
    'Home',
    'MyMaps',
    'Onboarding',
    'Cloud',
    'Search',
    'Preview',
    'Navigation',
    'Live',
  ]) {
    for (final spec in [
      (320.0, 640.0, 240.0),
      (390.0, 844.0, 0.0),
      (640.0, 360.0, 0.0),
    ]) {
      testWidgets('$name ${spec.$1}x${spec.$2}, text2 keyboard${spec.$3}', (
        t,
      ) async {
        t.view.physicalSize = Size(spec.$1, spec.$2);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final fixture = PublishedMapFixture(
          (await t.runAsync(cleanupTestImage))!,
        );
        final session = (await t.runAsync(
          () => fixture.api.loadQr(fixture.payload),
        ))!;
        final map = session.map, target = map.destinationNodes.last;
        final route = map.routeToNode(
          session.startKey,
          target.nodeId,
          target.floorId,
        );
        if (name == 'Navigation') AuthSession.clear(); // explicitly exercise anonymous manual navigation.
        final doc = <String, dynamic>{
          'id': fixture.mapId,
          'name': 'Fixture private map',
          'version': 1,
          'siteId': 1,
          'buildingId': 1,
          'content': fixture.content,
          'canPublish': true,
          'publicationKind': 'PersonalDemo',
        };
        final cloud = StartQrFixtureApi(fixture, doc);
        await cloud.createQr(
          fixture.mapId,
          1,
          fixture.content['floors'][0]['id'],
          fixture.content['floors'][0]['content']['nodes'][0]['id'],
        );
        LiveTrackingReplay? replay;
        if (name == 'Live') {
          final base = (await t.runAsync(LiveTrackingReplay.create))!;
          await t.runAsync(base.close);
          replay = LiveTrackingReplay(
            base.map,
            base.graph,
            FakeSensorProvider(),
          );
        }
        final page = switch (name) {
          'Home' => HomePage(historyService: _NoHistory()),
          'MyMaps' => MyMapsPage(api: _NoMaps()),
          'Onboarding' => const CreateMapPage(profile: profile),
          'Cloud' => MapProjectCloudPage(
            project: fixture.project,
            link: ProjectCloudLink(doc, fixture.project),
            maps: cloud,
            api: SiteFixtureApi(),
          ),
          'Search' => LocalMapSearchPage(
            map: map,
            destinationFloors: session.project.floors,
            initialStart: session.startKey,
          ),
          'Preview' => RoutePreviewPage.localNode(
            map: map,
            startNodeCode: session.startKey,
            destinationNodeId: target.nodeId,
            destinationFloorId: target.floorId,
            destinationName: target.name,
          ),
          'Navigation' => NavigationPage(route: route, localMap: map),
          _ => Scaffold(
            body: SingleChildScrollView(
              child: LiveTrackingPanel(
                controller: replay!.controller,
                onScan: () async {},
                onManual: () async {},
              ),
            ),
          ),
        };
        await t.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(2),
                viewInsets: EdgeInsets.only(bottom: spec.$3),
              ),
              child: child!,
            ),
            home: page,
          ),
        );
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(t.takeException(), isNull);
        if (name == 'Cloud') {
          final publish = find.text('Xuất bản snapshot đã lưu');
          await t.scrollUntilVisible(
            publish,
            120,
            scrollable: find
                .descendant(
                  of: find.byKey(const Key('cloud-content')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await t.ensureVisible(publish);
          await t.pumpAndSettle();
          await t.tap(publish);
          await t.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.ensureVisible(find.text('Hủy'));
          await t.tap(find.text('Hủy'));
          await t.pumpAndSettle();
          expect(cloud.published, 0);
        }
        if (replay != null) {
          await unmountLive(t);
          await closeTracking(t, replay.controller);
        } else {
          await t.pumpWidget(const SizedBox());
        }
      });
    }
  }
}
