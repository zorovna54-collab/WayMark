import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/auth/password_reset_page.dart';
import 'package:waymark/services/auth_api_service.dart';
import 'package:waymark/services/auth_session.dart';

void main() {
  tearDown(AuthSession.clear);
  testWidgets(
    'Request -> emailed token -> reset -> Login; never creates an auth session',
    (t) async {
      var requests = 0, resets = 0;
      final api = AuthApiService(
        client: MockClient((request) async {
          expect(request.headers.containsKey('Authorization'), isFalse);
          final body = jsonDecode(request.body) as Map;
          expect(body['usernameOrEmail'], 'reader');
          if (request.url.path.endsWith('forgot-password')) {
            requests++;
          } else {
            resets++;
            expect(body['token'], 'isolated-email-token');
            expect(body['newPassword'], 'New-password1');
          }
          return http.Response('{}', 200);
        }),
      );
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PasswordResetPage(initialAccount: 'reader', api: api),
                  ),
                ),
                child: const Text('Login placeholder'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Login placeholder'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('request-reset')));
      await t.pumpAndSettle();
      expect(requests, 1);
      expect(find.textContaining('Nếu tài khoản có email'), findsOneWidget);
      await t.enterText(
        find.byKey(const Key('reset-token')),
        'isolated-email-token',
      );
      await t.enterText(
        find.byKey(const Key('reset-password')),
        'New-password1',
      );
      await t.enterText(find.byKey(const Key('reset-confirm')), 'mismatch');
      await t.scrollUntilVisible(
        find.byKey(const Key('submit-reset')),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('submit-reset')));
      await t.pumpAndSettle();
      expect(resets, 0);
      expect(find.byKey(const Key('reset-error')), findsOneWidget);
      await t.enterText(
        find.byKey(const Key('reset-confirm')),
        'New-password1',
      );
      await t.ensureVisible(find.byKey(const Key('submit-reset')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('submit-reset')));
      await t.pumpAndSettle();
      expect(resets, 1);
      expect(AuthSession.accessToken, isNull);
      expect(find.textContaining('Đã đặt lại mật khẩu'), findsOneWidget);
      await t.tap(find.text('Quay lại đăng nhập'));
      await t.pumpAndSettle();
      expect(find.text('Login placeholder'), findsOneWidget);
    },
  );
  testWidgets('Reset invalid/expired token error keeps input for retry', (
    t,
  ) async {
    final api = AuthApiService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'message': 'Token không hợp lệ hoặc hết hạn.'}),
          400,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    await t.pumpWidget(
      MaterialApp(
        home: PasswordResetPage(api: api, initialAccount: 'reader'),
      ),
    );
    await t.enterText(find.byKey(const Key('reset-token')), 'invalid-token');
    await t.enterText(find.byKey(const Key('reset-password')), 'New-password1');
    await t.enterText(find.byKey(const Key('reset-confirm')), 'New-password1');
    await t.ensureVisible(find.byKey(const Key('submit-reset')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('submit-reset')));
    await t.pumpAndSettle();
    expect(find.text('Token không hợp lệ hoặc hết hạn.'), findsOneWidget);
    expect(
      t
          .widget<TextField>(find.byKey(const Key('reset-token')))
          .controller!
          .text,
      'invalid-token',
    );
  });
}
