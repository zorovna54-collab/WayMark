import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/navigation_history_service.dart';
import 'package:waymark/features/home/home_page.dart';
import 'package:waymark/features/history/history_page.dart';
import 'package:waymark/features/search/local_map_search_page.dart';

import 'fixtures/published_map_fixture.dart';
import 'floor_image_cleanup_test.dart' show cleanupTestImage;

http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
void main() {
  tearDown(AuthSession.clear);
  testWidgets(
    'Search failed cancellation offers staying and preserves the scanned session',
    (t) async {
      AuthSession.accessToken = 'a';
      final f = PublishedMapFixture((await t.runAsync(cleanupTestImage))!);
      final session = (await t.runAsync(() => f.api.loadQr(f.payload)))!;
      final service = NavigationHistoryService(
        client: MockClient(
          (r) async => r.method == 'PUT' ? json({}, 503) : json({}),
        ),
      );
      recordPublishedScan(session, service: service);
      await t.runAsync(() => session.map.historySession!.scanned());
      await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Previous screen'))),
      );
      final nav = Navigator.of(t.element(find.text('Previous screen')));
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => LocalMapSearchPage(
            map: session.map,
            destinationFloors: session.project.floors,
            initialStart: session.startKey,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const Key('local-start-node')),
            )
            .onChanged,
        isNull,
      );
      await t.pageBack();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pumpAndSettle();
      expect(find.text('Chưa đồng bộ lịch sử'), findsOneWidget);
      await t.tap(find.text('Ở lại / Thử lại'));
      await t.pumpAndSettle();
      expect(find.byType(LocalMapSearchPage), findsOneWidget);
      expect(session.map.historySession!.ended, isFalse);
      expect(AuthSession.accessToken, 'a');
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  test('Resolve alone does not create History; explicit scan records once, destination/start/finish share ID; failures retry', () async {
    final f = PublishedMapFixture(await cleanupTestImage());
    final session = await f.api.loadQr(f.payload);
    expect(session.map.historySession, isNull);
    AuthSession.accessToken = 'a';
    final requests = <http.Request>[];
    bool failScan = true;
    final service = NavigationHistoryService(
      client: MockClient((r) async {
        requests.add(r);
        if (r.method == 'POST' && failScan) return json({}, 503);
        return json({});
      }),
    );
    recordPublishedScan(session, service: service);
    final h = session.map.historySession!;
    await h.scanned();
    expect(h.message.value, contains('Chưa đồng bộ'));
    failScan = false;
    await h.scanned();
    final posts = requests.where((r) => r.method == 'POST').toList();
    final id = jsonDecode(posts.first.body)['sessionId'];
    expect(posts.every((r) => jsonDecode(r.body)['sessionId'] == id), isTrue);
    expect(
      posts.every((r) => !jsonDecode(r.body).containsKey('destinationNodeId')),
      isTrue,
    );
    final successfulCount = posts.length;
    recordPublishedScan(session, service: service);
    await h.scanned();
    expect(requests.where((r) => r.method == 'POST').length, successfulCount);
    final target = session.map.destinationNodes.first;
    final route = session.map.routeToNode(
      session.startKey,
      target.nodeId,
      target.floorId,
    );
    await h.select(route);
    await h.start(route);
    await h.start(route);
    expect(
      requests.where((r) => r.url.path.endsWith('/$id/start')),
      hasLength(1),
    );
    expect(h.ended, isFalse);
    await h.finish('Completed');
    await h.finish('Cancelled');
    expect(h.ended, isTrue);
    expect(
      requests.where((r) => r.method == 'PUT' && r.url.path.endsWith('/$id')),
      hasLength(1),
    );
  });
  test('Guest and changed account never receive private writes; cancelled scan needs no destination', () async {
    final f = PublishedMapFixture(await cleanupTestImage());
    final session = await f.api.loadQr(f.payload);
    var calls = 0;
    final service = NavigationHistoryService(
      client: MockClient((r) async {
        calls++;
        return json({});
      }),
    );
    AuthSession.clear();
    recordPublishedScan(session, service: service);
    await session.map.historySession!.scanned();
    expect(calls, 0);
    final another = await f.api.loadQr(f.payload);
    AuthSession.accessToken = 'a';
    recordPublishedScan(another, service: service);
    await another.map.historySession!.scanned();
    expect(calls, 1);
    AuthSession.accessToken = 'b';
    await another.map.historySession!.finish('Cancelled');
    expect(calls, 1);
  });
  testWidgets(
    'Home Recent and History query same source, refresh after scan, clear immediately on account switch',
    (t) async {
      AuthSession.accessToken = 'a';
      var rows = <Map<String, dynamic>>[];
      var gets = 0;
      final service = NavigationHistoryService(
        client: MockClient((r) async {
          expect(r.url.path, contains('/me/navigation-history'));
          gets++;
          if (r.headers['Authorization'] == 'Bearer b') return json([]);
          return json(rows);
        }),
      );
      await t.pumpWidget(MaterialApp(home: HomePage(historyService: service)));
      await t.pumpAndSettle();
      expect(gets, 1);
      rows = [
        {
          'id': 'id',
          'mapName': 'Private scan A',
          'startName': 'QR Start',
          'destinationName': '',
          'startedAtUtc': '2026-10-26T00:00:00Z',
          'scannedAtUtc': '2026-10-26T00:00:00Z',
          'status': 'Scanned',
        },
      ];
      NavigationHistoryService.changed();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pump(const Duration(milliseconds: 100));
      await t.pumpAndSettle();
      expect(gets, greaterThan(1));
      expect(
        find.text('Private scan A'),
        findsOneWidget,
        reason: t
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join(' / '),
      );
      await t.scrollUntilVisible(
        find.text('Private scan A'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Chưa chọn điểm đến'), findsOneWidget);
      expect(gets, greaterThan(1));
      AuthSession.accessToken = 'b';
      await t.pumpAndSettle();
      expect(find.text('Private scan A'), findsNothing);
      await t.pumpWidget(MaterialApp(home: HistoryPage(service: service)));
      await t.pumpAndSettle();
      expect(find.text('Private scan A'), findsNothing);
    },
  );
}
