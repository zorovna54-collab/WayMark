import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'admin_page_shell.dart';

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});
  @override
  Widget build(BuildContext context) => AdminPageShell(
    title: 'Tổng quan hệ thống',
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              'Tổng WayMarks',
              '245',
              Icons.location_on_outlined,
              '+12 trong tháng',
            ),
            _MetricCard(
              'Lượt quét QR (30 ngày)',
              '12,450',
              Icons.qr_code_2,
              '+15%',
            ),
            _MetricCard(
              'Điều hướng thành công',
              '11,920',
              Icons.navigation_outlined,
              '95% tỷ lệ',
            ),
            _MetricCard(
              'Người dùng active',
              '3,200',
              Icons.people_outline,
              '+5% trong tuần',
            ),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lưu lượng quét theo khu vực',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 170,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final value in [40, 70, 45, 90, 60, 30, 80])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: Container(
                              height: value * 1.5,
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: .7),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Khu A    Khu B    Khu C    Sảnh chính    Tầng 2    Tầng 3    Tầng 4',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Hoạt động gần đây',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ),
              for (final line in [
                'WayMark mới được quét — Sảnh chính',
                'Điều hướng hoàn tất — Khoa Ngoại Thần Kinh',
                'WayMark được cập nhật — Tầng 2, Khu B',
              ])
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.secondary,
                    child: Icon(Icons.bolt, color: AppColors.accent),
                  ),
                  title: Text(line),
                  subtitle: const Text('Hôm nay'),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.title, this.value, this.icon, this.trend);
  final String title, value, trend;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 245,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.accent),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(color: AppColors.textSecondary)),
            Text(
              value,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
            ),
            Text(
              trend,
              style: const TextStyle(color: AppColors.accent, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
