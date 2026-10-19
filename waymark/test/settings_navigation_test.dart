import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/admin/settings_page.dart';
import 'package:waymark/features/home/home_page.dart';
import 'package:waymark/services/auth_session.dart';

void main() {
  setUp(() {
    AuthSession.accessToken = 'settings-test-token';
    AuthSession.username = 'settings-test-user';
  });
  tearDown(AuthSession.clear);

  void expectSession() {
    expect(AuthSession.accessToken, 'settings-test-token');
    expect(AuthSession.username, 'settings-test-user');
  }

  for (final systemBack in [false, true]) {
    testWidgets(
      'Settings pushed: ${systemBack ? 'system' : 'AppBar'} Back pops original route',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminSettingsPage(),
                    ),
                  ),
                  child: const Text('Original Home'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Original Home'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Quay lại'), findsOneWidget);
        expect(find.byTooltip('Menu quản trị'), findsOneWidget);
        if (systemBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.byTooltip('Quay lại'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(AdminSettingsPage), findsNothing);
        expect(find.text('Original Home'), findsOneWidget);
        expect(
          tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
          isFalse,
        );
        expectSession();
      },
    );

    testWidgets(
      'Standalone Settings: ${systemBack ? 'system' : 'AppBar'} Back replaces with one Home',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: AdminSettingsPage()));
        await tester.pumpAndSettle();
        if (systemBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.byTooltip('Quay lại'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(HomePage), findsOneWidget);
        expect(find.byType(AdminSettingsPage), findsNothing);
        expect(
          tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
          isFalse,
        );
        expectSession();
      },
    );
  }

  testWidgets(
    'Standalone Settings system Back closes drawer before returning Home',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AdminSettingsPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Menu quản trị'));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold)).isDrawerOpen,
        isTrue,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AdminSettingsPage), findsOneWidget);
      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold)).isDrawerOpen,
        isFalse,
      );
      expect(find.byType(HomePage), findsNothing);
      expectSession();
    },
  );
}
