import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/admin/my_maps_page.dart';
import 'package:waymark/features/admin/draft_recovery.dart';
import 'package:waymark/features/admin/settings_page.dart';
import 'package:waymark/features/history/history_page.dart';
import 'package:waymark/features/profile/profile_page.dart';
import 'package:waymark/features/auth/login/login_page.dart';
import 'package:waymark/features/search/local_map_search_page.dart';
import 'package:waymark/services/auth_api_service.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/map_draft_api_service.dart';
import 'package:waymark/services/navigation_history_service.dart';
import 'package:waymark/services/published_map_api_service.dart';

import 'fixtures/published_map_fixture.dart';
import 'floor_image_cleanup_test.dart' show cleanupTestImage;

http.Response _json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);
Map<String, Object?> _map(String name) => {
  'id': '11111111-1111-4111-8111-111111111111',
  'name': name,
  'version': 1,
  'publishedVersion': null,
};

class _DelayedReader extends PublishedMapApiService {
  _DelayedReader(http.Client client) : super(client: client);
  final result = Completer<PublishedMapSession>();
  bool started = false;
  @override
  Future<PublishedMapSession> loadQr(String payload) {
    started = true;
    return result.future;
  }
}

class _ResumeService extends NavigationHistoryService {
  _ResumeService(this._maps);
  final PublishedMapApiService _maps;
  @override
  PublishedMapApiService get maps => _maps;
}

void main() {
  setUp(AuthSession.clear);
  tearDown(AuthSession.clear);

  test(
    'replacing a token clears cached identity before local recovery can use it',
    () {
      AuthSession.establish('a', 'private-owner-a');
      expect(
        DraftRecovery.ownerScope('fixture-api'),
        contains('private-owner-a'),
      );
      AuthSession.accessToken = 'b';
      expect(AuthSession.username, isNull);
      expect(AuthSession.profile, isNull);
      expect(DraftRecovery.ownerScope('fixture-api'), isNull);
    },
  );

  testWidgets(
    'leaving Login prevents a late response from signing in silently',
    (t) async {
      final response = Completer<http.Response>();
      final api = AuthApiService(client: MockClient((_) => response.future));
      await t.pumpWidget(MaterialApp(home: LoginPage(api: api)));
      await t.enterText(find.byType(TextField).at(0), 'a');
      await t.enterText(find.byType(TextField).at(1), 'test-only');
      await t.ensureVisible(find.text('Đăng nhập'));
      await t.tap(find.text('Đăng nhập'));
      await t.pump();
      await t.pumpWidget(const SizedBox());
      response.complete(_json({'accessToken': 'late', 'username': 'a'}));
      await t.pumpAndSettle();
      expect(AuthSession.accessToken, isNull);
      expect(t.takeException(), isNull);
    },
  );

  test(
    'a failed newer login does not allow an older intent to sign in',
    () async {
      final older = Completer<http.Response>();
      final api = AuthApiService(
        client: MockClient((r) async {
          if (jsonDecode(r.body)['username'] == 'a') return older.future;
          return http.Response('{}', 401);
        }),
      );
      final a = api.login(username: 'a', password: 'test-only');
      final rejected = expectLater(a, throwsA(isA<AuthApiException>()));
      await expectLater(
        api.login(username: 'b', password: 'test-only'),
        throwsA(isA<AuthApiException>()),
      );
      older.complete(_json({'accessToken': 'late', 'username': 'a'}));
      await rejected;
      expect(AuthSession.accessToken, isNull);
    },
  );

  test(
    'pending login cannot restore a session after explicit logout',
    () async {
      final response = Completer<http.Response>();
      final api = AuthApiService(client: MockClient((_) => response.future));
      final login = api.login(username: 'a', password: 'test-only');
      final rejected = expectLater(login, throwsA(isA<AuthApiException>()));
      AuthSession.clear();
      response.complete(_json({'accessToken': 'late-a', 'username': 'a'}));
      await rejected;
      expect(AuthSession.accessToken, isNull);
    },
  );

  test(
    'latest login intent wins even when the older reply arrives last',
    () async {
      final older = Completer<http.Response>();
      final newer = Completer<http.Response>();
      final api = AuthApiService(
        client: MockClient(
          (r) => jsonDecode(r.body)['username'] == 'a'
              ? older.future
              : newer.future,
        ),
      );
      final a = api.login(username: 'a', password: 'test-only');
      final rejected = expectLater(a, throwsA(isA<AuthApiException>()));
      final b = api.login(username: 'b', password: 'test-only');
      newer.complete(_json({'accessToken': 'token-b', 'username': 'b'}));
      await b;
      older.complete(_json({'accessToken': 'token-a', 'username': 'a'}));
      await rejected;
      expect(AuthSession.accessToken, 'token-b');
      expect(AuthSession.username, 'b');
    },
  );

  test(
    'session listeners observe token and account metadata atomically',
    () async {
      AuthSession.accessToken = 'old';
      AuthSession.username = 'old-user';
      final seen = <String?>[];
      void changed() => seen.add(AuthSession.username);
      AuthSession.changes.addListener(changed);
      try {
        final api = AuthApiService(
          client: MockClient(
            (_) async => _json({'accessToken': 'new', 'username': 'new-user'}),
          ),
        );
        await api.login(username: 'new-user', password: 'test-only');
        expect(seen, ['new-user']);
        AuthSession.clear();
        expect(seen.last, isNull);
      } finally {
        AuthSession.changes.removeListener(changed);
      }
    },
  );

  for (final kind in ['published private', 'draft private']) {
    test(
      '$kind rejects reply after account switch, including token reuse',
      () async {
        AuthSession.accessToken = 'a';
        final response = Completer<http.Response>();
        final client = MockClient((_) => response.future);
        final pending = kind == 'published private'
            ? PublishedMapApiService(client: client).list()
            : MapDraftApiService(client: client).metadata(10);
        final rejected = expectLater(
          pending,
          throwsA(isA<MapDraftApiException>()),
        );
        AuthSession.clear();
        AuthSession.accessToken = 'a';
        response.complete(
          _json(
            kind == 'published private'
                ? []
                : {
                    'id': '11111111-1111-4111-8111-111111111111',
                    'floorId': 10,
                    'siteId': 1,
                    'buildingId': 1,
                    'version': 1,
                    'status': 'Draft',
                    'updatedAt': '2026-10-30T00:00:00Z',
                  },
          ),
        );
        await rejected;
      },
    );
  }

  test(
    'public reads remain anonymous and valid across account changes',
    () async {
      AuthSession.accessToken = 'a';
      final response = Completer<http.Response>();
      final api = PublishedMapApiService(
        client: MockClient((r) {
          expect(r.headers.containsKey('Authorization'), isFalse);
          return response.future;
        }),
      );
      final pending = api.json('public/test');
      AuthSession.accessToken = 'b';
      response.complete(_json({'ok': true}));
      expect(await pending, {'ok': true});
    },
  );

  test('stale save is uncertain and is never retried automatically', () async {
    AuthSession.accessToken = 'a';
    final response = Completer<http.Response>();
    var calls = 0;
    final api = PublishedMapApiService(
      client: MockClient((_) {
        calls++;
        return response.future;
      }),
    );
    final pending = api.request(
      'admin/map-projects',
      method: 'POST',
      private: true,
      body: {},
    );
    final rejected = expectLater(
      pending,
      throwsA(
        isA<MapDraftApiException>().having(
          (e) => e.uncertain,
          'uncertain outcome',
          isTrue,
        ),
      ),
    );
    AuthSession.accessToken = 'b';
    response.complete(_json({'id': 'old-account-result'}));
    await rejected;
    expect(calls, 1);
  });

  testWidgets(
    'My Maps clears private rows and reloads for the current account',
    (t) async {
      AuthSession.accessToken = 'a';
      final api = PublishedMapApiService(
        client: MockClient(
          (r) async => _json(
            r.headers['Authorization'] == 'Bearer a' ? [_map('Private A')] : [],
          ),
        ),
      );
      await t.pumpWidget(MaterialApp(home: MyMapsPage(api: api)));
      await t.pumpAndSettle();
      expect(find.text('Private A'), findsOneWidget);
      AuthSession.accessToken = 'b';
      await t.pumpAndSettle();
      expect(find.text('Private A'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );

  for (final profile in [true, false]) {
    testWidgets(
      'private account view ${profile ? 'Profile' : 'Settings'} clears cached owner on switch',
      (t) async {
        AuthSession.accessToken = 'a';
        final api = AuthApiService(
          client: MockClient((r) async {
            final name = r.headers['Authorization'] == 'Bearer a'
                ? 'Private A'
                : 'Current B';
            return _json({
              'userName': name,
              'displayName': name,
              'email': null,
              'emailVerified': false,
              'roles': <String>[],
            });
          }),
        );
        await t.pumpWidget(
          MaterialApp(
            home: profile ? ProfilePage(api: api) : AdminSettingsPage(api: api),
          ),
        );
        await t.pumpAndSettle();
        expect(find.textContaining('Private A'), findsWidgets);
        AuthSession.accessToken = 'b';
        await t.pumpAndSettle();
        expect(find.textContaining('Private A'), findsNothing);
        expect(find.textContaining('Current B'), findsWidgets);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('My Maps ignores a previous account list that completes late', (
    t,
  ) async {
    AuthSession.accessToken = 'a';
    final response = Completer<http.Response>();
    final api = PublishedMapApiService(
      client: MockClient(
        (r) => r.headers['Authorization'] == 'Bearer a'
            ? response.future
            : Future.value(_json([_map('Current B')])),
      ),
    );
    await t.pumpWidget(MaterialApp(home: MyMapsPage(api: api)));
    await t.pump();
    AuthSession.accessToken = 'b';
    await t.pump();
    response.complete(_json([_map('Private A')]));
    await t.pumpAndSettle();
    expect(find.text('Private A'), findsNothing);
    expect(find.text('Current B'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'History resume cannot record an old account trip in the new account',
    (t) async {
      AuthSession.accessToken = 'a';
      final fixture = PublishedMapFixture(
        (await t.runAsync(cleanupTestImage))!,
      );
      final session = (await t.runAsync(
        () => fixture.api.loadQr(fixture.payload),
      ))!;
      var writes = 0;
      final reader = _DelayedReader(
        MockClient((r) async {
          if (r.method != 'GET') {
            writes++;
            return _json({});
          }
          if (r.url.path.endsWith('/resume')) {
            return _json({'payload': fixture.payload});
          }
          return _json(
            r.headers['Authorization'] == 'Bearer a'
                ? [
                    {
                      'id': 'history-a',
                      'mapName': 'Private trip A',
                      'startName': 'QR start',
                      'destinationName': '',
                      'status': 'Scanned',
                      'scannedAtUtc': '2026-10-30T00:00:00Z',
                    },
                  ]
                : [],
          );
        }),
      );
      final service = _ResumeService(reader);
      await t.pumpWidget(MaterialApp(home: HistoryPage(service: service)));
      await t.pumpAndSettle();
      await t.tap(find.text('Tính tuyến mới'));
      await t.pumpAndSettle();
      await t.tap(find.text('Đúng vị trí bắt đầu'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 10));
      expect(reader.started, isTrue);
      AuthSession.accessToken = 'b';
      await t.pump();
      reader.result.complete(session);
      await t.pumpAndSettle();
      expect(writes, 0);
      expect(find.byType(LocalMapSearchPage), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
}
