import 'package:flutter/material.dart';

import '../../models/route_models.dart';

String routingOptionsLabel(RoutingOptions options) {
  if (options.wheelchair) return 'Xe lăn — cần dữ liệu xác minh';
  final preference = switch (options.preference) {
    'PreferElevators' => 'Ưu tiên thang máy',
    'LessWalking' => 'Ít phải đi bộ',
    _ => 'Tuyến thông thường',
  };
  return options.avoidStairs ? '$preference • tránh cầu thang' : preference;
}

Future<RoutingOptions?> showRoutePreferences(
  BuildContext context,
  RoutingOptions current,
) {
  var avoid = current.avoidStairs;
  var wheelchair = current.wheelchair;
  var preference = current.preference;
  return showDialog<RoutingOptions>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('Tùy chọn tuyến'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tránh cầu thang'),
                value: avoid,
                onChanged: (value) => update(() => avoid = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Chế độ xe lăn'),
                value: wheelchair,
                subtitle: const Text(
                  'Chưa có metadata xác minh. API sẽ từ chối, không tự chuyển sang tuyến thường.',
                ),
                onChanged: (value) => update(() => wheelchair = value),
              ),
              DropdownButtonFormField<String>(
                initialValue: preference,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Ưu tiên (trong tập cạnh được phép)',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'ShortestDistance',
                    child: Text('Tổng khoảng cách ngắn nhất'),
                  ),
                  DropdownMenuItem(
                    value: 'PreferElevators',
                    child: Text('Ưu tiên thang máy'),
                  ),
                  DropdownMenuItem(
                    value: 'LessWalking',
                    child: Text('Ít đi bộ hơn'),
                  ),
                ],
                onChanged: (value) => update(() => preference = value!),
              ),
              const SizedBox(height: 12),
              const Text(
                'Ít đi bộ: giảm mét ngoài thang máy. Ưu tiên thang máy: giảm số cạnh cầu thang/ramp rồi giảm mét. Không phải đánh giá an toàn hay thời gian chờ.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialog,
              RoutingOptions(
                avoidStairs: avoid,
                wheelchair: wheelchair,
                preference: preference,
              ),
            ),
            child: const Text('Tìm tuyến theo tùy chọn'),
          ),
        ],
      ),
    ),
  );
}
