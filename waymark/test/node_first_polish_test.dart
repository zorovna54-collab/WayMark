import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/admin/draft_map_editor.dart';
import 'package:waymark/features/navigation/local_map_navigation.dart';
import 'package:waymark/features/navigation/navigation_page.dart';
import 'package:waymark/features/search/local_map_search_page.dart';

import 'fixtures/local_navigation_fixture.dart';
import 'fixtures/multifloor_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DraftNode target(
    DraftNode n, {
    String title = 'Quầy hướng dẫn',
    String? note,
  }) => DraftNode(
    n.code,
    n.name,
    n.x,
    n.y,
    n.type,
    displayName: title,
    searchableAsDestination: true,
    landmarkNote: note,
  );
  test('Canvas/edge labels agree, metadata is preserved, legacy labels default to hidden', () {
    final d = customNavigationDraft(), old = d.nodes.first;
    final n = target(old);
    d.putNode(n, replace: true);
    final painter = DraftMapPainter(d, n.code);
    expect(painter.nodeLabel(n), n.listLabel(0));
    expect(painter.nodeLabel(d.nodes[1]), 'N02');
    expect(painter.visibleRoomNames, isEmpty);
    expect(
      DraftMapPainter(d, null, showLabels: true).visibleRoomNames,
      hasLength(3),
    );
    expect(n.at(.2, .3).readableName, 'Quầy hướng dẫn');
    expect(n.at(.2, .3).searchableAsDestination, isTrue);
  });
  testWidgets(
    'Search snapshot survives edited/reordered caller floors and can search original name and N badge',
    (t) async {
      final p = threeFloorProject(), d = p.floors[1], n = d.nodes.last;
      d.putNode(target(n), replace: true);
      final map = await LocalMapNavigation.fromProject(p);
      final expected = map.destinationNodes.single;
      d.putNode(
        DraftNode(n.code, 'Changed after snapshot', n.x, n.y, n.type),
        replace: true,
      );
      final page = LocalMapSearchPage(
        map: map,
        destinationFloors: p.floors.reversed.toList(),
      );
      expect(
        page.searchableNodeDestinations.single.displayName,
        'Quầy hướng dẫn',
      );
      expect(page.searchableNodeDestinations.single.selection.floorId, 2);
      expect(
        page.searchableNodeDestinations.single.selection.nodeId,
        expected.nodeId,
      );
      final route = map.routeToNode(
        p.floors[0].nodeId('START'),
        expected.nodeId,
        2,
      );
      expect(route.destination.name, 'Quầy hướng dẫn');
      await t.pumpWidget(MaterialApp(home: page));
      await t.enterText(find.byType(TextField), 'N03');
      await t.pumpAndSettle();
      expect(find.text('Quầy hướng dẫn (DOOR)'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Cửa phòng');
      await t.pumpAndSettle();
      expect(find.text('Quầy hướng dẫn (DOOR)'), findsOneWidget);
    },
  );
  test('Node routes do not show unrelated legacy Room labels; room routes retain their own label', () async {
    final d = customNavigationDraft();
    d.putNode(
      target(d.nodes.singleWhere((n) => n.code == 'DOOR')),
      replace: true,
    );
    final map = await LocalMapNavigation.fromDraft(d),
        node = map.destinationNodes.single;
    expect(
      map.routeRoomLabels(map.routeToNode('S', node.nodeId, 1), 1),
      isEmpty,
    );
    final room = map.rooms.first;
    expect(
      map.routeRoomLabels(map.routeToRoom('S', room.id), 1).single.id,
      room.id,
    );
  });
  testWidgets(
    'Landmarks and next-step instructions identify the correct floor after next/back and arrival',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final p = threeFloorProject();
      for (final (i, d) in p.floors.indexed) {
        final n = d.nodes.singleWhere((n) => n.code == 'STAIR');
        d.putNode(
          DraftNode(
            n.code,
            n.name,
            n.x,
            n.y,
            n.type,
            landmarkNote: 'Mốc chỉ tầng $i',
          ),
          replace: true,
        );
      }
      final end = p.floors.last.nodes.last;
      p.floors.last.putNode(target(end, note: 'Đích tầng II'), replace: true);
      final map = await LocalMapNavigation.fromProject(p),
          dest = map.destinationNodes.single;
      final route = map.routeToNode(
        p.floors.first.nodeId('START'),
        dest.nodeId,
        3,
      );
      await t.pumpWidget(
        MaterialApp(
          home: NavigationPage(route: route, localMap: map),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.byKey(const Key('navigation-route-endpoints')),
        findsOneWidget,
      );
      for (var i = 0; i < route.nodes.length; i++) {
        final node = route.nodes[i],
            note = map.landmarkNoteForNode(node.id, node.floor.id);
        if (note != null) {
          expect(find.text('Mốc nhận biết: $note'), findsOneWidget);
          expect(find.text('Mốc tại: ${node.floor.name}'), findsOneWidget);
        }
        if (i < route.edges.length) {
          final next = route.nodes[i + 1];
          expect(
            t
                .widget<Text>(find.byKey(const Key('mobile-next-instruction')))
                .data,
            contains(next.floor.name),
          );
          await t.tap(find.byKey(const Key('navigation-confirm')));
          await t.pumpAndSettle();
        }
      }
      expect(
        find.byKey(const Key('navigation-next-landmark-note')),
        findsNothing,
      );
      await t.tap(find.text('Bước trước'));
      await t.pumpAndSettle();
      expect(find.text('Mốc nhận biết: Mốc chỉ tầng 2'), findsOneWidget);
      expect(find.text('Mốc kế tiếp tại: Tầng II'), findsOneWidget);
    },
  );
}
