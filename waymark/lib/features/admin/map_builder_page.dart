import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'admin_page_shell.dart';

class AdminMapBuilderPage extends StatefulWidget {
  const AdminMapBuilderPage({super.key});
  @override
  State<AdminMapBuilderPage> createState() => _AdminMapBuilderPageState();
}

class _AdminMapBuilderPageState extends State<AdminMapBuilderPage> {
  String _tool = 'Chọn';
  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  @override
  Widget build(BuildContext context) => AdminPageShell(
    title: 'Map & Route Builder',
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () {}, child: const Text('Hủy')),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _notice('Bản dựng demo — chưa lưu dữ liệu.'),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Lưu thay đổi'),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 700;
              return Row(
                children: [
                  NavigationRail(
                    extended: constraints.maxWidth > 900,
                    selectedIndex: [
                      'Chọn',
                      'Thêm node',
                      'Nối đường',
                    ].indexOf(_tool),
                    onDestinationSelected: (i) => setState(
                      () => _tool = ['Chọn', 'Thêm node', 'Nối đường'][i],
                    ),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.ads_click),
                        label: Text('Chọn'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.add_location_alt_outlined),
                        label: Text('Thêm node'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.polyline),
                        label: Text('Nối đường'),
                      ),
                    ],
                  ),
                  Expanded(child: _MapCanvas(tool: _tool)),
                  if (wide)
                    SizedBox(
                      width: 260,
                      child: _PropertiesPanel(
                        onCreateQr: () => _notice('Tạo QR đang ở chế độ demo.'),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        if (MediaQuery.sizeOf(context).width <= 700)
          SizedBox(
            height: 220,
            child: _PropertiesPanel(
              onCreateQr: () => _notice('Tạo QR đang ở chế độ demo.'),
            ),
          ),
      ],
    ),
  );
}

class _MapCanvas extends StatelessWidget {
  const _MapCanvas({required this.tool});
  final String tool;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(child: CustomPaint(painter: _GridPainter())),
        CustomPaint(size: Size.infinite, painter: _RoutePainter()),
        const _MapNode(alignment: Alignment(-.65, .48), title: 'Cổng chính'),
        const _MapNode(alignment: Alignment(.05, -.08), title: 'Sảnh A'),
        const _MapNode(alignment: Alignment(.66, -.48), title: 'Khoa Ngoại'),
        Positioned(
          left: 12,
          bottom: 12,
          child: Chip(
            avatar: const Icon(Icons.ads_click, size: 18),
            label: Text('Công cụ: $tool'),
          ),
        ),
      ],
    ),
  );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = AppColors.border;
    for (double x = 0; x < size.width; x += 22) {
      for (double y = 0; y < size.height; y += 22) {
        canvas.drawCircle(Offset(x, y), 1, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * .18, size.height * .73)
      ..lineTo(size.width * .18, size.height * .52)
      ..lineTo(size.width * .5, size.height * .52)
      ..lineTo(size.width * .5, size.height * .35)
      ..lineTo(size.width * .82, size.height * .35);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MapNode extends StatelessWidget {
  const _MapNode({required this.alignment, required this.title});
  final Alignment alignment;
  final String title;
  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircleAvatar(
          radius: 12,
          backgroundColor: AppColors.primary,
          child: Icon(Icons.place, color: Colors.white, size: 15),
        ),
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
          ),
          child: Text(title, style: const TextStyle(fontSize: 11)),
        ),
      ],
    ),
  );
}

class _PropertiesPanel extends StatelessWidget {
  const _PropertiesPanel({required this.onCreateQr});
  final VoidCallback onCreateQr;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        'Thuộc tính Node',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
      ),
      const SizedBox(height: 16),
      const TextField(
        decoration: InputDecoration(
          labelText: 'WayMark ID',
          border: OutlineInputBorder(),
          hintText: 'WM-001',
        ),
      ),
      const SizedBox(height: 12),
      const TextField(
        decoration: InputDecoration(
          labelText: 'Tên hiển thị',
          border: OutlineInputBorder(),
          hintText: 'Sảnh chính',
        ),
      ),
      const SizedBox(height: 12),
      const TextField(
        decoration: InputDecoration(
          labelText: 'Khu vực / Tầng',
          border: OutlineInputBorder(),
          hintText: 'Tầng 1, Khu B',
        ),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: 'Điểm chuyển tiếp',
        decoration: const InputDecoration(
          labelText: 'Loại Node',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(
            value: 'Điểm chuyển tiếp',
            child: Text('Điểm chuyển tiếp'),
          ),
          DropdownMenuItem(
            value: 'Điểm đến',
            child: Text('Điểm đến (Destination)'),
          ),
        ],
        onChanged: (_) {},
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: onCreateQr,
        icon: const Icon(Icons.qr_code_2),
        label: const Text('Tạo / In mã QR'),
      ),
    ],
  );
}
