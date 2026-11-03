import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/auth/account_security_page.dart';
import 'package:waymark/features/history/history_page.dart';
import 'package:waymark/features/navigation/navigation_page.dart';
import 'package:waymark/features/navigation/local_map_navigation.dart';
import 'package:waymark/services/auth_api_service.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/navigation_history_service.dart';

import 'fixtures/published_map_fixture.dart';
import 'floor_image_cleanup_test.dart' show cleanupTestImage;

http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Future<void> readyMap(WidgetTester t, LocalMapNavigation map) async {
  await t.runAsync(() async {
    await precacheImage(map.image!, t.element(find.byType(NavigationPage)));
  });
  await t.pumpAndSettle();
}

void main() {
  tearDown(AuthSession.clear);
  testWidgets(
    'Change password sends only current/new password with JWT; clears session only on success',
    (t) async {
      AuthSession.accessToken = 'signed-user-a';
      AuthSession.username = 'User A';
      final requests = <http.Request>[];
      final api = AuthApiService(
        client: MockClient((r) async {
          requests.add(r);
          return json({});
        }),
      );
      await t.pumpWidget(MaterialApp(home: AccountSecurityPage(api: api)));
      expect(find.textContaining('Chưa có email:'), findsOneWidget);
      await t.enterText(
        find.byKey(const Key('current-password')),
        'Current-test1',
      );
      await t.enterText(find.byKey(const Key('new-password')), 'Next-test2');
      await t.enterText(
        find.byKey(const Key('confirm-password')),
        'Next-test2',
      );
      await t.tap(find.text('Đổi mật khẩu cho tài khoản này'));
      await t.pumpAndSettle();
      expect(requests.single.url.path, '/api/Auth/me/change-password');
      expect(requests.single.headers['Authorization'], 'Bearer signed-user-a');
      expect((jsonDecode(requests.single.body) as Map).keys.toSet(), {
        'currentPassword',
        'newPassword',
      });
      expect(AuthSession.accessToken, isNull);
      expect(find.text('Đăng nhập lại'), findsOneWidget);
    },
  );
  testWidgets(
    'Email request does not mark verified or replace current session; confirmation is separate',
    (t) async {
      AuthSession.accessToken = 'signed-a';
      final paths = <String>[];
      final api = AuthApiService(
        client: MockClient((r) async {
          paths.add(r.url.path);
          return json({});
        }),
      );
      await t.pumpWidget(
        MaterialApp(home: AccountSecurityPage(api: api, emailMode: true)),
      );
      await t.enterText(
        find.byKey(const Key('binding-email')),
        'new@example.invalid',
      );
      await t.enterText(
        find.byKey(const Key('current-password')),
        'Current-test1',
      );
      await t.tap(find.text('Gửi token xác minh email'));
      await t.pumpAndSettle();
      expect(AuthSession.accessToken, 'signed-a');
      expect(paths, ['/api/Auth/me/email/request']);
      expect(find.textContaining('Email chưa thay đổi'), findsOneWidget);
      await t.enterText(
        find.byKey(const Key('email-token')),
        'test-sink-token',
      );
      await t.ensureVisible(find.text('Xác minh email'));
      await t.tap(find.text('Xác minh email'));
      await t.pumpAndSettle();
      expect(paths.last, '/api/Auth/me/email/confirm');
      expect(AuthSession.accessToken, isNull);
    },
  );
  testWidgets(
    'Failed account write preserves session and input on small screen',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      AuthSession.accessToken = 'a';
      final api = AuthApiService(
        client: MockClient(
          (_) async => json({'message': 'Email đã được dùng'}, 409),
        ),
      );
      await t.pumpWidget(
        MaterialApp(home: AccountSecurityPage(api: api, emailMode: true)),
      );
      await t.enterText(
        find.byKey(const Key('binding-email')),
        'taken@example.invalid',
      );
      await t.enterText(
        find.byKey(const Key('current-password')),
        'Current-test1',
      );
      await t.ensureVisible(find.text('Gửi token xác minh email'));
      await t.tap(find.text('Gửi token xác minh email'));
      await t.pumpAndSettle();
      expect(AuthSession.accessToken, 'a');
      expect(find.text('taken@example.invalid'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'History begins once on Navigation, completes once, never auto advances',
    (t) async {
      final fixture = PublishedMapFixture(
        (await t.runAsync(cleanupTestImage))!,
      );
      final session = (await t.runAsync(
        () => fixture.api.loadQr(fixture.payload),
      ))!;
      final dest = session.map.destinationNodes.first;
      final route = session.map.routeToNode(
        session.startKey,
        dest.nodeId,
        dest.floorId,
      );
      var starts = 0, ends = 0;
      final service = NavigationHistoryService(
        client: MockClient((r) async {
          if (r.method == 'POST') {
            starts++;
            final body = jsonDecode(r.body) as Map;
            expect(body['qrToken'], fixture.token);
            expect(body.containsKey('userId'), isFalse);
          }
          if (r.method == 'PUT' &&
              !r.url.path.endsWith('/destination') &&
              !r.url.path.endsWith('/start')) {
            ends++;
            expect(jsonDecode(r.body)['status'], 'Completed');
          }
          return json({});
        }),
      );
      AuthSession.accessToken = 'a';
      await t.pumpWidget(
        MaterialApp(
          home: NavigationPage(
            route: route,
            localMap: session.map,
            historyService: service,
          ),
        ),
      );
      await readyMap(t, session.map);
      expect(starts, 1);
      await t.pump(const Duration(minutes: 3));
      expect(ends, 0);
      expect(starts, 1);
      for (var i = 0; i < route.edges.length; i++) {
        await t.tap(find.byKey(const Key('navigation-confirm')));
        await t.pumpAndSettle();
      }
      expect(ends, 0);
      expect(find.byKey(const Key('navigation-complete')), findsOneWidget);
      await t.tap(find.text('Kết thúc'));
      await t.pumpAndSettle();
      expect(ends, 1);
      await t.pumpWidget(const MaterialApp(home: SizedBox()));
      await t.pumpAndSettle();
      expect(ends, 1);
    },
  );
  testWidgets(
    'Abnormal Navigation disposal preserves unfinished session and guest never calls history API',
    (t) async {
      final fixture = PublishedMapFixture(
        (await t.runAsync(cleanupTestImage))!,
      );
      final session = (await t.runAsync(
        () => fixture.api.loadQr(fixture.payload),
      ))!;
      final dest = session.map.destinationNodes.first, calls = <String>[];
      final route = session.map.routeToNode(
        session.startKey,
        dest.nodeId,
        dest.floorId,
      );
      final service = NavigationHistoryService(
        client: MockClient((r) async {
          calls.add(
            r.method == 'PUT'
                ? (r.url.path.endsWith('/start')
                      ? 'start'
                      : r.url.path.endsWith('/destination')
                      ? 'destination'
                      : jsonDecode(r.body)['status'] as String)
                : r.method,
          );
          return json({});
        }),
      );
      AuthSession.accessToken = 'a';
      await t.pumpWidget(
        MaterialApp(
          home: NavigationPage(
            route: route,
            localMap: session.map,
            historyService: service,
          ),
        ),
      );
      await readyMap(t, session.map);
      await t.pumpWidget(const MaterialApp(home: SizedBox()));
      await t.pumpAndSettle();
      expect(calls, [
        'POST',
        'destination',
        'start',
      ]); // Abnormal disposal does not invent cancellation/completion.
      AuthSession.clear();
      calls.clear();
      await t.pumpWidget(
        MaterialApp(
          home: NavigationPage(
            route: route,
            localMap: session.map,
            historyService: service,
          ),
        ),
      );
      await readyMap(t, session.map);
      expect(calls, isEmpty);
      expect(find.textContaining('Guest: không lưu'), findsOneWidget);
    },
  );
  testWidgets(
    'History API failure does not block navigation or invent saved completion',
    (t) async {
      final fixture = PublishedMapFixture(
        (await t.runAsync(cleanupTestImage))!,
      );
      final session = (await t.runAsync(
        () => fixture.api.loadQr(fixture.payload),
      ))!;
      final dest = session.map.destinationNodes.first;
      AuthSession.accessToken = 'a';
      final service = NavigationHistoryService(
        client: MockClient((_) async => json({}, 503)),
      );
      await t.pumpWidget(
        MaterialApp(
          home: NavigationPage(
            route: session.map.routeToNode(
              session.startKey,
              dest.nodeId,
              dest.floorId,
            ),
            localMap: session.map,
            historyService: service,
          ),
        ),
      );
      await readyMap(t, session.map);
      expect(find.textContaining('Chưa đồng bộ lịch sử'), findsOneWidget);
      expect(
        t
            .widget<ElevatedButton>(find.byKey(const Key('navigation-confirm')))
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'History DELETE changes backend list, reload is empty, session change hides previous data',
    (t) async {
      AuthSession.accessToken = 'a';
      var deleted = false;
      final service = NavigationHistoryService(
        client: MockClient((r) async {
          expect(r.headers['Authorization'], 'Bearer a');
          if (r.method == 'DELETE') {
            deleted = true;
            return http.Response('', 204);
          }
          return json(
            deleted
                ? []
                : [
                    {
                      'id': 'test-id',
                      'mapName': 'Private A',
                      'startName': 'Door',
                      'destinationName': 'Clinic',
                      'startedAtUtc': '2026-10-25T00:00:00Z',
                      'status': 'Completed',
                    },
                  ],
          );
        }),
      );
      await t.pumpWidget(MaterialApp(home: HistoryPage(service: service)));
      await t.pumpAndSettle();
      expect(find.text('Private A'), findsOneWidget);
      await t.tap(find.text('Xóa mục'));
      await t.pumpAndSettle();
      await t.tap(find.text('Xóa'));
      await t.pumpAndSettle();
      expect(deleted, isTrue);
      expect(find.text('Private A'), findsNothing);
      expect(find.textContaining('Chưa có phiên'), findsOneWidget);
      AuthSession.clear();
      await t.pumpWidget(
        MaterialApp(
          home: HistoryPage(key: UniqueKey(), service: service),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Private A'), findsNothing);
    },
  );
  test(
    'History finish never writes into another account after logout/login',
    () async {
      final fixture = PublishedMapFixture(await cleanupTestImage());
      final session = await fixture.api.loadQr(fixture.payload);
      final dest = session.map.destinationNodes.first;
      final calls = <String>[];
      AuthSession.accessToken = 'a';
      final history = NavigationHistorySession(
        NavigationHistoryService(
          client: MockClient((r) async {
            calls.add(r.method);
            return json({});
          }),
        ),
        session.map,
        session.map.routeToNode(session.startKey, dest.nodeId, dest.floorId),
      );
      await history.start();
      AuthSession.accessToken = 'b';
      await history.finish('Completed');
      expect(calls, ['POST', 'PUT', 'PUT']);
    },
  );
}
