import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/admin/draft_map_editor.dart';
import 'package:waymark/features/admin/draft_recovery.dart';
import 'package:waymark/features/admin/admin_page_shell.dart';
import 'package:waymark/features/home/home_page.dart';
import 'package:waymark/models/account_profile.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/features/auth/login/login_page.dart';
import 'package:waymark/features/admin/map_builder_page.dart';

class _NoRecovery extends DraftRecovery {
  @override
  bool get supported => false;
}

void main() {
  tearDown(AuthSession.clear);
  testWidgets(
    'Login local Builder entry keeps session and never opens fake Admin metrics',
    (t) async {
      AuthSession.accessToken = 'keep-existing-session';
      await t.pumpWidget(const MaterialApp(home: LoginPage()));
      await t.pumpAndSettle();
      expect(
        find.text('Xem giao diện Admin demo (chưa đăng nhập)'),
        findsNothing,
      );
      await t.ensureVisible(find.text('Map Builder cục bộ • chưa lưu server'));
      await t.tap(find.text('Map Builder cục bộ • chưa lưu server'));
      await t.pumpAndSettle();
      expect(find.byType(AdminMapBuilderPage), findsOneWidget);
      expect(find.text('Tổng quan hệ thống'), findsNothing);
      expect(AuthSession.accessToken, 'keep-existing-session');
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'Creator drawer has Home/My Maps/QR and no active System Admin demo tools',
    (t) async {
      AuthSession.accessToken = 'a';
      AuthSession.profile = const AccountProfile(
        userName: 'Creator',
        displayName: 'Creator',
        email: null,
        emailVerified: false,
        roles: ['Creator'],
        canManageMaps: true,
      );
      await t.pumpWidget(
        const MaterialApp(
          home: AdminPageShell(title: 'Studio test', child: SizedBox()),
        ),
      );
      await t.tap(find.byTooltip('Menu WayMark'));
      await t.pumpAndSettle();
      expect(find.text('WayMark Studio'), findsOneWidget);
      expect(find.text('WayMark Admin'), findsNothing);
      for (final label in [
        'Trang chủ',
        'Bản đồ của tôi',
        'Tạo bản đồ mới',
        'Map Builder',
        'Quản lý QR',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Dashboard'), findsNothing);
      expect(find.text('Quản trị tài khoản / Site / role'), findsNothing);
      final token = AuthSession.accessToken;
      await t.tap(find.text('Trang chủ'));
      await t.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
      expect(AuthSession.accessToken, token);
    },
  );
  testWidgets(
    'Dirty Builder Home requires confirmation; cancel retains draft; approved exit returns same Home',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const MaterialApp(home: HomePage()));
      await t.pumpAndSettle();
      final navigator = Navigator.of(t.element(find.byType(HomePage)));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => DraftMapEditor(recovery: _NoRecovery()),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('new-local-map')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('create-local-map')));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Menu WayMark'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('studio-home')));
      await t.pumpAndSettle();
      expect(find.text('Rời bản nháp chưa xuất?'), findsOneWidget);
      expect(find.text('Lưu trước khi rời'), findsOneWidget);
      await t.tap(find.text('Giữ lại'));
      await t.pumpAndSettle();
      expect(find.byType(DraftMapEditor), findsOneWidget);
      await t.tap(find.byKey(const Key('studio-home')));
      await t.pumpAndSettle();
      await t.tap(find.text('Rời bản nháp'));
      await t.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(DraftMapEditor), findsNothing);
      expect(navigator.canPop(), isFalse);
    },
  );
}
