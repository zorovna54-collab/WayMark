import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class NavigationPage extends StatefulWidget {
  final String destination;
  final String location;

  const NavigationPage({
    super.key,
    this.destination = 'Khoa Ngoại Thần Kinh',
    this.location = 'Tầng 4, Khu B',
  });

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  bool cameraMode = false;
  bool reached = false;
  int progress = 60;

  Timer? _timer;

  @override
  void initState() {
    super.initState();

    // Mô phỏng quá trình di chuyển.
    _timer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;

      setState(() {
        reached = true;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reached) {
      return _buildReachedScreen();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // =========================
          // BACKGROUND
          // =========================
          Positioned.fill(
            child: cameraMode
                ? _buildCameraBackground()
                : _buildMapBackground(),
          ),

          // =========================
          // TOP BAR
          // =========================
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                12,
                16,
                0,
              ),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  _topButton(
                    icon: Icons.close,
                    onTap: () {
                      Navigator.pop(context);
                    },
                  ),
                  _cameraToggle(),
                ],
              ),
            ),
          ),

          // =========================
          // CURRENT INSTRUCTION
          // =========================
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(
                top: 92,
                left: 16,
                right: 16,
              ),
              child: _instructionPanel(),
            ),
          ),

          // =========================
          // BOTTOM NEXT STEP PANEL
          // =========================
          _buildBottomPanel(),
        ],
      ),
    );
  }

  // =========================================================
  // MAP BACKGROUND
  // =========================================================

  Widget _buildMapBackground() {
    return Container(
      color: const Color(0xFFE2E8F0),
      child: CustomPaint(
        painter: NavigationMapPainter(),
      ),
    );
  }

  // =========================================================
  // CAMERA / AR BACKGROUND
  // =========================================================

  Widget _buildCameraBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF475569),
            Color(0xFF1E293B),
            Color(0xFF020617),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: CameraEnvironmentPainter(),
            ),
          ),

          Center(
            child: AnimatedScale(
              scale: 1.0,
              duration: const Duration(milliseconds: 300),
              child: const Icon(
                Icons.navigation,
                size: 120,
                color: AppColors.accent,
                shadows: [
                  Shadow(
                    color: Colors.black54,
                    blurRadius: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // INSTRUCTION PANEL
  // =========================================================

  Widget _instructionPanel() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 15,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.turn_right,
              size: 31,
              color: AppColors.accent,
            ),
          ),

          const SizedBox(width: 16),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rẽ phải phía trước',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'vào Hành lang C • Còn 45m',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // BOTTOM PANEL
  // =========================================================

  Widget _buildBottomPanel() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          24,
          20,
          24,
          28,
        ),
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(32),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 20,
              offset: Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: AppColors.secondary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_upward,
                    color: AppColors.primary,
                    size: 21,
                  ),
                ),

                const SizedBox(width: 14),

                const Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TIẾP THEO',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.9,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Đi thẳng 20m tới Thang máy',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress / 100,
                minHeight: 8,
                backgroundColor: AppColors.secondary,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(
                  AppColors.accent,
                ),
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Đã hoàn thành $progress%',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // TOP BUTTON
  // =========================================================

  Widget _topButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            color: Colors.white,
            size: 23,
          ),
        ),
      ),
    );
  }

  // =========================================================
  // CAMERA TOGGLE
  // =========================================================

  Widget _cameraToggle() {
    return Material(
      color: cameraMode
          ? AppColors.accent
          : Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: () {
          setState(() {
            cameraMode = !cameraMode;
          });
        },
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 7),
              Text(
                cameraMode ? 'Tắt Camera' : 'Camera',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // REACHED SCREEN
  // =========================================================

  Widget _buildReachedScreen() {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            24,
            40,
            24,
            32,
          ),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 128,
                        height: 128,
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.location_on,
                          size: 62,
                          color: Colors.white,
                        ),
                      ),

                      const SizedBox(height: 30),

                      const Text(
                        'Đã đến nơi!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        '${widget.destination}, ${widget.location}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.popUntil(
                      context,
                      (route) => route.isFirst,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text(
                    'Hoàn tất',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================
// MAP PAINTER
// ===========================================================

class NavigationMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pathPaint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();

    path.moveTo(
      size.width * 0.20,
      size.height * 0.72,
    );

    path.lineTo(
      size.width * 0.20,
      size.height * 0.52,
    );

    path.lineTo(
      size.width * 0.52,
      size.height * 0.52,
    );

    path.lineTo(
      size.width * 0.52,
      size.height * 0.32,
    );

    path.lineTo(
      size.width * 0.75,
      size.height * 0.32,
    );

    canvas.drawPath(path, pathPaint);

    // Current position
    final currentPaint = Paint()
      ..color = AppColors.accent;

    canvas.drawCircle(
      Offset(
        size.width * 0.20,
        size.height * 0.72,
      ),
      14,
      currentPaint,
    );

    // White center
    final whitePaint = Paint()
      ..color = Colors.white;

    canvas.drawCircle(
      Offset(
        size.width * 0.20,
        size.height * 0.72,
      ),
      5,
      whitePaint,
    );

    // Destination
    final destinationPaint = Paint()
      ..color = AppColors.primary;

    canvas.drawCircle(
      Offset(
        size.width * 0.75,
        size.height * 0.32,
      ),
      15,
      destinationPaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return false;
  }
}

// ===========================================================
// CAMERA ENVIRONMENT PAINTER
// ===========================================================

class CameraEnvironmentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 2;

    final floorY = size.height * 0.72;

    for (int i = 0; i < 9; i++) {
      final x = size.width * i / 8;

      canvas.drawLine(
        Offset(size.width / 2, floorY),
        Offset(x, size.height),
        linePaint,
      );
    }

    canvas.drawLine(
      Offset(0, floorY),
      Offset(size.width, floorY),
      linePaint,
    );

    final wallPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.18,
        size.height * 0.28,
        size.width * 0.64,
        size.height * 0.44,
      ),
      wallPaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return false;
  }
}