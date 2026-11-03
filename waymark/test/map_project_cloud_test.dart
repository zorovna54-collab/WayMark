import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/admin/floor_plan_asset.dart';
import 'package:waymark/features/admin/map_project_cloud_page.dart';
import 'package:waymark/services/map_draft_api_service.dart';
import 'package:waymark/services/published_map_api_service.dart';
import 'package:waymark/services/waymark_api_service.dart';

import 'fixtures/published_map_fixture.dart';
import 'floor_image_cleanup_test.dart' show cleanupTestImage;

class CloudFixtureApi extends PublishedMapApiService {
  CloudFixtureApi(this.document);
  Map<String, dynamic> document;
  Map<String, dynamic>? saved;
  int? expected;
  String? savedId;
  @override
  Future<List<Map<String, dynamic>>> list() async => [];
  @override
  Future<List<Map<String, dynamic>>> qrs(String id) async => [];
  @override
  Future<Map<String, dynamic>> get(String id) async => document;
  @override
  Future<Map<String, dynamic>> readiness(String id) async => {
    'mapId': document['id'],
    'version': document['version'],
    'checks': [{'code': 'saved_graph_validation', 'passed': true, 'message': 'Graph fixture hợp lệ.'}],
  };
  @override
  Future<Map<String, dynamic>> save(
    String name,
    Map<String, dynamic> content, {
    String? id,
    int? version,
  }) async {
    saved = content;
    expected = version;
    savedId = id;
    document = {
      ...document,
      'id': id,
      'siteId': 1,
      'buildingId': 1,
      'version': 2,
      'name': name,
      'content': content,
    };
    return document;
  }
}

class StartQrFixtureApi extends CloudFixtureApi {
  StartQrFixtureApi(this.fixture, super.document);
  final PublishedMapFixture fixture;
  final records = <Map<String, dynamic>>[];
  int published = 0;
  String? createdNode;
  @override
  Future<List<Map<String, dynamic>>> qrs(String id) async => List.of(records);
  @override
  Future<Map<String, dynamic>> createQr(
    String id,
    int version,
    String floorKey,
    String nodeId,
  ) async {
    createdNode = nodeId;
    final q = {
      'id': '00000000-0000-4000-8000-000000000001',
      'mapId': id,
      'draftVersion': version,
      'publishedVersion': null,
      'floorKey': floorKey,
      'nodeId': nodeId,
      'payload': fixture.payload,
      'isActive': true,
    };
    records.add(q);
    return q;
  }

  @override
  Future<void> publish(String id, int version) async {
    published++;
    for (final q in records) {
      q['publishedVersion'] = version;
    }
  }
}

class SiteFixtureApi extends WayMarkApiService {
  @override
  Future<List<Map<String, dynamic>>> getSites() async => [];
  @override
  Future<List<Map<String, dynamic>>> getFloors(int buildingId) async => [
    for (var i = 10; i < 13; i++)
      {'id': i, 'name': 'Server $i', 'buildingId': 1},
  ];
}

class ImageFixtureApi extends MapDraftApiService {
  ImageFixtureApi(this.image);
  final FloorPlanAsset image;
  int uploads = 0;
  @override
  Future<DraftMetadata> metadata(int floor) async => DraftMetadata.fromJson({
    'id': newDraftGuid(),
    'siteId': 1,
    'buildingId': 1,
    'floorId': floor,
    'version': 1,
    'status': 'Draft',
    'updatedAt': '2026-10-23T00:00:00Z',
  });
  @override
  Future<DraftImageMetadata> upload(
    int floor,
    Uint8List bytes,
    String mime,
  ) async {
    uploads++;
    return DraftImageMetadata.fromJson({
      'id': newDraftGuid(),
      'floorId': floor,
      'mimeType': mime,
      'width': image.width,
      'height': image.height,
      'byteLength': bytes.length,
      'sha256': List.filled(64, 'a').join(),
    });
  }
}

void main() {
  testWidgets(
    'Personal saved draft -> select saved QR start -> publish -> pinned QR; no unsaved node QR',
    (t) async {
      final fixture = PublishedMapFixture(
        (await t.runAsync(cleanupTestImage))!,
      );
      final savedContent =
          jsonDecode(jsonEncode(fixture.content)) as Map<String, dynamic>;
      fixture.project.floors.first.putNode(
        const DraftNode('UNSAVED', 'Not saved yet', .2, .3, 'Junction'),
      );
      final doc = {
        'id': fixture.mapId,
        'name': 'Personal map',
        'version': 1,
        'siteId': 1,
        'buildingId': 1,
        'content': savedContent,
        'canPublish': true,
        'publicationKind': 'PersonalDemo',
      };
      final maps = StartQrFixtureApi(fixture, doc);
      await t.pumpWidget(
        MaterialApp(
          home: MapProjectCloudPage(
            project: fixture.project,
            link: ProjectCloudLink(doc, fixture.project),
            maps: maps,
            api: SiteFixtureApi(),
          ),
        ),
      );
      await t.pumpAndSettle();
      final dropdown = find.byWidgetPredicate(
        (w) => w is DropdownButtonFormField<String>,
      );
      await t.scrollUntilVisible(
        dropdown,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(dropdown);
      await t.pumpAndSettle();
      expect(find.textContaining('Not saved yet'), findsNothing);
      final floor = (savedContent['floors'] as List).first as Map,
          node =
              (savedContent['floors'][0]['content']['nodes'] as List).first
                  as Map;
      final label =
          '${floor['name']} • N01 · ${node['displayName'] ?? node['name']}';
      await t.tap(find.text(label).last);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Tạo / xem QR cho Node'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Tạo / xem QR cho Node'));
      await t.pumpAndSettle();
      expect(maps.createdNode, node['id']);
      expect(
        find.text('Chưa publish • không dùng định vị Visitor'),
        findsOneWidget,
      );
      await t.tap(find.text('Đóng'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Xuất bản snapshot đã lưu'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Xuất bản snapshot đã lưu'));
      await t.pumpAndSettle();
      await t.tap(find.text('Xuất bản snapshot'));
      await t.pumpAndSettle();
      expect(maps.published, 1);
      expect(maps.records.single['publishedVersion'], 1);
      expect(find.textContaining('Đã xuất bản snapshot v1'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  for (final canPublish in [false, true]) {
    testWidgets(
      'Cloud uses server publish capability=$canPublish and explains missing QR',
      (t) async {
        t.view.physicalSize = const Size(1024, 1800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final image = (await t.runAsync(cleanupTestImage))!;
        final fixture = PublishedMapFixture(image);
        final doc = {
          'id': fixture.mapId,
          'name': 'Map',
          'version': 1,
          'siteId': 1,
          'buildingId': 1,
          'content': fixture.content,
          'canPublish': canPublish,
          'publicationKind': canPublish ? 'PersonalDemo' : 'FacilityScoped',
        };
        await t.pumpWidget(
          MaterialApp(
            home: MapProjectCloudPage(
              project: fixture.project,
              link: ProjectCloudLink(doc, fixture.project),
              api: SiteFixtureApi(),
              maps: CloudFixtureApi(doc),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(
          find.text('Xuất bản snapshot đã lưu'),
          canPublish ? findsOneWidget : findsNothing,
        );
        if (canPublish) {
          expect(
            t
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Xuất bản snapshot đã lưu'),
                )
                .onPressed,
            isNull,
          );
          expect(find.textContaining('Tạo QR cho ít nhất'), findsWidgets);
          expect(find.textContaining('không đại diện cơ sở'), findsOneWidget);
        } else {
          expect(
            find.textContaining('Cần được cấp quyền xuất bản'),
            findsOneWidget,
          );
        }
      },
    );
  }
  for (final replaceImage in [false, true]) {
    testWidgets(
      'Reopen linked cloud draft retains edits/version; ${replaceImage ? 'changed image uploads once' : 'unchanged images reused'}',
      (t) async {
        final image = (await t.runAsync(cleanupTestImage))!;
        final fixture = PublishedMapFixture(image);
        final doc = {
          'id': fixture.mapId,
          'siteId': 1,
          'buildingId': 1,
          'name': 'Map',
          'version': 1,
          'content': fixture.content,
        };
        final link = ProjectCloudLink(doc, fixture.project);
        final floor = fixture.project.floors.first,
            node = fixture.project.floors.first.nodes.first;
        floor.putNode(
          DraftNode(node.code, 'Changed locally', node.x, node.y, node.type),
          replace: true,
        );
        if (replaceImage) {
          final bytes = Uint8List.fromList([...image.bytes, 0]);
          floor.image = await t.runAsync(
            () => FloorPlanAsset.validate(bytes, 'changed.png', 'image/png'),
          );
        }
        final maps = CloudFixtureApi(doc), images = ImageFixtureApi(image);
        ProjectCloudLink? savedLink;
        await t.pumpWidget(
          MaterialApp(
            home: MapProjectCloudPage(
              project: fixture.project,
              link: link,
              maps: maps,
              api: SiteFixtureApi(),
              images: images,
              onLinked: (v) => savedLink = v,
            ),
          ),
        );
        await t.pumpAndSettle();
        final save = find.text('Lưu draft nhiều tầng lên server');
        await t.scrollUntilVisible(
          save,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        await t.tap(save);
        await t.pumpAndSettle();
        expect(maps.savedId, fixture.mapId);
        expect(maps.expected, 1);
        expect(
          (maps.saved!['floors'] as List).first['content']['nodes'][0]['name'],
          'Changed locally',
        );
        expect(images.uploads, replaceImage ? 1 : 0);
        expect(savedLink!.document['version'], 2);
        expect(floor.nodes.first.name, 'Changed locally');
        expect(t.takeException(), isNull);
      },
    );
  }
}
