import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/admin/settings_page.dart';
import 'package:waymark/features/auth/login/login_page.dart';
import 'package:waymark/features/home/home_page.dart';
import 'package:waymark/features/profile/profile_page.dart';
import 'package:waymark/services/auth_api_service.dart';
import 'package:waymark/services/auth_session.dart';

http.Response jsonResponse(Object value, [int code = 200]) => http.Response(
  jsonEncode(value),
  code,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, Object?> profile(String name, [List<String> roles = const []]) => {
  'userName': 'reader',
  'displayName': name,
  'email': 'reader@example.invalid',
  'emailVerified': false,
  'roles': roles,
  'capabilities': {
    'canCreatePersonalMaps': true,
    'canManageMaps': roles.isNotEmpty,
    'canManageFacility': false,
    'isSystemAdmin': roles.contains('Admin'),
    'managedSites': [],
  },
};

void main() {
  setUp(() {
    AuthSession.accessToken = 'test-only-token';
    AuthSession.username = 'reader';
  });
  tearDown(AuthSession.clear);
  testWidgets(
    'Profile load/save/reopen/logout uses API and clears protected stack',
    (t) async {
      var name = 'Reader';
      final api = AuthApiService(
        client: MockClient((request) async {
          expect(request.url.path, endsWith('/Auth/me'));
          expect(request.headers['Authorization'], 'Bearer test-only-token');
          if (request.method == 'PUT') {
            final body = jsonDecode(request.body) as Map;
            expect(body.keys, ['displayName']);
            name = body['displayName'] as String;
          }
          return jsonResponse(profile(name, ['Creator']));
        }),
      );
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Open profile'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ProfilePage(api: api),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open profile'));
      await t.pumpAndSettle();
      expect(find.text('reader@example.invalid'), findsOneWidget);
      expect(find.textContaining('Creator'), findsOneWidget);
      expect(find.text('Email chưa xác nhận'), findsOneWidget);
      await t.enterText(
        find.byKey(const Key('profile-display-name')),
        'Tên mới',
      );
      await t.tap(find.byKey(const Key('save-profile')));
      await t.pumpAndSettle();
      expect(name, 'Tên mới');
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.text('Open profile'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(find.byKey(const Key('profile-display-name')))
            .controller!
            .text,
        'Tên mới',
      );
      await t.scrollUntilVisible(
        find.byKey(const Key('logout')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('logout')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('confirm-logout')));
      await t.pumpAndSettle();
      expect(AuthSession.accessToken, isNull);
      expect(AuthSession.profile, isNull);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(t.state<NavigatorState>(find.byType(Navigator)).canPop(), isFalse);
      await expectLater(api.getProfile(), throwsA(isA<AuthApiException>()));
    },
  );
  testWidgets(
    'Profile offline/retry and expired session show actionable errors',
    (t) async {
      var status = 503;
      final api = AuthApiService(
        client: MockClient(
          (_) async => jsonResponse(
            status == 200
                ? profile('Reader')
                : {'message': 'Server chưa sẵn sàng'},
            status,
          ),
        ),
      );
      await t.pumpWidget(MaterialApp(home: ProfilePage(api: api)));
      await t.pumpAndSettle();
      expect(find.text('Server chưa sẵn sàng'), findsOneWidget);
      status = 401;
      await t.tap(find.text('Thử lại'));
      await t.pumpAndSettle();
      expect(find.textContaining('hết hạn'), findsOneWidget);
      expect(AuthSession.expired, isTrue);
      status = 200;
      await t.tap(find.text('Thử lại'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('profile-display-name')), findsNothing);
      // A rejected credential must not be reused as an implicit refresh.
      AuthSession.establish('renewed-fixture-token', 'reader');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('profile-display-name')), findsOneWidget);
    },
  );
  for (final roles in [
    <String>[],
    ['Creator'],
    ['SiteManager'],
    ['Admin'],
  ]) {
    testWidgets('Settings actual role $roles controls Map Builder entry', (
      t,
    ) async {
      final api = AuthApiService(
        client: MockClient((_) async => jsonResponse(profile('Reader', roles))),
      );
      await t.pumpWidget(MaterialApp(home: AdminSettingsPage(api: api)));
      await t.pumpAndSettle();
      expect(
        find.byKey(const Key('settings-my-maps')),
        roles.isEmpty ? findsNothing : findsOneWidget,
      );
      expect(find.text('Lưu cấu hình'), findsNothing);
      expect(find.text('Hiển thị đường đi AR'), findsNothing);
    });
  }
  testWidgets(
    'Guest Settings connection probe uses no JWT and reports offline',
    (t) async {
      AuthSession.clear();
      var offline = false;
      final api = AuthApiService(
        client: MockClient((request) async {
          expect(request.headers.containsKey('Authorization'), isFalse);
          if (offline) throw http.ClientException('offline');
          return http.Response('', 401);
        }),
      );
      await t.pumpWidget(MaterialApp(home: AdminSettingsPage(api: api)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('settings-my-maps')), findsNothing);
      await t.tap(find.byKey(const Key('check-api')));
      await t.pumpAndSettle();
      expect(find.textContaining('HTTP 401'), findsOneWidget);
      offline = true;
      await t.tap(find.byKey(const Key('check-api')));
      await t.pumpAndSettle();
      expect(find.textContaining('Không kết nối được API'), findsOneWidget);
    },
  );
  test(
    'Late profile response after logout cannot recreate session or roles',
    () async {
      final pending = Completer<http.Response>();
      final api = AuthApiService(client: MockClient((_) => pending.future));
      final request = api.getProfile();
      AuthSession.clear();
      pending.complete(jsonResponse(profile('Old admin', ['Admin'])));
      await expectLater(request, throwsA(isA<AuthApiException>()));
      expect(AuthSession.accessToken, isNull);
      expect(AuthSession.profile, isNull);
    },
  );
  testWidgets('Home avatar opens Profile for logged-in user', (t) async {
    await t.pumpWidget(const MaterialApp(home: HomePage()));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('home-profile')));
    await t.pumpAndSettle();
    expect(find.byType(ProfilePage), findsOneWidget);
  });
}
