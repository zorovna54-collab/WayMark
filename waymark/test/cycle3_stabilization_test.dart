import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/navigation_history_service.dart';
import 'package:waymark/models/account_profile.dart';
import 'package:waymark/features/auth/logout.dart';
import 'package:waymark/features/auth/login/login_page.dart';
import 'package:waymark/features/admin/admin_page_shell.dart';
import 'package:waymark/features/admin/create_map_page.dart';
import 'package:waymark/features/home/home_page.dart';

void creator() {
  AuthSession.establish('fixture-A', 'Creator A');
  AuthSession.profile = const AccountProfile(
    userName: 'Creator A',
    displayName: 'A',
    email: 'a@example.invalid',
    emailVerified: false,
    roles: ['Creator'],
    canManageMaps: true,
  );
}

class _NoHistory extends NavigationHistoryService {
  @override
  Future<List<Map<String, dynamic>>> list() async => [];
}

void main() {
  setUp(creator);
  tearDown(AuthSession.clear);
  testWidgets('explicit logout still works for the current expired session', (
    t,
  ) async {
    AuthSession.rejectUnauthorized(
      AuthSession.accessToken,
      AuthSession.revision,
    );
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => confirmLogout(c),
              child: const Text('Logout expired'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Logout expired'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('confirm-logout')), findsOneWidget);
    await t.tap(find.byKey(const Key('confirm-logout')));
    await t.pumpAndSettle();
    expect(AuthSession.accessToken, isNull);
    expect(find.byType(LoginPage), findsOneWidget);
  });
  testWidgets('Studio drawer remains usable at 320px text2 short viewport', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 480);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: const AdminPageShell(title: 'Studio', child: SizedBox()),
      ),
    );
    await t.tap(find.byTooltip('Menu WayMark'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'logout modal supports Escape cancel without losing current session',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => confirmLogout(c),
                child: const Text('Open logout'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open logout'));
      await t.pumpAndSettle();
      expect(find.text('Giữ phiên'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(AuthSession.accessToken, 'fixture-A');
    },
  );
  testWidgets('old logout confirmation cannot end replacement session', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => confirmLogout(c),
              child: const Text('Logout A'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Logout A'));
    await t.pumpAndSettle();
    AuthSession.establish('fixture-B', 'B');
    await t.pumpAndSettle();
    final old = find.byKey(const Key('confirm-logout'));
    if (old.evaluate().isNotEmpty) {
      await t.tap(old);
      await t.pumpAndSettle();
    }
    expect(AuthSession.accessToken, 'fixture-B');
    expect(find.byType(LoginPage), findsNothing);
  });
  testWidgets(
    'drawer navigation awaiting confirmation cannot open A onboarding under B',
    (t) async {
      final confirm = Completer<bool>();
      await t.pumpWidget(
        MaterialApp(
          home: AdminPageShell(
            title: 'Studio',
            beforeNavigate: () => confirm.future,
            child: const Text('Editor retained'),
          ),
        ),
      );
      await t.tap(find.byTooltip('Menu WayMark'));
      await t.pumpAndSettle();
      await t.tap(find.text('Tạo bản đồ mới'));
      await t.pump();
      AuthSession.establish('fixture-B', 'B');
      await t.pump();
      confirm.complete(true);
      await t.pumpAndSettle();
      expect(find.byType(CreateMapPage), findsNothing);
      expect(find.text('Editor retained'), findsOneWidget);
    },
  );
  testWidgets(
    'open drawer updates account capabilities without stale Creator action',
    (t) async {
      await t.pumpWidget(
        const MaterialApp(
          home: AdminPageShell(title: 'Studio', child: SizedBox()),
        ),
      );
      await t.tap(find.byTooltip('Menu WayMark'));
      await t.pumpAndSettle();
      expect(find.text('Tạo bản đồ mới'), findsOneWidget);
      AuthSession.establish('fixture-B', 'B');
      await t.pumpAndSettle();
      expect(find.text('Tạo bản đồ mới'), findsNothing);
      expect(find.text('Creator / quản lý bản đồ'), findsNothing);
    },
  );
  testWidgets('Home profile is a named button, reachable by keyboard', (
    t,
  ) async {
    AuthSession.clear();
    final semantics = t.ensureSemantics();
    try {
      await t.pumpWidget(
        MaterialApp(home: HomePage(historyService: _NoHistory())),
      );
      await t.pumpAndSettle();
      expect(
        t.getSemantics(find.byKey(const Key('home-profile'))),
        matchesSemantics(
          label: 'Hồ sơ tài khoản',
          tooltip: 'Hồ sơ tài khoản',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasFocusAction: true,
          hasTapAction: true,
        ),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}
