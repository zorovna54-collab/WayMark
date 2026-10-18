import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../search/search_page.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final historyData = [
      {
        'date': 'Hôm nay',
        'items': [
          {
            'destination': 'Khoa Ngoại Thần Kinh',
            'from': 'Cổng chính Khu A',
            'time': '14:30',
          },
          {
            'destination': 'Nhà vệ sinh (Nam)',
            'from': 'Khu tiếp đón',
            'time': '09:15',
          },
        ],
      },
      {
        'date': 'Hôm qua',
        'items': [
          {
            'destination': 'Quầy thuốc Số 3',
            'from': 'Cổng phụ Khu C',
            'time': '16:45',
          },
          {
            'destination': 'Phòng Cấp cứu',
            'from': 'Bãi đỗ xe',
            'time': '08:20',
          },
        ],
      },
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Lịch sử di chuyển',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back,
            color: AppColors.primary,
          ),
        ),
      ),

      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          for (final group in historyData) ...[
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                Text(
                  group['date'] as String,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            ...((group['items'] as List<Map<String, String>>).map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _historyCard(
                  context,
                  destination: item['destination']!,
                  from: item['from']!,
                  time: item['time']!,
                ),
              ),
            )),

            const SizedBox(height: 16),
          ],

          const SizedBox(height: 8),

          OutlinedButton.icon(
            onPressed: () {
              _showClearDialog(context);
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Xóa lịch sử'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: BorderSide(
                color: Colors.redAccent.withValues(alpha: 0.35),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyCard(
    BuildContext context, {
    required String destination,
    required String from,
    required String time,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 14,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          time,
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 7),

                    Text(
                      destination,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SearchPage(),
                    ),
                  );
                },
                style: IconButton.styleFrom(
                  backgroundColor:
                      AppColors.accent.withValues(alpha: 0.10),
                ),
                icon: const Icon(
                  Icons.navigation_outlined,
                  color: AppColors.accent,
                  size: 19,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Từ: $from',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Xóa lịch sử?'),
          content: const Text(
            'Bạn có chắc muốn xóa toàn bộ lịch sử di chuyển?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã xóa lịch sử'),
                  ),
                );
              },
              child: const Text(
                'Xóa',
                style: TextStyle(
                  color: Colors.redAccent,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
