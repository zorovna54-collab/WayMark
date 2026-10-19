import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../ai/lm_studio_test_page.dart';
import '../home/home_page.dart';
import 'admin_page_shell.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});
  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  void _goBack() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState!.closeDrawer();
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomePage()),
      );
    }
  }

  bool _elevator = true;
  bool _ar = true;
  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: Navigator.of(context).canPop(),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _goBack();
    },
    child: AdminPageShell(
      scaffoldKey: _scaffoldKey,
      onBack: _goBack,
      title: 'Cài đặt hệ thống',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cấu hình chung',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Quản lý các thông số cơ bản của ứng dụng WayMark.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 22),
                  const TextField(
                    decoration: InputDecoration(
                      labelText: 'Tên tổ chức / Địa điểm',
                      hintText: 'Bệnh viện Đa khoa Quốc tế',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _SettingsDropdown(
                    label: 'Đơn vị đo lường',
                    values: ['Mét (m)', 'Feet (ft)'],
                  ),
                  const SizedBox(height: 16),
                  const _SettingsDropdown(
                    label: 'Ngôn ngữ mặc định',
                    values: ['Tiếng Việt', 'English'],
                  ),
                  const SizedBox(height: 16),
                  const _SettingsDropdown(
                    label: 'Tự động xóa lịch sử điều hướng',
                    values: ['Sau 30 ngày', 'Sau 60 ngày', 'Không bao giờ'],
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.smart_toy_outlined,
                color: AppColors.accent,
              ),
              title: const Text('Kiểm thử LM Studio AI'),
              subtitle: const Text(
                'Kiểm tra kết nối local và gửi câu hỏi thử nghiệm.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const LmStudioTestPage(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cấu hình điều hướng (Routing Engine)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Thông số thuật toán tìm đường.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ưu tiên tuyến đường có thang máy'),
                    subtitle: const Text(
                      'Dành cho người dùng xe lăn hoặc hạn chế vận động.',
                    ),
                    value: _elevator,
                    onChanged: (value) => setState(() => _elevator = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hiển thị đường đi AR'),
                    subtitle: const Text(
                      'Cho phép người dùng bật chế độ Camera.',
                    ),
                    value: _ar,
                    onChanged: (value) => setState(() => _ar = value),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cấu hình demo — chưa lưu dữ liệu.'),
                ),
              ),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Lưu cấu hình'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SettingsDropdown extends StatelessWidget {
  const _SettingsDropdown({required this.label, required this.values});
  final String label;
  final List<String> values;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: values.first,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: [
      for (final value in values)
        DropdownMenuItem(value: value, child: Text(value)),
    ],
    onChanged: (_) {},
  );
}
