import 'package:flutter/material.dart';

import '../../services/auth_session.dart';
import 'login/login_page.dart';

void logoutToLogin(BuildContext context) {
  AuthSession.clear();
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const LoginPage()),
    (_) => false,
  );
}

Future<void> confirmLogout(BuildContext context) async {
  final token = AuthSession.accessToken;
  final revision = AuthSession.revision;
  final yes = await showDialog<bool>(
    context: context,
    builder: (c) => ValueListenableBuilder<int>(
      valueListenable: AuthSession.changes,
      builder: (_, _, _) => !AuthSession.isCurrent(token, revision)
          ? AlertDialog(
              scrollable: true,
              title: const Text('Phiên làm việc đã thay đổi'),
              content: const Text(
                'Xác nhận cũ không được đăng xuất tài khoản mới.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('Đóng'),
                ),
              ],
            )
          : AlertDialog(
              scrollable: true,
              title: const Text('Đăng xuất khỏi WayMark?'),
              content: const Text(
                'Phiên trên thiết bị này sẽ kết thúc. Hãy lưu bản nháp đang chỉnh trước khi tiếp tục.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Giữ phiên'),
                ),
                FilledButton(
                  key: const Key('confirm-logout'),
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Đăng xuất'),
                ),
              ],
            ),
    ),
  );
  if (yes == true &&
      context.mounted &&
      AuthSession.isCurrent(token, revision)) {
    logoutToLogin(context);
  }
}
