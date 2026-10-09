import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../navigation/navigation_page.dart';

class RoutePreviewPage extends StatelessWidget {
  final String destination;
  final String location;
  final String distance;
  final String wayMarkCode;

  const RoutePreviewPage({
    super.key,
    this.destination = 'Khoa Ngoại Thần Kinh',
    this.location = 'Tầng 4, Khu B',
    this.distance = '120m',
    this.wayMarkCode = '',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // =========================
          // FAKE MAP
          // =========================
          Positioned.fill(
            child: Container(
              color: const Color(0xFFE2E8F0),
              child: CustomPaint(painter: RoutePainter()),
            ),
          ),

          // =========================
          // TOP BAR
          // =========================
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _circleButton(
                    icon: Icons.arrow_back,
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                  _circleButton(icon: Icons.explore_outlined, onPressed: () {}),
                ],
              ),
            ),
          ),

          // =========================
          // BOTTOM SHEET
          // =========================
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
              decoration: const BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 20,
                    offset: Offset(0, -6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              destination,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              location,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            if (wayMarkCode.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'WayMark: $wayMarkCode',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            distance,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: AppColors.accent,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            '~ 3 phút đi bộ',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),

                  _routeStep(
                    icon: Icons.location_on,
                    title: 'Vị trí hiện tại',
                    subtitle: 'Cổng chính Khu A • WM-A01',
                    isActive: true,
                  ),

                  _routeLine(),

                  _routeStep(
                    icon: Icons.turn_right,
                    title: 'WayMark tiếp theo',
                    subtitle: 'Ngã ba hành lang • WM-A02',
                  ),

                  _routeLine(),

                  _routeStep(
                    icon: Icons.location_on_outlined,
                    title: 'Điểm đến',
                    subtitle: '$destination • $location',
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NavigationPage(
                              destination: destination,
                              location: location,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: const Text(
                        'Bắt đầu dẫn đường',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: AppColors.card,
      elevation: 5,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: AppColors.primary),
        ),
      ),
    );
  }

  Widget _routeStep({
    required IconData icon,
    required String title,
    required String subtitle,
    bool isActive = false,
  }) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isActive ? AppColors.accent : AppColors.secondary,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 17,
            color: isActive ? Colors.white : AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _routeLine() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
      child: Container(height: 20, width: 2, color: AppColors.border),
    );
  }
}

class RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();

    path.moveTo(size.width * 0.20, size.height * 0.78);

    path.lineTo(size.width * 0.20, size.height * 0.55);

    path.lineTo(size.width * 0.52, size.height * 0.55);

    path.lineTo(size.width * 0.52, size.height * 0.30);

    path.lineTo(size.width * 0.72, size.height * 0.30);

    canvas.drawPath(path, paint);

    // Start point
    final startPaint = Paint()..color = AppColors.primary;

    canvas.drawCircle(
      Offset(size.width * 0.20, size.height * 0.78),
      10,
      startPaint,
    );

    // Destination
    final destinationPaint = Paint()..color = AppColors.accent;

    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.30),
      14,
      destinationPaint,
    );

    final whitePaint = Paint()..color = Colors.white;

    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.30),
      5,
      whitePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
