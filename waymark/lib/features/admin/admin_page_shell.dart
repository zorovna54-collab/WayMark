import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../services/auth_session.dart';
import '../home/home_page.dart';
import '../history/history_page.dart';
import '../scanner/public_map_entry_page.dart';
import '../auth/login/login_page.dart';
import 'map_builder_page.dart';
import 'my_maps_page.dart';
import 'create_map_page.dart';
import 'settings_page.dart';

/// Capability-aware navigation only. Every API still enforces server policy.
class AdminPageShell extends StatelessWidget {
  const AdminPageShell({
    super.key,
    required this.title,
    required this.child,
    this.onBack,
    this.scaffoldKey,
    this.beforeNavigate,
  });
  final String title;
  final Widget child;
  final VoidCallback? onBack;
  final GlobalKey<ScaffoldState>? scaffoldKey;
  final Future<bool> Function()? beforeNavigate;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: AuthSession.changes,
    builder: (context, _, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final token = AuthSession.accessToken;
    final revision = AuthSession.revision;
    final profile = AuthSession.profile;
    final signedIn = AuthSession.accessToken != null;
    final editor = profile?.canEditMaps == true;
    final facility = profile?.canManageFacility == true;
    final system = profile?.isSystemAdmin == true;
    final items = <(String, IconData, Widget)>[
      if (editor) ...[
        ('Bản đồ của tôi', Icons.map_outlined, const MyMapsPage()),
        if (profile != null)
          (
            'Tạo bản đồ mới',
            Icons.add_location_alt_outlined,
            CreateMapPage(profile: profile),
          ),
        (
          'Map Builder',
          Icons.account_tree_outlined,
          const AdminMapBuilderPage(),
        ),
        ('Quản lý QR', Icons.qr_code_2, const MyMapsPage()),
        if (facility)
          (
            'Bản đồ Site được ủy quyền',
            Icons.domain_outlined,
            const MyMapsPage(),
          ),
      ] else ...[
        ('Quét QR', Icons.qr_code_scanner, const PublicMapEntryPage()),
        ('Lịch sử', Icons.history, const HistoryPage()),
        (
          'Bắt đầu tạo bản đồ',
          Icons.add_location_alt_outlined,
          profile == null ? const LoginPage() : CreateMapPage(profile: profile),
        ),
        (
          'Map Builder cục bộ',
          Icons.edit_location_alt_outlined,
          const AdminMapBuilderPage(),
        ),
      ],
      ('Cài đặt', Icons.settings_outlined, const AdminSettingsPage()),
    ];
    Future<void> go(Widget? page, {bool home = false}) async {
      if (!AuthSession.isCurrent(token, revision)) return;
      if (page is AdminMapBuilderPage && beforeNavigate != null) {
        Navigator.of(context).pop();
        return;
      }
      if (beforeNavigate != null && !await beforeNavigate!()) return;
      if (!context.mounted || !AuthSession.isCurrent(token, revision)) return;
      final navigator = Navigator.of(context);
      navigator.pop(); // This callback is only invoked by an open Drawer item.
      if (home) {
        final existing = HomePage.activeRoute;
        if (existing != null && existing.isActive) {
          navigator.popUntil((route) => identical(route, existing));
          return;
        }
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const HomePage()),
        );
        return;
      }
      // Push retains the editor instance. Back returns to the exact same draft.
      navigator.push(MaterialPageRoute<void>(builder: (_) => page!));
    }

    final canBack = Navigator.of(context).canPop();
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.primary,
        leading: canBack || onBack != null
            ? IconButton(
                tooltip: 'Quay lại',
                icon: const Icon(Icons.arrow_back),
                onPressed:
                    onBack ??
                    () async {
                      if (beforeNavigate == null || await beforeNavigate!()) {
                        if (context.mounted &&
                            AuthSession.isCurrent(token, revision)) {
                          Navigator.maybePop(context);
                        }
                      }
                    },
              )
            : null,
        actions: [
          Builder(
            builder: (c) => IconButton(
              tooltip: 'Menu WayMark',
              onPressed: () => Scaffold.of(c).openDrawer(),
              icon: const Icon(Icons.menu),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(color: AppColors.primary),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text(
                      'WayMark Studio',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      system
                          ? 'System Admin'
                          : facility
                          ? 'Quản lý Site'
                          : editor
                          ? 'Creator / quản lý bản đồ'
                          : signedIn
                          ? 'Tài khoản người dùng'
                          : 'Visitor • bản nháp cục bộ',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              ListTile(
                key: const Key('studio-home'),
                leading: const Icon(Icons.home_outlined),
                title: const Text('Trang chủ'),
                onTap: () => go(null, home: true),
              ),
              for (final item in items)
                ListTile(
                  leading: Icon(item.$2, color: AppColors.accent),
                  title: Text(item.$1),
                  onTap: () => go(item.$3),
                ),
              if (system)
                const ListTile(
                  enabled: false,
                  leading: Icon(Icons.admin_panel_settings_outlined),
                  title: Text('Quản trị tài khoản / Site / role'),
                  subtitle: Text(
                    'Chưa khả dụng — chưa có API quản trị tương ứng',
                  ),
                ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'QR: mở bản đồ được cấp quyền → Server / Publish / QR. Không cấp quyền bằng menu.',
                ),
              ),
            ],
          ),
        ),
      ),
      body: child,
    );
  }
}
