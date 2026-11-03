import 'package:flutter/material.dart';

import '../../services/auth_session.dart';
import '../../services/auth_api_service.dart';
import 'login/login_page.dart';

/// Hides retained private content without popping or discarding its RAM draft.
class WorkflowRecovery extends StatefulWidget {
  const WorkflowRecovery({
    super.key,
    required this.workflow,
    this.onRecovered,
    this.api,
  });
  final OwnerWorkflow workflow;
  final AuthApiService? api;
  final VoidCallback? onRecovered;
  @override
  State<WorkflowRecovery> createState() => _WorkflowRecoveryState();
}

class _WorkflowRecoveryState extends State<WorkflowRecovery> {
  bool _busy = false;
  String? _message;
  Future<void> _recover() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (AuthSession.accessToken == null ||
          AuthSession.expired ||
          AuthSession.ownerKey != widget.workflow.ownerKey) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => const LoginPage(returnToWorkflow: true),
          ),
        );
      }
      if (!mounted) return;
      final profile = await (widget.api ?? AuthApiService()).getProfile();
      if (!mounted) return;
      if (profile.userName.toLowerCase() !=
              AuthSession.username?.toLowerCase() ||
          !widget.workflow.rebind()) {
        setState(
          () => _message = 'Tài khoản khác không được mở bản nháp này. Đăng nhập lại đúng chủ phiên; không tự chuyển dữ liệu.',
        );
        return;
      }
      widget.onRecovered?.call();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Chưa xác minh lại chủ phiên. Giữ bản nháp; đăng nhập đúng tài khoản rồi thử đối chiếu lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Khôi phục phiên làm việc')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Phiên hết hạn hoặc tài khoản đã thay đổi. Nội dung riêng được ẩn; bản nháp đang giữ trong RAM, chưa bị xóa. Không tự gửi lại Save/Publish.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Đăng nhập đúng chủ phiên để tiếp tục. Nếu lần ghi trước mất phản hồi, đọc lại server để đối chiếu trước khi lưu. Đóng ứng dụng có thể mất bản chưa lưu; đây không phải backup xuyên restart.',
          ),
          if (_message != null) Text(_message!),
          FilledButton(
            onPressed: _busy ? null : _recover,
            child: Text(
              _busy ? 'Đang xác minh…' : 'Đăng nhập lại / xác minh chủ phiên',
            ),
          ),
        ],
      ),
    ),
  );
}

class SessionRecoveryButton extends StatelessWidget {
  const SessionRecoveryButton({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: AuthSession.changes,
    builder: (_, _, _) => !AuthSession.expired
        ? const SizedBox.shrink()
        : OutlinedButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => const LoginPage(returnToWorkflow: true),
              ),
            ),
            child: const Text('Phiên hết hạn • Đăng nhập lại'),
          ),
  );
}

Future<T?> showSessionDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final workflow = OwnerWorkflow();
  try {
    return await showWorkflowDialog<T>(
      context: context,
      workflow: workflow,
      builder: builder,
    );
  } finally {
    workflow.dispose();
  }
}

/// The original dialog's contents and confirmations disappear on session change.
Future<T?> showWorkflowDialog<T>({
  required BuildContext context,
  required OwnerWorkflow workflow,
  required WidgetBuilder builder,
}) {
  final revision = AuthSession.revision;
  return showDialog<T>(
    context: context,
    builder: (c) => ListenableBuilder(
      listenable: workflow,
      builder: (_, _) => workflow.current && AuthSession.revision == revision
          ? builder(c)
          : AlertDialog(
              scrollable: true,
              title: const Text('Phiên làm việc đã thay đổi'),
              content: const Text(
                'Thao tác cũ đã bị vô hiệu hóa. Bản nháp được giữ; không gửi yêu cầu bằng tài khoản mới.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('Đóng'),
                ),
              ],
            ),
    ),
  );
}
