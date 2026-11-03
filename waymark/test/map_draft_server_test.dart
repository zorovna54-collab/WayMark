import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/admin/draft_server_session.dart';
import 'package:waymark/features/admin/floor_plan_asset.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/map_draft_api_service.dart';
import 'package:waymark/services/waymark_api_service.dart';

import 'fixtures/map_draft_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List png;
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xff2188bb), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(2, 1);
    png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
    image.dispose();
    picture.dispose();
  });
  setUp(() {
    AuthSession.accessToken = 'isolated-draft-test';
  });
  tearDown(AuthSession.clear);
  DraftServerSession session(MapDraftApiService api) =>
      DraftServerSession(api, siteId: 1, buildingId: 1, floor: draftFloor());

  test('JSON v2 -> server v1 -> local preserves GUIDs, places, entrances, transitions, image', () async {
    final draft = localDraft();
    draft.image = await FloorPlanAsset.validate(png, 'plan.png', 'image/png');
    final exported = await DraftMap.decode(
      draft.encode(),
      siteId: 1,
      buildingId: 1,
      floor: draftFloor(),
    );
    final content = DraftServerMapper.content(exported, imageId);
    expect(content['schemaVersion'], 1);
    expect(content.containsKey('siteId'), false);
    expect(content.containsKey('image'), false);
    expect((content['nodes'] as List).first['id'], entranceId);
    expect((content['edges'] as List).single['fromNodeId'], entranceId);
    final restored = DraftServerMapper.fromContent(
      content,
      siteId: 1,
      buildingId: 1,
      floor: draftFloor(),
    );
    expect(DraftServerMapper.content(restored, imageId), content);
    expect(exported.image!.bytes, orderedEquals(png));
    expect(restored.places.single['entranceNodeIds'], [entranceId]);
    expect(restored.transitions.single['targetVersion'], 3);
    expect(() => restored.removeNode('DOOR'), throwsFormatException);
    expect(() => restored.removeNode('LIFT'), throwsFormatException);
    expect(
      () => restored.putNode(
        const DraftNode('DOOR', 'Door', .1, .2, 'Junction'),
        replace: true,
      ),
      throwsFormatException,
    );
  });

  test(
    'Unmeasured and inactive edges survive roundtrip; no invented local route',
    () async {
      final d = localDraft();
      final old = d.edges.single;
      d.updateEdge(
        old,
        const DraftEdge(
          'DOOR',
          'LIFT',
          0,
          'Corridor',
          isActive: false,
          isMeasured: false,
        ),
      );
      final c = DraftServerMapper.content(d, null);
      expect((c['edges'] as List).single['id'], edgeId);
      expect((c['edges'] as List).single['distanceMeters'], isNull);
      final r = DraftServerMapper.fromContent(
        c,
        siteId: 1,
        buildingId: 1,
        floor: draftFloor(),
      );
      expect(r.edges.single.isMeasured, false);
      expect(r.edges.single.isActive, false);
      final local = await DraftMap.decode(
        r.encode(),
        siteId: 1,
        buildingId: 1,
        floor: draftFloor(),
      );
      expect(DraftServerMapper.content(local, null), c);
      local.image = await FloorPlanAsset.validate(png, 'plan.png', 'image/png');
      local.layoutReviewed = true;
      expect(() => local.previewRoute('DOOR', 'LIFT'), throwsFormatException);
    },
  );

  test(
    'Create graph without image, then append save; current JWT/base URL reused',
    () async {
      final server = DraftHttpFixture();
      final client = MockClient(server.handle);
      addTearDown(client.close);
      final s = session(MapDraftApiService(client: client));
      final draft = localDraft();
      await s.save(draft);
      expect(server.version, 1);
      expect(s.savedAt, isNotNull);
      draft.putNode(draft.nodes.first.at(.25, .35), replace: true);
      AuthSession.accessToken = 'updated-session-token';
      await s.save(draft);
      expect(server.version, 2);
      expect(server.content!['nodes'][0]['x'], .25);
      expect(
        server.requests.last.headers['Authorization'],
        'Bearer updated-session-token',
      );
      expect(
        server.requests.first.url.toString(),
        '${WayMarkApiService.baseUrl}/admin/floors/1/map-drafts',
      );
      expect(server.requests.where((r) => r.method == 'POST').length, 1);
      expect(AuthSession.accessToken, 'updated-session-token');
    },
  );

  test('Upload owner -> raw PNG -> asset binding; load with protected image, restore appends', () async {
    final server = DraftHttpFixture();
    final client = MockClient(server.handle);
    addTearDown(client.close);
    final api = MapDraftApiService(client: client),
        s = session(MapDraftApiService(client: client));
    final d = localDraft()
      ..image = await FloorPlanAsset.validate(png, 'plan.png', 'image/png');
    await s.save(d);
    expect(server.version, 2);
    expect(server.uploads, 1);
    expect(server.content!['imageAssetId'], imageId);
    final upload = server.requests.singleWhere(
      (r) => r.url.path.endsWith('/images'),
    );
    expect(upload.headers['content-type'], 'image/png');
    expect(upload.bodyBytes, orderedEquals(png));
    final reader = session(api);
    final loaded = await reader.load();
    expect(loaded.image!.bytes, orderedEquals(png));
    expect(loaded.places, d.places);
    expect(loaded.transitions, d.transitions);
    await reader.save(loaded);
    expect(server.uploads, 1); // reuses the downloaded asset
    expect((await reader.revisions()).map((r) => r.version), [3, 2, 1]);
    final restored = await reader.restore(2);
    expect(server.restores, 1);
    expect(reader.metadata!.version, 4);
    expect(restored.image!.bytes, orderedEquals(png));
    expect(
      server.requests.every(
        (r) => r.headers['Authorization'] == 'Bearer isolated-draft-test',
      ),
      true,
    );
  });

  test('Upload succeeded/save failed retains asset; retry does not duplicate upload', () async {
    final server = DraftHttpFixture()
      ..failureCode = 'draft_storage_unavailable';
    final client = MockClient(server.handle);
    addTearDown(client.close);
    final s = session(MapDraftApiService(client: client));
    final d = localDraft()
      ..image = await FloorPlanAsset.validate(png, 'plan.png', 'image/png');
    final before = d.encode();
    await expectLater(
      s.save(d),
      throwsA(
        isA<MapDraftApiException>().having((e) => e.status, 'status', 503),
      ),
    );
    expect(d.encode(), orderedEquals(before));
    expect(s.savedAt, isNull);
    expect(s.metadata!.version, 1);
    expect(server.uploads, 1);
    server.failureCode = null;
    // A JSON backup/import of the same bytes also reuses the pending asset.
    final imported = await DraftMap.decode(
      d.encode(),
      siteId: 1,
      buildingId: 1,
      floor: draftFloor(),
    );
    await s.save(imported);
    expect(server.uploads, 1);
    expect(server.content!['imageAssetId'], imageId);
    expect(s.savedAt, isNotNull);
  });

  test('Ambiguous upload blocks blind retry; scoped list + explicit recovery reuses asset', () async {
    final server = DraftHttpFixture()..failUpload = true;
    final client = MockClient(server.handle);
    addTearDown(client.close);
    final api = MapDraftApiService(client: client),
        s = session(MapDraftApiService(client: client));
    final d = localDraft()
      ..image = await FloorPlanAsset.validate(png, 'plan.png', 'image/png');
    await expectLater(s.save(d), throwsA(isA<MapDraftApiException>()));
    await expectLater(
      s.save(d),
      throwsA(
        isA<MapDraftApiException>().having(
          (e) => e.code,
          'code',
          'upload_uncertain',
        ),
      ),
    );
    expect(server.uploads, 1);
    expect(s.savedAt, isNull);
    final images = await api.images(1);
    d.image = await s.recoverImage(images.single);
    await s.save(d);
    expect(server.uploads, 1);
    expect(server.version, 2);
  });

  test('Existing server head requires explicit load; never overwrites from local floor selection', () async {
    final server = DraftHttpFixture()..version = 3;
    final client = MockClient(server.handle);
    addTearDown(client.close);
    final s = session(MapDraftApiService(client: client));
    await expectLater(
      s.save(localDraft()),
      throwsA(
        isA<MapDraftApiException>().having(
          (e) => e.versionConflict,
          'conflict',
          true,
        ),
      ),
    );
    expect(server.saves, 0);
    expect(s.metadata, isNull);
  });

  test('Concurrent version vs quota conflicts are distinct; local and old version preserved', () async {
    final server = DraftHttpFixture();
    final client = MockClient(server.handle);
    addTearDown(client.close);
    final s = session(MapDraftApiService(client: client)), d = localDraft();
    await s.save(d);
    for (final code in [
      'draft_version_conflict',
      'draft_revision_quota',
      'floor_image_quota',
      'image_storage_quota',
      'image_key_conflict',
    ]) {
      server
        ..failureCode = code
        ..failureStatus = 409;
      final backup = d.encode();
      await expectLater(
        s.save(d),
        throwsA(
          isA<MapDraftApiException>().having(
            (e) => e.versionConflict,
            'conflict',
            code == 'draft_version_conflict',
          ),
        ),
      );
      expect(d.encode(), orderedEquals(backup));
      expect(s.metadata!.version, 1);
    }
  });

  test(
    'Wrong floor graph/metadata and local map cannot cross the selected scope',
    () async {
      final client = MockClient((r) async => jsonResponse(draftMetadata(1, 2)));
      addTearDown(client.close);
      final s = session(MapDraftApiService(client: client));
      await expectLater(s.load(), throwsFormatException);
      expect(s.metadata, isNull);
      await expectLater(
        s.save(DraftMap(siteId: 2, buildingId: 1, floor: draftFloor())),
        throwsFormatException,
      );
      final api = MapDraftApiService(
        client: MockClient(
          (r) async => jsonResponse({
            'draftId': draftId,
            'floorId': 2,
            'version': 1,
            'status': 'Draft',
            'content': {},
          }),
        ),
      );
      addTearDown(api.client!.close);
      await expectLater(
        api.graph(1, draftId, 1),
        throwsA(isA<MapDraftApiException>()),
      );
    },
  );

  test('Failed image download never replaces session or local graph; restores also fail closed', () async {
    final server = DraftHttpFixture();
    final client = MockClient(server.handle);
    addTearDown(client.close);
    final s = session(MapDraftApiService(client: client)), d = localDraft();
    d.image = await FloorPlanAsset.validate(png, 'plan.png', 'image/png');
    await s.save(d);
    final before = d.encode();
    server.failDownload = true;
    await expectLater(s.load(), throwsA(isA<MapDraftApiException>()));
    expect(s.metadata!.version, 2);
    expect(d.encode(), orderedEquals(before));
    await expectLater(
      s.restore(1),
      throwsA(
        isA<MapDraftApiException>().having(
          (e) => e.code,
          'requires reload',
          'restore_reload_required',
        ),
      ),
    );
    expect(server.version, 3);
    expect(s.metadata!.version, 2); // requires Reload before retry
  });

  for (final status in [400, 401, 403, 404, 409, 413, 503]) {
    test(
      'HTTP $status is explicit, preserves JWT and local/offline backup',
      () async {
        final client = MockClient(
          (r) async => jsonResponse({'code': 'isolated_failure'}, status),
        );
        addTearDown(client.close);
        final s = session(MapDraftApiService(client: client)), d = localDraft();
        final backup = d.encode();
        await expectLater(
          s.save(d),
          throwsA(
            isA<MapDraftApiException>().having(
              (e) => e.status,
              'status',
              status,
            ),
          ),
        );
        expect(d.encode(), orderedEquals(backup));
        expect(s.savedAt, isNull);
        final restored = await DraftMap.decode(
          d.encode(),
          siteId: 1,
          buildingId: 1,
          floor: draftFloor(),
        );
        expect(restored.nodes.length, 2);
        expect(AuthSession.accessToken, 'isolated-draft-test');
      },
    );
  }

  test('Missing JWT sends no request and preserves AuthSession', () async {
    AuthSession.accessToken = null;
    var requests = 0;
    final client = MockClient((r) async {
      requests++;
      return jsonResponse({});
    });
    addTearDown(client.close);
    await expectLater(
      MapDraftApiService(client: client).metadata(1),
      throwsA(
        isA<MapDraftApiException>().having((e) => e.status, 'status', 401),
      ),
    );
    expect(requests, 0);
  });
  for (final body in ['not json', '{}', '[]', '{"id":123}']) {
    test('Invalid response $body never confirms Saved', () async {
      final client = MockClient((r) async => http.Response(body, 200));
      addTearDown(client.close);
      final s = session(MapDraftApiService(client: client));
      await expectLater(
        s.save(localDraft()),
        throwsA(
          isA<MapDraftApiException>().having(
            (e) => e.code,
            'code',
            'invalid_response',
          ),
        ),
      );
      expect(s.savedAt, isNull);
    });
  }
  test(
    'Network and timeout retain local data and never call production APIs',
    () async {
      for (final slow in [false, true]) {
        final client = MockClient((r) async {
          if (!slow) throw http.ClientException('offline');
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return jsonResponse({});
        });
        addTearDown(client.close);
        final s = session(
          MapDraftApiService(
            client: client,
            timeout: const Duration(milliseconds: 5),
          ),
        );
        final d = localDraft(), before = jsonEncode(localDraft().toJson());
        await expectLater(
          s.save(d),
          throwsA(
            isA<MapDraftApiException>().having(
              (e) => e.code,
              'code',
              slow ? 'timeout' : 'network',
            ),
          ),
        );
        expect(jsonEncode(d.toJson()), before);
        expect(s.savedAt, isNull);
      }
    },
  );
}
