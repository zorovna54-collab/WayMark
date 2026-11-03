import 'package:flutter/material.dart';

import '../../services/auth_api_service.dart';
import '../../services/auth_session.dart';
import 'logout.dart';
import 'workflow_recovery.dart';
import 'password_reset_page.dart';

/// Sensitive writes are bound to the signed subject, never an entered username.
class AccountSecurityPage extends StatefulWidget {
  const AccountSecurityPage({super.key, this.api, this.emailMode = false});
  final AuthApiService? api;
  final bool emailMode;
  @override
  State<AccountSecurityPage> createState() => _AccountSecurityPageState();
}

class _AccountSecurityPageState extends State<AccountSecurityPage> {
  final _owner = OwnerWorkflow();
  void _ownerChanged() {
    if (mounted) setState(() {});
  }

  late final _api = widget.api ?? AuthApiService();
  final _current = TextEditingController(),
      _next = TextEditingController(),
      _confirm = TextEditingController(),
      _email = TextEditingController(),
      _token = TextEditingController();
  String? _message, _error;
  bool _busy = false, _sent = false, _done = false;
  @override
  void initState() {
    super.initState();
    _owner.addListener(_ownerChanged);
    _email.text = AuthSession.profile?.email ?? '';
  }

  @override
  void dispose() {
    _owner.removeListener(_ownerChanged);
    _owner.dispose();
    for (final c in [_current, _next, _confirm, _email, _token]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit({bool confirmEmail = false}) async {
    if (_busy || !_owner.current) return;
    if ((!confirmEmail && _current.text.isEmpty) ||
        (!widget.emailMode &&
            (_next.text.length < 8 || _next.text != _confirm.text)) ||
        (widget.emailMode &&
            (!_email.text.contains('@') ||
                (confirmEmail && _token.text.trim().isEmpty)))) {
      setState(
        () => _error =
            'Kiểm tra email/token hoặc mật khẩu và xác nhận trùng khớp.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = _message = null;
    });
    try {
      await _owner.wait(
        _api.accountAction(
          widget.emailMode
              ? (confirmEmail ? 'email/confirm' : 'email/request')
              : 'change-password',
          widget.emailMode
              ? {
                  'email': _email.text.trim(),
                  if (confirmEmail)
                    'token': _token.text.trim()
                  else
                    'currentPassword': _current.text,
                }
              : {'currentPassword': _current.text, 'newPassword': _next.text},
        ),
      );
      if (!mounted) return;
      setState(() {
        _sent = widget.emailMode;
        _done = !widget.emailMode || confirmEmail;
        _message = _done
            ? 'Thay đổi thành công cho tài khoản hiện tại. Hãy đăng nhập lại.'
            : 'Đã gửi token xác minh tới email mới. Email chưa thay đổi; token có hạn 30 phút.';
        if (_done) {
          _current.clear();
          _next.clear();
          _confirm.clear();
          _token.clear();
          AuthSession.clear();
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      !_owner.current && (!_done || AuthSession.accessToken != null)
      ? WorkflowRecovery(workflow: _owner, api: _api)
      : PopScope<void>(
          canPop: !_done,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _done) logoutToLogin(context);
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                widget.emailMode
                    ? 'Liên kết / xác minh email'
                    : 'Đổi mật khẩu hiện tại',
              ),
            ),
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Tài khoản: ${AuthSession.profile?.userName ?? AuthSession.username ?? 'đã xác thực'}',
                ),
                const Text(
                  'Thao tác chỉ áp dụng tài khoản đang đăng nhập. Không gộp hoặc đổi tài khoản theo email nhập vào.',
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Text(_error!, key: const Key('account-security-error')),
                if (_message != null)
                  Text(_message!, key: const Key('account-security-message')),
                if (!_done) ...[
                  if (widget.emailMode)
                    TextField(
                      key: const Key('binding-email'),
                      controller: _email,
                      enabled: !_busy && !_sent,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email cần xác minh',
                      ),
                    ),
                  TextField(
                    key: const Key('current-password'),
                    controller: _current,
                    obscureText: true,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Mật khẩu hiện tại',
                    ),
                  ),
                  if (!widget.emailMode) ...[
                    TextField(
                      key: const Key('new-password'),
                      controller: _next,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Mật khẩu mới',
                      ),
                    ),
                    TextField(
                      key: const Key('confirm-password'),
                      controller: _confirm,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Nhập lại mật khẩu mới',
                      ),
                    ),
                  ],
                  FilledButton(
                    onPressed: _busy ? null : () => _submit(),
                    child: Text(
                      widget.emailMode
                          ? 'Gửi token xác minh email'
                          : 'Đổi mật khẩu cho tài khoản này',
                    ),
                  ),
                  if (_sent) ...[
                    TextField(
                      key: const Key('email-token'),
                      controller: _token,
                      obscureText: true,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Token xác minh trong email',
                      ),
                    ),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _submit(confirmEmail: true),
                      child: const Text('Xác minh email'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _sent = false;
                              _token.clear();
                            }),
                      child: const Text('Sửa địa chỉ email'),
                    ),
                  ],
                  if (!widget.emailMode) ...[
                    Text(
                      AuthSession.profile?.email == null
                          ? 'Chưa có email: hãy liên kết và xác minh trong Hồ sơ. Vẫn có thể đổi mật khẩu bằng mật khẩu hiện tại.'
                          : 'Quên mật khẩu hiện tại? Khôi phục theo email là luồng riêng.',
                    ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => PasswordResetPage(api: _api),
                        ),
                      ),
                      child: const Text('Khôi phục tài khoản theo email'),
                    ),
                  ],
                ] else
                  FilledButton(
                    onPressed: () => logoutToLogin(context),
                    child: const Text('Đăng nhập lại'),
                  ),
              ],
            ),
          ),
        );
}
