import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/admin/settings_page.dart';
import 'package:waymark/features/admin/create_map_page.dart';
import 'package:waymark/features/admin/draft_map_editor.dart';
import 'package:waymark/features/profile/profile_page.dart';
import 'package:waymark/services/auth_api_service.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/models/account_profile.dart';

http.Response response(Object json, [int status = 200]) => http.Response(
  jsonEncode(json),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, Object?> me({bool owns = false, bool admin = false}) => {
  'userName': 'regular-user',
  'displayName': 'Người dùng',
  'email': 'person@example.invalid',
  'emailVerified': false,
  'roles': admin ? ['Admin'] : [],
  'capabilities': {
    'canCreatePersonalMaps': true,
    'canManageMaps': owns,
    'canManageFacility': false,
    'isSystemAdmin': admin,
    'managedSites': [],
  },
};
void main() {
  setUp(() {
    AuthSession.accessToken = 'ordinary-user-test-token';
  });
  tearDown(() {
    AuthSession.clear();
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets(
    'Regular User Settings -> personal onboarding -> Builder -> refreshed My Maps without role grant',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      t.view.physicalSize = const Size(360, 760);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      var owns = false, creates = 0;
      final api = AuthApiService(
        client: MockClient((request) async {
          expect(
            request.headers['Authorization'],
            'Bearer ordinary-user-test-token',
          );
          if (request.url.path.endsWith('/Auth/me')) {
            return response(me(owns: owns));
          }
          expect(request.url.path, endsWith('/me/map-workspaces'));
          expect(request.method, 'POST');
          final form = jsonDecode(request.body) as Map;
          expect(form.containsKey('ownerId'), isFalse);
          expect(form.containsKey('siteId'), isFalse);
          expect(form.containsKey('role'), isFalse);
          expect(form['name'], 'Bản đồ mới');
          creates++;
          owns = true;
          return response({
            'id': '11111111-1111-4111-8111-111111111111',
            'name': form['name'],
            'version': 1,
            'siteId': 3,
            'buildingId': 3,
            'canPublish': true,
            'publicationKind': 'PersonalDemo',
            'updatedAt': '2026-10-25T00:00:00Z',
            'content': {
              'id': form['requestId'],
              'links': [],
              'info': {
                'purpose': form['purpose'],
                'placeName': form['placeName'],
                'kind': 'PersonalDemo',
              },
              'floors': [
                {
                  'id': '22222222-2222-4222-8222-222222222222',
                  'floorId': 21,
                  'name': form['floorName'],
                  'code': form['floorCode'],
                  'content': {
                    'schemaVersion': 1,
                    'imageAssetId': null,
                    'nodes': [],
                    'edges': [],
                    'places': [],
                    'transitions': [],
                  },
                },
              ],
            },
          }, 201);
        }),
      );
      await t.pumpWidget(MaterialApp(home: AdminSettingsPage(api: api)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('settings-my-maps')), findsNothing);
      await t.scrollUntilVisible(
        find.byKey(const Key('settings-create-map')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.byKey(const Key('settings-create-map')));
      await t.pumpAndSettle();
      expect(find.byType(CreateMapPage), findsOneWidget);
      await t.enterText(find.byKey(const Key('create-map-name')), 'Bản đồ mới');
      await t.enterText(
        find.byKey(const Key('create-map-place')),
        'Địa điểm thử',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const Key('create-map-submit')),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('create-map-submit')));
      await t.pumpAndSettle();
      expect(creates, 1);
      expect(find.byType(DraftMapEditor), findsOneWidget);
      expect(AuthSession.profile!.roles, isEmpty);
      expect(AuthSession.profile!.canManageMaps, isTrue);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byType(AdminSettingsPage), findsOneWidget);
      await t.scrollUntilVisible(
        find.byKey(const Key('settings-my-maps')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('settings-my-maps')), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
      expect(t.takeException(), isNull);
    },
  );
  test(
    'Client capability parsing never promotes a role string into capabilities',
    () {
      final json = me();
      json['roles'] = ['Admin', 'Creator'];
      json.remove('capabilities');
      final p = AccountProfile.fromJson(json);
      expect(p.canManageMaps, isFalse);
      expect(p.isSystemAdmin, isFalse);
    },
  );
  for (final admin in [false, true]) {
    testWidgets(
      'Small-screen Profile/Settings and server Admin capability=$admin',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final api = AuthApiService(
          client: MockClient((_) async => response(me(admin: admin))),
        );
        await t.pumpWidget(MaterialApp(home: AdminSettingsPage(api: api)));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.text(admin ? 'Quản trị hệ thống' : 'Ứng dụng và hỗ trợ'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.text('Quản trị hệ thống'),
          admin ? findsOneWidget : findsNothing,
        );
        await t.pumpWidget(MaterialApp(home: ProfilePage(api: api)));
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const Key('profile-display-name')),
          'Tên nháp',
        );
        await t.scrollUntilVisible(
          find.byKey(const Key('cancel-profile')),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await t.tap(find.byKey(const Key('cancel-profile')));
        await t.pumpAndSettle();
        expect(
          t
              .widget<TextField>(find.byKey(const Key('profile-display-name')))
              .controller!
              .text,
          'Người dùng',
        );
        expect(t.takeException(), isNull);
      },
    );
  }
  test(
    'Forgot-password uses anonymous reset route, keeps 403 distinct from SMTP',
    () async {
      final api = AuthApiService(
        client: MockClient((r) async {
          expect(r.method, 'POST');
          expect(r.url.path, endsWith('/api/Auth/forgot-password'));
          expect(r.headers.containsKey('Authorization'), isFalse);
          return http.Response('Forbidden', 403);
        }),
      );
      await expectLater(
        api.requestPasswordReset(usernameOrEmail: 'test@example.invalid'),
        throwsA(
          isA<AuthApiException>()
              .having((e) => e.statusCode, 'status', 403)
              .having(
                (e) => e.message,
                'message',
                contains('không cần đăng nhập'),
              ),
        ),
      );
    },
  );
}
