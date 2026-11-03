import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/admin/local_map_project.dart';
import 'package:waymark/features/admin/draft_map_editor.dart';
import 'package:waymark/features/admin/floor_plan_asset.dart';
import 'package:waymark/features/navigation/local_map_navigation.dart';
import 'package:waymark/features/navigation/navigation_page.dart';
import 'package:waymark/features/route/floor_route_map.dart';
import 'package:waymark/features/search/local_map_search_page.dart';

import 'fixtures/multifloor_fixture.dart';
import 'draft_floor_workflow_test.dart' show MemoryDraftFiles;

Future<void> attachFloorImages(LocalMapProject p) async {
  for (final (i, f) in p.floors.indexed) {
    final r = ui.PictureRecorder();
    // Independent image for every floor, never a production floor plan.
    final canvas = Canvas(r)
      ..drawColor(
        [
          Colors.blue.shade100,
          Colors.green.shade100,
          Colors.orange.shade100,
        ][i],
        BlendMode.src,
      );
    final width = 200.0 + i * 20;
    canvas.drawRect(
      Rect.fromLTWH(width * .05, 90, width * .9, 20),
      Paint()..color = Colors.white,
    );
    final walls = Paint()
      ..color = Colors.blueGrey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(Rect.fromLTWH(width * .65, 25, width * .3, 65), walls);
    canvas.drawRect(Rect.fromLTWH(width * .45, 90, width * .1, 20), walls);
    final label = TextPainter(
      text: TextSpan(
        text: 'TEST FLOOR ${['G', 'I', 'II'][i]}',
        style: const TextStyle(color: Colors.black, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, const Offset(8, 150));
    final picture = r.endRecording(),
        image = await picture.toImage(200 + i * 20, 200);
    final b = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    f.image = await FloorPlanAsset.validate(
      Uint8List.fromList(
        b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes),
      ),
      'floor-$i.png',
      'image/png',
    );
    image.dispose();
    picture.dispose();
    // Keep Canvas construction confined to this fixture.
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('v3 round trip restores independent images/graph/Rooms/links; v2 imports unchanged', () async {
    final p = threeFloorProject();
    await attachFloorImages(p);
    final copy = await LocalMapProject.decode(p.encode());
    expect(copy.floors.length, 3);
    expect(copy.links.length, 2);
    for (var i = 0; i < 3; i++) {
      expect(copy.floors[i].image!.bytes, p.floors[i].image!.bytes);
      expect(copy.floors[i].nodeIds, p.floors[i].nodeIds);
      expect(copy.floors[i].places, p.floors[i].places);
      expect(copy.floors[i].image!.width, 200 + i * 20);
    }
    expect(copy.floors[0].image!.bytes, isNot(copy.floors[1].image!.bytes));
    final legacy = await LocalMapProject.decode(p.floors.first.encode());
    expect(legacy.floors.length, 1);
    expect(legacy.floors.first.nodeIds, p.floors.first.nodeIds);
    final route = (await LocalMapNavigation.fromProject(copy)).routeToRoom(
      copy.floors[0].nodeId('START'),
      copy.floors[2].places.single['id'],
    );
    expect(route.totalDistanceMeters, 30);
    expect(route.nodes.map((n) => n.floor.id), [1, 1, 2, 3, 3]);
    expect(route.edges.where((e) => e.movement == 'ChangeFloor').length, 2);
    expect(route.nodes.last.nodeCode, 'DOOR');
  });
  test('Same-floor, no connection, reverse direction, missing node, wrong transfer type and GUID collision', () async {
    final p = threeFloorProject();
    var nav = await LocalMapNavigation.fromProject(p);
    expect(
      nav
          .routeToRoom(
            p.floors[0].nodeId('START'),
            p.floors[0].places.single['id'],
          )
          .totalDistanceMeters,
      10,
    );
    expect(
      () => nav.routeToRoom(
        p.floors[2].nodeId('START'),
        p.floors[0].places.single['id'],
      ),
      throwsFormatException,
    );
    p.links.clear();
    nav = await LocalMapNavigation.fromProject(p);
    expect(
      () => nav.routeToRoom(
        p.floors[0].nodeId('START'),
        p.floors[2].places.single['id'],
      ),
      throwsFormatException,
    );
    p.links.add(
      LocalFloorLink(
        fromFloor: p.floors[0].localWorkspaceId!,
        fromNode: p.floors[0].nodeId('DOOR'),
        toFloor: p.floors[1].localWorkspaceId!,
        toNode: p.floors[1].nodeId('STAIR'),
        meters: 2,
        type: 'Stairs',
      ),
    );
    expect(LocalMapNavigation.validateProject(p).canRoute, isFalse);
    p.links.clear();
    p.floors[1].nodeIds['DOOR'] = p.floors[0].nodeId('DOOR');
    expect(LocalMapNavigation.validateProject(p).canRoute, isFalse);
  });
  test(
    'Room-less v3 project validates and routes to a marked Node across floors',
    () async {
      final project = threeFloorProject();
      for (final floor in project.floors) {
        floor.places.clear();
      }
      project.floors.last.putNode(
        const DraftNode(
          'DOOR',
          'Technical door',
          .8,
          .5,
          'Entrance',
          displayName: 'Radiology',
          searchableAsDestination: true,
          landmarkNote: 'Blue sign near the door',
        ),
        replace: true,
      );

      expect(LocalMapNavigation.validateProject(project).canRoute, isTrue);
      final navigation = await LocalMapNavigation.fromProject(project);
      final destination = navigation
          .graphFor(3)
          .nodes
          .singleWhere((node) => node.nodeCode == 'DOOR');
      final route = navigation.routeToNode(
        project.floors.first.nodeId('START'),
        destination.id,
        destination.floorId,
      );

      expect(route.nodes.last.id, destination.id);
      expect(route.nodes.last.floor.id, 3);
      expect(
        navigation.landmarkNoteForNode(destination.id, destination.floorId),
        'Blue sign near the door',
      );
    },
  );
  test(
    'Room-less v3 project without a marked destination reports guidance',
    () {
      final project = threeFloorProject();
      for (final floor in project.floors) {
        floor.places.clear();
      }

      final report = LocalMapNavigation.validateProject(project);
      expect(report.canRoute, isFalse);
      expect(
        report.errors.join(' '),
        contains('đánh dấu một Node làm điểm đến hoặc thêm Room/Place'),
      );
    },
  );
  test('Rename/remove floor preserve other floors, clear referencing links, frozen navigation survives edits', () async {
    final p = threeFloorProject(), first = p.floors.first;
    final nav = await LocalMapNavigation.fromProject(p);
    final renamed = await p.renameFloor(first, 'Ground', 'GROUND');
    expect(renamed.nodeIds, first.nodeIds);
    expect(p.links.first.fromFloor, renamed.localWorkspaceId);
    p.removeFloor(p.floors[1]);
    expect(p.links, isEmpty);
    expect(p.floors.length, 2);
    expect(
      nav
          .routeToRoom(first.nodeId('START'), p.floors.last.places.single['id'])
          .totalDistanceMeters,
      30,
    );
    expect(
      () => p.renameFloor(p.floors.first, 'Duplicate', 'II'),
      throwsFormatException,
    );
  });
  testWidgets(
    'Shared Navigation follows cross-floor steps with matching images, never draws cross-floor segment',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final p = threeFloorProject();
      p.floors[1].putNode(
        const DraftNode(
          'STAIR',
          'Cầu thang tầng I',
          .5,
          .5,
          'Stairs',
          landmarkNote: 'Bảng tầng I tại chiếu nghỉ',
        ),
        replace: true,
      );
      p.floors[2].putNode(
        const DraftNode(
          'STAIR',
          'Cầu thang tầng II',
          .5,
          .5,
          'Stairs',
          landmarkNote: 'Cửa thang mở ra sảnh tầng II',
        ),
        replace: true,
      );
      p.floors[2].putNode(
        const DraftNode(
          'DOOR',
          'Cửa phòng X-quang',
          .8,
          .5,
          'Entrance',
          landmarkNote: 'Biển X-quang cạnh cửa',
        ),
        replace: true,
      );
      final nav = await t.runAsync(() async {
        await attachFloorImages(p);
        return LocalMapNavigation.fromProject(p);
      });
      final route = nav!.routeToRoom(
        p.floors[0].nodeId('START'),
        p.floors[2].places.single['id'],
      );
      await t.pumpWidget(
        MaterialApp(
          home: NavigationPage(route: route, localMap: nav),
        ),
      );
      await t.runAsync(() async {
        for (var i = 1; i <= 3; i++) {
          await precacheImage(
            nav.imageFor(i)!,
            t.element(find.byType(NavigationPage)),
          );
        }
      });
      await t.pumpAndSettle();
      for (var index = 0; index < route.nodes.length; index++) {
        final floor = route.nodes[index].floor;
        expect(
          find.text('Tầng của bước hiện tại: ${floor.name}'),
          findsOneWidget,
        );
        final painter = t
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((p) => p.painter)
            .whereType<FloorRoutePainter>()
            .single;
        expect(painter.geometry.segments.length, floor.id == 2 ? 0 : 1);
        expect(painter.roomLabels.every((r) => r.floorId == floor.id), isTrue);
        final currentNote = nav.landmarkNoteForNode(
          route.nodes[index].id,
          route.nodes[index].floor.id,
        );
        if (currentNote == null) {
          expect(
            find.byKey(const Key('navigation-current-landmark-note')),
            findsNothing,
          );
        } else {
          expect(find.text('Mốc nhận biết: $currentNote'), findsOneWidget);
        }
        if (index < route.nodes.length - 1) {
          final nextNode = route.nodes[index + 1];
          final nextNote = nav.landmarkNoteForNode(
            nextNode.id,
            nextNode.floor.id,
          );
          if (nextNote == null) {
            expect(
              find.byKey(const Key('navigation-next-landmark-note')),
              findsNothing,
            );
          } else {
            expect(
              find.text('Mốc nhận biết điểm kế tiếp: $nextNote'),
              findsOneWidget,
            );
          }
        } else {
          expect(
            find.byKey(const Key('navigation-next-landmark-note')),
            findsNothing,
          );
        }
        if (index < route.nodes.length - 1) {
          await t.tap(find.byKey(const Key('navigation-confirm')));
          await t.pumpAndSettle();
        }
      }
      expect(find.byKey(const Key('mobile-arrival-summary')), findsOneWidget);
    },
  );
  testWidgets(
    'Builder declares directed cross-floor link with explicit reverse option',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final p = threeFloorProject()..links.clear();
      final files = MemoryDraftFiles()
        ..next = (bytes: p.encode(), name: 'p.json', mime: 'application/json');
      await t.pumpWidget(MaterialApp(home: DraftMapEditor(files: files)));
      await t.pumpAndSettle();
      await t.tap(find.text('Mở JSON'));
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 5));
      await t.ensureVisible(find.text('Nối tầng'));
      await t.pumpAndSettle();
      await t.tap(find.text('Nối tầng'));
      await t.pumpAndSettle();
      await t.tap(find.text('Từ node / tầng'));
      await t.pumpAndSettle();
      await t.tap(find.text('Tầng G: Cầu thang (STAIR)').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Đến node / tầng'));
      await t.pumpAndSettle();
      await t.tap(find.text('Tầng I: Cầu thang (STAIR)').last);
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Khoảng cách liên tầng (m)'),
        '7.5',
      );
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await t.tap(find.text('Lưu liên kết'));
      await t.pumpAndSettle();
      await Scrollable.ensureVisible(
        t.element(find.byKey(const Key('export-draft'))),
        alignment: .5,
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('export-draft')));
      await t.pumpAndSettle();
      final saved = await LocalMapProject.decode(files.saved!);
      expect(saved.links.length, 2);
      expect(saved.links.first.meters, 7.5);
      expect(saved.links.first.fromNode, saved.links.last.toNode);
      expect(saved.links.last.toJson()['accessibility'], 'Unknown');
    },
  );
  testWidgets(
    'Builder switches floor without losing draft; v3 preview/back keeps entire project',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final p = threeFloorProject(),
          files = MemoryDraftFiles()
            ..next = (
              bytes: threeFloorProject().encode(),
              name: 'three.json',
              mime: 'application/json',
            );
      files.next = (
        bytes: p.encode(),
        name: 'three.json',
        mime: 'application/json',
      );
      await t.pumpWidget(MaterialApp(home: DraftMapEditor(files: files)));
      await t.pumpAndSettle();
      await t.tap(find.text('Mở JSON'));
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 5));
      await t.tap(find.text('Tầng G (G)').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Tầng II (II)').last);
      await t.pumpAndSettle();
      expect(find.textContaining('Tầng II'), findsWidgets);
      await t.ensureVisible(find.byKey(const Key('add-project-floor')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('add-project-floor')));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Tên tầng'), 'Lầu IV');
      await t.enterText(find.widgetWithText(TextField, 'Mã tầng'), 'IV');
      await t.tap(find.text('Lưu tầng'));
      await t.pumpAndSettle();
      expect(find.text('0 Node • 0 Edge • 0 điểm đến'), findsOneWidget);
      await t.ensureVisible(find.text('Đổi tên tầng'));
      await t.tap(find.text('Đổi tên tầng'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Tên tầng'),
        'Lầu IV mới',
      );
      await t.tap(find.text('Lưu tầng'));
      await t.pumpAndSettle();
      expect(find.text('Lầu IV mới (IV)'), findsOneWidget);
      await t.ensureVisible(find.text('Xóa tầng'));
      await t.tap(find.text('Xóa tầng'));
      await t.pumpAndSettle();
      expect(find.textContaining('Xóa ảnh,'), findsOneWidget);
      await t.tap(find.text('Xóa tầng').last);
      await t.pumpAndSettle();
      expect(
        find.text('3 Node • 3 Edge • 1 điểm đến • 1 Room (legacy)'),
        findsOneWidget,
      );
      await t.ensureVisible(find.byKey(const Key('try-local-navigation')));
      await t.tap(find.byKey(const Key('try-local-navigation')));
      await t.pumpAndSettle();
      await t.tap(find.text('Chọn điểm đến'));
      await t.pumpAndSettle();
      expect(find.byType(LocalMapSearchPage), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('export-draft')));
      await t.tap(find.byKey(const Key('export-draft')));
      await t.pumpAndSettle();
      final restored = await LocalMapProject.decode(files.saved!);
      expect(restored.floors.length, 3);
      expect(restored.links.length, 2);
      expect(restored.floors[2].nodeIds, p.floors[2].nodeIds);
    },
  );
}
