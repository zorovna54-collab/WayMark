import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/admin/draft_map_editor.dart';
import 'package:waymark/features/admin/draft_server_session.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/map_draft_api_service.dart';
import 'package:waymark/services/waymark_api_service.dart';

import 'draft_floor_workflow_test.dart' show MemoryDraftFiles;
import 'fixtures/map_draft_fixture.dart';
import 'fixtures/routing_fixture.dart';

void main() {
  late DraftHttpFixture server;
  late MemoryDraftFiles files;
  late MockClient client;
  setUp(() {
    AuthSession.accessToken = 'widget-draft-token';
    server = DraftHttpFixture();
    files = MemoryDraftFiles();
    client = MockClient((http.Request r) async {
      if (r.url.path.contains('/admin/')) return server.handle(r);
      expect(r.method, 'GET'); // production graph never written
      final p = r.url.path;
      if (p.endsWith('/sites')) {
        return jsonResponse([
          {'id': 1, 'name': 'Site'},
        ]);
      }
      if (p.endsWith('/buildings')) {
        return jsonResponse([
          {'id': 1, 'siteId': 1, 'name': 'Building'},
        ]);
      }
      if (p.endsWith('/floors')) {
        return jsonResponse([
          floorGraphJson(1)['floor'],
          floorGraphJson(2)['floor'],
        ]);
      }
      return jsonResponse(floorGraphJson(p.contains('/2/') ? 2 : 1));
    });
  });
  tearDown(() {
    client.close();
    AuthSession.clear();
  });
  Future<void> choose(WidgetTester t, String level, String label) async {
    await t.ensureVisible(find.byKey(ValueKey('draft-$level')));
    await t.tap(find.byKey(ValueKey('draft-$level')));
    await t.pumpAndSettle();
    await t.tap(find.text(label).last);
    await t.pumpAndSettle();
  }

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(1600, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: DraftMapEditor(
          api: WayMarkApiService(client: client),
          draftsApi: MapDraftApiService(client: client),
          files: files,
        ),
      ),
    );
    await t.pumpAndSettle();
    await choose(t, 'Site', 'Site');
    await choose(t, 'Building', 'Building');
    await choose(t, 'Floor', 'Floor one');
  }

  Future<void> tap(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(Key(key)));
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  Future<void> importLocal(WidgetTester t) async {
    files.next = (
      bytes: localDraft().encode(),
      name: 'backup.json',
      mime: 'application/json',
    );
    await tap(t, 'import-draft');
    expect(find.text('Có thay đổi local chưa lưu server'), findsOneWidget);
  }

  testWidgets(
    'Create/save confirmed only after success; load recovers Room and nodes',
    (t) async {
      await open(t);
      await importLocal(t);
      await tap(t, 'save-server-draft');
      expect(find.text('Đã xác nhận bản nháp server'), findsOneWidget);
      expect(find.textContaining('Revision 1 •'), findsOneWidget);
      await tap(t, 'load-server-draft');
      final p =
          t
                  .widget<CustomPaint>(
                    find.byKey(const Key('floor-route-canvas')),
                  )
                  .painter!
              as DraftMapPainter;
      expect(p.draft.places.single['entranceNodeIds'], [entranceId]);
      expect(p.draft.nodes.first.code, 'DOOR');
      expect(AuthSession.accessToken, 'widget-draft-token');
    },
  );

  testWidgets('Retained Builder Save-before-leave dialog cannot save under B', (
    t,
  ) async {
    await open(t);
    await importLocal(t);
    final before = server.version;
    await tap(t, 'load-server-draft');
    expect(find.text('Lưu trước khi rời'), findsOneWidget);
    AuthSession.establish('replacement-fixture-token', 'owner-B');
    await t.pumpAndSettle();
    expect(find.text('Lưu trước khi rời'), findsNothing);
    expect(find.text('Phiên làm việc đã thay đổi'), findsOneWidget);
    await t.tap(find.text('Đóng'));
    await t.pumpAndSettle();
    expect(server.version, before);
    expect(files.saved, isNull);
    expect(t.takeException(), isNull);
  });

  testWidgets('Save 503 leaves dirty/local graph and offline export works', (
    t,
  ) async {
    server
      ..version = 1
      ..content = DraftServerMapper.content(localDraft(), null);
    await open(t);
    await tap(t, 'load-server-draft');
    await importLocal(t);
    server.failureCode = 'draft_storage_unavailable';
    await tap(t, 'save-server-draft');
    expect(find.text('Có thay đổi local chưa lưu server'), findsOneWidget);
    expect(
      find.textContaining('Kho ảnh/dữ liệu bản nháp chưa khả dụng'),
      findsWidgets,
    );
    await tap(t, 'export-draft');
    expect(files.saved, isNotNull);
    expect(server.content!['places'][0]['name'], 'Exam room');
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'Version conflict offers keep/reload/export; quota does not offer overwrite',
    (t) async {
      await open(t);
      await importLocal(t);
      await tap(t, 'save-server-draft');
      await importLocal(t);
      server
        ..failureCode = 'draft_version_conflict'
        ..failureStatus = 409;
      await tap(t, 'save-server-draft');
      expect(find.text('Xung đột phiên bản'), findsOneWidget);
      expect(find.text('Xuất backup JSON'), findsOneWidget);
      await t.tap(find.text('Giữ local'));
      await t.pumpAndSettle();
      expect(find.text('Có thay đổi local chưa lưu server'), findsOneWidget);
      server.failureCode = 'draft_revision_quota';
      await tap(t, 'save-server-draft');
      expect(find.text('Xung đột phiên bản'), findsNothing);
      expect(find.textContaining('quota'), findsWidgets);
    },
  );

  testWidgets(
    'Dirty reload, floor change and Android Back require confirmation; floor session isolated',
    (t) async {
      await open(t);
      await importLocal(t);
      await tap(t, 'load-server-draft');
      expect(find.text('Rời bản nháp chưa xuất?'), findsOneWidget);
      await t.tap(find.text('Giữ lại'));
      await t.pumpAndSettle();
      expect(server.requests, isEmpty);
      await choose(t, 'Floor', 'Floor two');
      expect(find.text('Rời bản nháp chưa xuất?'), findsOneWidget);
      await t.tap(find.text('Giữ lại'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<DropdownButton<int>>(
              find.byKey(const ValueKey('draft-Floor')),
            )
            .value,
        1,
      );
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Rời bản nháp chưa xuất?'), findsOneWidget);
      await t.tap(find.text('Giữ lại'));
      await t.pumpAndSettle();
      await choose(t, 'Floor', 'Floor two');
      await t.tap(find.text('Rời bản nháp'));
      await t.pumpAndSettle();
      final p =
          t
                  .widget<CustomPaint>(
                    find.byKey(const Key('floor-route-canvas')),
                  )
                  .painter!
              as DraftMapPainter;
      expect(p.draft.floor.id, 2);
      expect(p.draft.places, isEmpty);
      expect(find.textContaining('Revision 1 •'), findsNothing);
      expect(AuthSession.accessToken, 'widget-draft-token');
    },
  );

  testWidgets('History restore requires confirm and produces new revision', (
    t,
  ) async {
    server
      ..version = 2
      ..content = DraftServerMapper.content(localDraft(), null);
    await open(t);
    await tap(t, 'load-server-draft');
    await tap(t, 'draft-revisions');
    expect(find.text('Revision 1'), findsOneWidget);
    await t.tap(find.text('Khôi phục').last);
    await t.pumpAndSettle();
    expect(find.text('Khôi phục revision 1?'), findsOneWidget);
    expect(server.restores, 0);
    await t.tap(find.text('Xác nhận khôi phục'));
    await t.pumpAndSettle();
    expect(server.restores, 1);
    expect(find.textContaining('Revision 3 •'), findsOneWidget);
  });
}
