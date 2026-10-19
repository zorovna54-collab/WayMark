import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'dashboard_page.dart';
import 'map_builder_page.dart';
import 'qr_manager_page.dart';
import 'settings_page.dart';

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

  static const _destinations = <(String, IconData, Widget)>[
    ('Dashboard', Icons.dashboard_outlined, AdminDashboardPage()),
    ('Map Builder', Icons.account_tree_outlined, AdminMapBuilderPage()),
    ('Quản lý QR', Icons.qr_code_2, AdminQrManagerPage()),
    ('Cài đặt', Icons.settings_outlined, AdminSettingsPage()),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    key: scaffoldKey,
    backgroundColor: AppColors.background,
    appBar: AppBar(
      title: Text(title),
      backgroundColor: AppColors.card,
      foregroundColor: AppColors.primary,
      leading: onBack == null
          ? null
          : IconButton(
              tooltip: 'Quay lại',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
      actions: onBack == null
          ? null
          : [
              Builder(
                builder: (context) => IconButton(
                  tooltip: 'Menu quản trị',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu),
                ),
              ),
            ],
    ),
    drawer: Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: AppColors.primary),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  'WayMark Admin',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            for (final item in _destinations)
              ListTile(
                leading: Icon(item.$2, color: AppColors.accent),
                title: Text(item.$1),
                onTap: () async {
                  if (beforeNavigate != null && !await beforeNavigate!()) {
                    return;
                  }
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute<void>(builder: (_) => item.$3),
                  );
                },
              ),
          ],
        ),
      ),
    ),
    body: child,
  );
}
