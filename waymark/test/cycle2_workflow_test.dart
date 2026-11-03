import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/published_map_api_service.dart';
import 'package:waymark/services/map_draft_api_service.dart';
import 'package:waymark/services/waymark_api_service.dart';
import 'package:waymark/features/admin/map_project_cloud_page.dart';

import 'fixtures/published_map_fixture.dart';
import 'floor_image_cleanup_test.dart' show cleanupTestImage;
import 'map_project_cloud_test.dart' show StartQrFixtureApi, SiteFixtureApi;

void main() {
  setUp(() => AuthSession.establish('fixture-A', 'owner-A'));
  tearDown(AuthSession.clear);
  test(
    'current private 401 invalidates workflows without clearing owner identity',
    () async {
      final revision = AuthSession.revision;
      final api = PublishedMapApiService(
        client: MockClient((_) async => http.Response('{}', 401)),
      );
      await expectLater(api.list(), throwsA(isA<MapDraftApiException>()));
      expect(AuthSession.revision, greaterThan(revision));
      expect(AuthSession.username, 'owner-A');
    },
  );
  for (final status in [403, 500]) {
    test('private $status does not expire current session', () async {
      final revision = AuthSession.revision;
      final api = PublishedMapApiService(
        client: MockClient((_) async => http.Response('{}', status)),
      );
      await expectLater(api.list(), throwsA(isA<MapDraftApiException>()));
      expect(AuthSession.revision, revision);
    });
  }
  test('old 401 cannot expire new owner even when token reused', () async {
    final pending = Completer<http.Response>();
    final api = PublishedMapApiService(
      client: MockClient((_) => pending.future),
    );
    final future = api.list();
    AuthSession.establish('fixture-A', 'owner-B');
    final revision = AuthSession.revision;
    pending.complete(http.Response('{}', 401));
    await expectLater(
      future,
      throwsA(
        isA<MapDraftApiException>().having(
          (e) => e.code,
          'code',
          'auth_session_changed',
        ),
      ),
    );
    expect(AuthSession.revision, revision);
    expect(AuthSession.username, 'owner-B');
  });
  test('public 401 and timeout never expire private session', () async {
    final revision = AuthSession.revision;
    final publicApi = PublishedMapApiService(
      client: MockClient((r) async {
        expect(r.headers.containsKey('Authorization'), false);
        return http.Response('{}', 401);
      }),
    );
    await expectLater(
      publicApi.json('public/fixture'),
      throwsA(isA<MapDraftApiException>()),
    );
    final privateApi = PublishedMapApiService(
      client: MockClient((_) async => throw TimeoutException('fixture')),
    );
    await expectLater(
      privateApi.list(),
      throwsA(
        isA<MapDraftApiException>().having(
          (e) => e.uncertain,
          'uncertain',
          true,
        ),
      ),
    );
    expect(AuthSession.revision, revision);
  });

  test(
    'draft and legacy private readers expire only the current session on 401',
    () async {
      final client = MockClient((_) async => http.Response('{}', 401));
      final revision = AuthSession.revision;
      await expectLater(
        MapDraftApiService(client: client).metadata(1),
        throwsA(isA<MapDraftApiException>()),
      );
      expect(AuthSession.revision, greaterThan(revision));
      expect(AuthSession.expired, true);
      AuthSession.establish('fixture-A2', 'owner-A');
      await expectLater(
        WayMarkApiService(client: client).getSites(),
        throwsA(isA<WayMarkApiException>()),
      );
      expect(AuthSession.expired, true);
    },
  );
  testWidgets(
    'disposed cloud ignores pending private list without state writes',
    (t) async {
      final api = _PendingList();
      await t.pumpWidget(
        MaterialApp(
          home: MapProjectCloudPage(maps: api, api: SiteFixtureApi()),
        ),
      );
      await t.pump();
      await t.pumpWidget(const SizedBox());
      api.listResult.complete([]);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(api.reads, 1);
    },
  );
  for (final action in ['publish', 'revoke']) {
    testWidgets(
      'retained $action confirmation cannot run under replacement owner',
      (t) async {
        t.view.physicalSize = const Size(1024, 1800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final fixture = PublishedMapFixture(
          (await t.runAsync(cleanupTestImage))!,
        );
        final doc = <String, dynamic>{
          'id': fixture.mapId,
          'name': 'Private A',
          'version': 1,
          'siteId': 1,
          'buildingId': 1,
          'content': jsonDecode(jsonEncode(fixture.content)),
          'canPublish': true,
          'publicationKind': 'PersonalDemo',
        };
        final api = _Actions(fixture, doc);
        await api.createQr(
          fixture.mapId,
          1,
          fixture.content['floors'][0]['id'],
          fixture.content['floors'][0]['content']['nodes'][0]['id'],
        );
        await t.pumpWidget(
          MaterialApp(
            home: MapProjectCloudPage(
              project: fixture.project,
              link: ProjectCloudLink(doc, fixture.project),
              maps: api,
              api: SiteFixtureApi(),
            ),
          ),
        );
        await t.pumpAndSettle();
        final button = find.widgetWithText(
          action == 'publish' ? FilledButton : TextButton,
          action == 'publish' ? 'Xuất bản snapshot đã lưu' : 'Thu hồi',
        );
        await t.scrollUntilVisible(
          button,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await t.tap(button);
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        AuthSession.establish('fixture-B', 'owner-B');
        await t.pumpAndSettle();
        final confirm = find.widgetWithText(
          FilledButton,
          action == 'publish' ? 'Xuất bản snapshot' : 'Thu hồi',
        );
        if (confirm.evaluate().isNotEmpty) {
          await t.tap(confirm);
          await t.pumpAndSettle();
        }
        expect(api.published, 0);
        expect(api.revoked, 0);
        expect(find.textContaining('Private A'), findsNothing);
      },
    );
  }
}

class _Actions extends StartQrFixtureApi {
  _Actions(super.fixture, super.document);
  int revoked = 0;
  @override
  Future<void> revoke(String mapId, String qrId) async {
    revoked++;
  }
}

class _PendingList extends PublishedMapApiService {
  final listResult = Completer<List<Map<String, dynamic>>>();
  int reads = 0;
  @override
  Future<List<Map<String, dynamic>>> list() {
    reads++;
    return listResult.future;
  }
}
