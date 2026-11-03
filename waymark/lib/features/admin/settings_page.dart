import 'package:flutter/material.dart';

import '../auth/workflow_recovery.dart';

import '../../core/theme/app_colors.dart';
import '../../models/account_profile.dart';
import '../../services/auth_api_service.dart';
import '../../services/auth_session.dart';
import '../../services/published_map_api_service.dart';
import '../auth/login/login_page.dart';
import '../auth/register/register_page.dart';
import '../auth/account_security_page.dart';
import '../auth/logout.dart';
import '../home/home_page.dart';
import '../profile/profile_page.dart';
import '../profile/account_widgets.dart';
import '../scanner/public_map_entry_page.dart';
import 'create_map_page.dart';
import 'my_maps_page.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key, this.api});
  final AuthApiService? api;
  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  late final _api = widget.api ?? AuthApiService();
  AccountProfile? _profile;
  String? _error, _connection;
  bool _loading = false, _checking = false;
  @override
  void initState() {
    super.initState();
    AuthSession.changes.addListener(_sessionChanged);
    _load();
  }

  void _sessionChanged() {
    if (!mounted) return;
    setState(() {
      _profile = null;
      _error = null;
      _connection = null;
    });
    _load();
  }

  @override
  void dispose() {
    AuthSession.changes.removeListener(_sessionChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final revision = AuthSession.revision;
    bool current() => mounted && revision == AuthSession.revision;
    if (AuthSession.accessToken == null) {
      if (mounted) {
        setState(() {
          _profile = null;
          _loading = false;
          _error = null;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await _api.getProfile();
      if (current()) setState(() => _profile = profile);
    } catch (error) {
      if (current()) {
        setState(() {
          _profile = null;
          _error = error.toString();
        });
      }
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
    if (mounted) await _load();
  }

  Future<void> _create() async {
    if (_profile == null) await _load();
    if (!mounted || _profile == null) return;
    await _open(
      CreateMapPage(
        profile: _profile!,
        auth: _api,
        maps: PublishedMapApiService(client: _api.client),
      ),
    );
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _connection = null;
    });
    try {
      final result = await _api.checkConnection();
      if (mounted) setState(() => _connection = result);
    } catch (error) {
      if (mounted) setState(() => _connection = error.toString());
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _goBack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomePage()),
      );
    }
  }

  Widget _tile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback? action, {
    Key? key,
  }) => ListTile(
    key: key,
    leading: Icon(icon, color: AppColors.primary),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: action == null ? null : const Icon(Icons.chevron_right),
    onTap: action,
  );
  @override
  Widget build(BuildContext context) {
    final loggedIn = AuthSession.accessToken != null;
    final profile = _profile;
    final maps = PublishedMapApiService(client: _api.client);
    return PopScope<Object?>(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Cài đặt'),
          leading: IconButton(
            tooltip: 'Quay lại',
            onPressed: _goBack,
            icon: const Icon(Icons.arrow_back),
          ),
          actions: [
            IconButton(
              tooltip: 'Làm mới quyền',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                AccountHeader(
                  name:
                      profile?.displayName ??
                      (loggedIn ? 'Tài khoản WayMark' : 'Chào bạn'),
                  subtitle: loggedIn
                      ? 'Thông tin tài khoản và quyền hiện tại'
                      : 'Quét QR để tìm đường, không cần tài khoản',
                ),
                if (_loading) const LinearProgressIndicator(),
                const SessionRecoveryButton(),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  TextButton(
                    onPressed: _loading ? null : _load,
                    child: const Text('Tải lại tài khoản'),
                  ),
                ],
                AccountSection(
                  title: 'Tài khoản',
                  icon: Icons.person_outline,
                  children: [
                    if (loggedIn) ...[
                      _tile(
                        Icons.account_circle_outlined,
                        'Hồ sơ tài khoản',
                        profile?.email ??
                            'Thông tin, vai trò và trạng thái email',
                        () => _open(ProfilePage(api: _api)),
                      ),
                      _tile(
                        Icons.lock_outline,
                        'Bảo mật tài khoản',
                        'Đổi mật khẩu của tài khoản hiện tại',
                        () => _open(AccountSecurityPage(api: _api)),
                      ),
                    ] else ...[
                      _tile(
                        Icons.login,
                        'Đăng nhập',
                        'Quản lý thông tin và bản đồ riêng',
                        () => _open(const LoginPage()),
                      ),
                      _tile(
                        Icons.person_add_outlined,
                        'Đăng ký',
                        'Tạo tài khoản WayMark',
                        () => _open(const RegisterPage()),
                      ),
                    ],
                  ],
                ),
                if (loggedIn)
                  AccountSection(
                    title: 'Bản đồ của bạn',
                    icon: Icons.map_outlined,
                    children: [
                      _tile(
                        Icons.add_location_alt_outlined,
                        'Bắt đầu tạo bản đồ',
                        'Tạo bản nháp trong không gian riêng của bạn',
                        _loading ? null : _create,
                        key: const Key('settings-create-map'),
                      ),
                      if (profile?.canManageMaps == true)
                        _tile(
                          Icons.folder_open_outlined,
                          'Bản đồ của tôi / Map Builder',
                          'Bản nháp, phiên bản đã xuất bản và QR được cấp quyền',
                          () => _open(MyMapsPage(api: maps)),
                          key: const Key('settings-my-maps'),
                        ),
                    ],
                  ),
                if (profile?.canManageFacility == true)
                  AccountSection(
                    title: 'Cơ sở được ủy quyền',
                    icon: Icons.domain_outlined,
                    children: [
                      for (final site in profile!.managedSites)
                        ListTile(
                          leading: const Icon(Icons.domain),
                          title: Text(site['name'] as String),
                          subtitle: const Text(
                            'Bạn đang được cấp quyền tại cơ sở này',
                          ),
                        ),
                      _tile(
                        Icons.map_outlined,
                        'Bản đồ được ủy quyền',
                        'Chỉ hiển thị bản đồ bạn được phép quản lý',
                        () => _open(MyMapsPage(api: maps)),
                      ),
                      const ListTile(
                        title: Text('Quản lý cộng tác viên'),
                        subtitle: Text(
                          'Chưa khả dụng — chưa có API cấp quyền tương ứng',
                        ),
                        enabled: false,
                      ),
                    ],
                  ),
                if (profile?.isSystemAdmin == true)
                  const AccountSection(
                    title: 'Quản trị hệ thống',
                    icon: Icons.admin_panel_settings_outlined,
                    children: [
                      ListTile(
                        title: Text('Quản trị tài khoản và phân quyền'),
                        subtitle: Text('Chưa khả dụng'),
                        enabled: false,
                      ),
                    ],
                  ),
                AccountSection(
                  title: 'Ứng dụng và hỗ trợ',
                  icon: Icons.help_outline,
                  children: [
                    _tile(
                      Icons.qr_code_scanner,
                      'Quét QR / Bản đồ công khai',
                      'Mở bản đồ đã xuất bản và tìm đường',
                      () => _open(const PublicMapEntryPage()),
                    ),
                    ListTile(
                      title: const Text('Kết nối API'),
                      subtitle: Text(AuthApiService.baseUrl),
                      trailing: _checking
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(),
                            )
                          : IconButton(
                              key: const Key('check-api'),
                              tooltip: 'Kiểm tra kết nối',
                              onPressed: _check,
                              icon: const Icon(Icons.refresh),
                            ),
                    ),
                    if (_connection != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_connection!, key: const Key('api-status')),
                      ),
                    const AboutListTile(
                      applicationName: 'WayMark',
                      applicationVersion: String.fromEnvironment(
                        'WAYMARK_APP_VERSION',
                        defaultValue: '1.0.0+1',
                      ),
                      icon: Icon(Icons.info_outline),
                      applicationLegalese: 'Phiên bản phát triển — bản đồ phải được xác minh tại thực địa.',
                    ),
                  ],
                ),
                if (loggedIn)
                  OutlinedButton.icon(
                    key: const Key('logout'),
                    onPressed: () => confirmLogout(context),
                    icon: const Icon(Icons.logout),
                    label: const Text('Đăng xuất'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
