import 'package:flutter/material.dart';

import '../auth/workflow_recovery.dart';

import '../../models/account_profile.dart';
import '../../services/auth_api_service.dart';
import '../../services/auth_session.dart';
import '../../core/theme/app_colors.dart';
import '../auth/logout.dart';
import '../auth/account_security_page.dart';
import 'account_widgets.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.api});
  final AuthApiService? api;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final _api = widget.api ?? AuthApiService();
  final _name = TextEditingController();
  AccountProfile? _profile;
  String? _error;
  String? _success;
  bool _busy = true;
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
      _name.clear();
      _error = null;
      _success = null;
    });
    _load();
  }

  @override
  void dispose() {
    AuthSession.changes.removeListener(_sessionChanged);
    _name.dispose();
    super.dispose();
  }

  Future<void> _load({bool save = false}) async {
    final revision = AuthSession.revision;
    bool current() => mounted && revision == AuthSession.revision;
    final name = _name.text.trim();
    if (save &&
        (name.isEmpty ||
            name.length > 80 ||
            RegExp(r'[\x00-\x1F\x7F]').hasMatch(name))) {
      setState(() => _error = 'Tên hiển thị cần 1–80 ký tự hợp lệ.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      final profile = save
          ? await _api.updateProfile(name)
          : await _api.getProfile();
      if (!current()) return;
      setState(() {
        _profile = profile;
        _name.text = profile.displayName;
        if (save) _success = 'Đã lưu hồ sơ lên server.';
      });
    } catch (error) {
      if (current()) setState(() => _error = error.toString());
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Hồ sơ tài khoản')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SessionRecoveryButton(),
              if (_busy) const LinearProgressIndicator(),
              if (_success != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _success!,
                    key: const Key('profile-saved'),
                    style: const TextStyle(color: Colors.teal),
                  ),
                ),
              if (_error != null) ...[
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, key: const Key('profile-error')),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _load(),
                  child: const Text('Thử lại'),
                ),
              ],
              if (profile != null) ...[
                AccountHeader(
                  name: profile.displayName,
                  subtitle: '@${profile.userName}',
                ),
                AccountSection(
                  title: 'Thông tin cá nhân',
                  icon: Icons.person_outline,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            key: const Key('profile-display-name'),
                            controller: _name,
                            onChanged: (_) => setState(() => _success = null),
                            maxLength: 80,
                            enabled: !_busy,
                            decoration: const InputDecoration(
                              labelText: 'Tên hiển thị',
                              helperText: 'Tên đăng nhập không thay đổi',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                key: const Key('save-profile'),
                                onPressed: _busy
                                    ? null
                                    : () => _load(save: true),
                                icon: const Icon(Icons.check),
                                label: const Text('Lưu hồ sơ'),
                              ),
                              OutlinedButton(
                                key: const Key('cancel-profile'),
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                        _name.text = profile.displayName;
                                        _error = null;
                                      }),
                                child: const Text('Hủy thay đổi'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.mail_outline),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              AccountSecurityPage(api: _api, emailMode: true),
                        ),
                      ),
                      title: Text(
                        profile.email ?? 'Chưa có email',
                        key: const Key('profile-email'),
                      ),
                      subtitle: Text(
                        profile.emailVerified
                            ? 'Email đã xác nhận'
                            : 'Email chưa xác nhận',
                      ),
                    ),
                  ],
                ),
                AccountSection(
                  title: 'Vai trò và khả năng hiện có',
                  icon: Icons.verified_user_outlined,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vai trò hiệu lực: ${profile.roles.isEmpty ? 'User' : profile.roles.join(', ')}',
                            key: const Key('profile-roles'),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              if (profile.canCreatePersonalMaps)
                                const Chip(label: Text('Tạo bản đồ cá nhân')),
                              if (profile.canManageMaps)
                                const Chip(
                                  label: Text('Quản lý bản đồ được cấp quyền'),
                                ),
                              if (profile.canManageFacility)
                                const Chip(
                                  label: Text('Quản lý Site được ủy quyền'),
                                ),
                            ],
                          ),
                          const Text(
                            'Quyền do server cấp; xác nhận email không tự cấp quyền đại diện bệnh viện.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                AccountSection(
                  title: 'Bảo mật',
                  icon: Icons.lock_outline,
                  children: [
                    ListTile(
                      title: const Text('Bảo mật tài khoản'),
                      subtitle: const Text(
                        'Đổi mật khẩu của tài khoản hiện tại',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => AccountSecurityPage(api: _api),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (!_busy && _error == null)
                const Text('Chưa có thông tin tài khoản.'),
              if (AuthSession.accessToken != null)
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
    );
  }
}
