import 'package:flutter/material.dart';

import '../../services/auth_api_service.dart';

class PasswordResetPage extends StatefulWidget {
  const PasswordResetPage({super.key, this.initialAccount = '', this.api});
  final String initialAccount;
  final AuthApiService? api;
  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  late final _api = widget.api ?? AuthApiService();
  late final _account = TextEditingController(text: widget.initialAccount);
  final _token = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  String? _error, _message;
  bool _busy = false, _done = false;
  @override
  void dispose() {
    _account.dispose();
    _token.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _send({bool reset = false}) async {
    if (_account.text.trim().isEmpty ||
        (reset &&
            (_token.text.trim().isEmpty ||
                _password.text.length < 8 ||
                _password.text != _confirm.text))) {
      setState(
        () => _error = reset
            ? 'Nhập tài khoản, token, mật khẩu từ 8 ký tự và xác nhận khớp.'
            : 'Nhập username hoặc email.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = _message = null;
    });
    try {
      if (reset) {
        await _api.resetPassword(
          usernameOrEmail: _account.text,
          token: _token.text,
          newPassword: _password.text,
        );
      } else {
        await _api.requestPasswordReset(usernameOrEmail: _account.text);
      }
      if (mounted) {
        setState(() {
          _done = reset;
          _message = reset
              ? 'Đã đặt lại mật khẩu. Quay lại đăng nhập với mật khẩu mới.'
              : 'Đã nhận yêu cầu. Nếu tài khoản có email và dịch vụ gửi thư hoạt động, hãy kiểm tra hộp thư và dán token bên dưới.';
          if (reset) {
            _token.clear();
            _password.clear();
            _confirm.clear();
          }
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Đặt lại mật khẩu')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Khôi phục theo username/email: chỉ đặt lại mật khẩu của tài khoản sở hữu địa chỉ được nhập, không phải tài khoản khác đang đăng nhập. Không xác nhận email có tồn tại hay không.',
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Text(
            _error!,
            key: const Key('reset-error'),
            style: const TextStyle(color: Colors.red),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_message!, key: const Key('reset-message')),
          ),
        if (!_done) ...[
          TextField(
            key: const Key('reset-account'),
            controller: _account,
            enabled: !_busy,
            maxLength: 256,
            decoration: const InputDecoration(labelText: 'Username hoặc email'),
          ),
          OutlinedButton(
            key: const Key('request-reset'),
            onPressed: _busy ? null : () => _send(),
            child: const Text('Gửi yêu cầu qua email'),
          ),
          const Divider(height: 32),
          const Text(
            'Đã có token trong email? Dán token để đặt lại. Mật khẩu cần chữ hoa, chữ thường và chữ số.',
          ),
          TextField(
            key: const Key('reset-token'),
            controller: _token,
            enabled: !_busy,
            obscureText: true,
            maxLength: 8192,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Token trong email'),
          ),
          TextField(
            key: const Key('reset-password'),
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            maxLength: 128,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Mật khẩu mới'),
          ),
          TextField(
            key: const Key('reset-confirm'),
            controller: _confirm,
            enabled: !_busy,
            obscureText: true,
            maxLength: 128,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Xác nhận mật khẩu mới',
            ),
          ),
          FilledButton(
            key: const Key('submit-reset'),
            onPressed: _busy ? null : () => _send(reset: true),
            child: const Text('Đặt lại mật khẩu'),
          ),
        ],
        if (_done)
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Quay lại đăng nhập'),
          ),
      ],
    ),
  );
}
