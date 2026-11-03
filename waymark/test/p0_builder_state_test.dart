import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/admin/draft_map_editor.dart';
import 'package:waymark/features/admin/draft_recovery.dart';
import 'package:waymark/features/admin/local_map_project.dart';
import 'package:waymark/features/admin/map_project_cloud_page.dart';
import 'package:waymark/features/navigation/local_map_navigation.dart';
import 'package:waymark/features/route/floor_plan_canvas.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/waymark_api_service.dart';

import 'fixtures/personal_qr_http_fixture.dart';
import 'fixtures/local_navigation_fixture.dart';
import 'floor_image_cleanup_test.dart' show cleanupTestImage;

class MemoryRecovery extends DraftRecovery {
  final data = <String, Uint8List>{};
  @override
  bool get supported => true;
  @override
  Future<void> write(String owner, String project, Uint8List bytes) async {
    data['$owner/$project'] = Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List?> read(String owner, String project) async =>
      data['$owner/$project'];
}

void main() {
  tearDown(AuthSession.clear);
  test('Search destination count is independent of type/Room, deduplicates exact legacy labels, roundtrips v3', () async {
    final d = customNavigationDraft();
    expect(
      d.destinationCount,
      3,
    ); // Three actual legacy rooms, no searchable node.
    final door = d.nodes.singleWhere((n) => n.code == 'DOOR');
    d.putNode(
      DraftNode(
        door.code,
        'Room 101',
        door.x,
        door.y,
        'Entrance',
        searchableAsDestination: true,
      ),
      replace: true,
    );
    expect(
      d.destinationCount,
      3,
    ); // Room 101 at the same entrance is one result.
    expect(d.places, hasLength(3));
    final map = await LocalMapNavigation.fromDraft(d);
    expect(map.destinationNodes, isEmpty);
    expect(map.searchableRooms, hasLength(3));
    expect(map.rooms, hasLength(3)); // Legacy routing is retained.
    final p = LocalMapProject(d);
    final loaded = await LocalMapProject.decode(p.encode());
    expect(loaded.id, p.id);
    expect(loaded.floors.single.destinationCount, 3);
    expect(loaded.floors.single.nodeIds, d.nodeIds);
    d.putNode(
      DraftNode(door.code, 'Room 101', door.x, door.y, 'Entrance'),
      replace: true,
    );
    final hidden = await LocalMapNavigation.fromDraft(d);
    expect(hidden.destinationNodes, isEmpty);
    expect(hidden.searchableRooms, hasLength(3));
    final nodeOnly = DraftMap.local('S', 'B', 'G', 'G');
    nodeOnly.putNode(const DraftNode('D', 'Clinic', .5, .5, 'Destination'));
    expect(nodeOnly.destinationCount, 0);
    nodeOnly.putNode(
      const DraftNode(
        'D',
        'Clinic',
        .5,
        .5,
        'Destination',
        searchableAsDestination: true,
      ),
      replace: true,
    );
    expect(nodeOnly.destinationCount, 1);
    expect(nodeOnly.graphSummary, '1 Node • 0 Edge • 1 điểm đến');
  });
  for (final accept in [false, true]) {
    testWidgets(
      'Android recovery after reopening empty workspace: accept=$accept preserves graph identity and never writes server',
      (t) async {
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        AuthSession.establish('personal-test-user', 'isolated-recovery');
        final h = PersonalQrHttpFixture((await t.runAsync(cleanupTestImage))!);
        final store = MemoryRecovery();
        final scope = DraftRecovery.ownerScope(WayMarkApiService.baseUrl)!;
        await store.write(scope, h.project.id, h.project.encode());
        final empty = (await t.runAsync(
          () => h.api.project(h.copyDocument(), public: false),
        ))!;
        await t.pumpWidget(
          MaterialApp(
            home: DraftMapEditor(
              initialProject: empty,
              initialCloudLink: ProjectCloudLink(h.copyDocument(), empty),
              api: WayMarkApiService(client: h.client),
              recovery: store,
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await t.pumpAndSettle();
        expect(find.text('Có bản chỉnh sửa trên thiết bị'), findsOneWidget);
        await t.tap(
          find.text(accept ? 'Khôi phục chỉnh sửa local' : 'Giữ bản server'),
        );
        await t.pump();
        if (accept) {
          final provider = t
              .widget<FloorPlanCanvas>(find.byType(FloorPlanCanvas))
              .image!;
          await t.runAsync(
            () =>
                precacheImage(provider, t.element(find.byType(DraftMapEditor))),
          );
        }
        await t.pumpAndSettle();
        final editor = t.widget<DraftMapEditor>(find.byType(DraftMapEditor));
        expect(editor.initialProject!.id, h.project.id);
        await t.scrollUntilVisible(
          find.byKey(const Key('draft-graph-summary')),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        expect(
          find.text(
            accept
                ? '3 Node • 2 Edge • 1 điểm đến'
                : '0 Node • 0 Edge • 0 điểm đến',
          ),
          findsOneWidget,
        );
        expect(h.saves, 0);
        expect(h.uploads, 0);
        expect(await store.read('$scope-other-user', h.project.id), isNull);
      },
    );
  }
  test(
    'Unknown signed-in identity cannot fall back to shared guest recovery',
    () {
      AuthSession.accessToken = 'not-a-jwt';
      expect(DraftRecovery.ownerScope('http://api'), isNull);
      AuthSession.clear();
      expect(DraftRecovery.ownerScope('http://api'), 'http://api|local');
    },
  );
}
