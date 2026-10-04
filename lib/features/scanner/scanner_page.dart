import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../search/search_page.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool scanned = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    // Mô phỏng quét QR sau 2 giây.
    _timer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;

      setState(() {
        scanned = true;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _resetScanner() {
    setState(() {
      scanned = false;
    });

    _timer?.cancel();

    _timer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;

      setState(() {
        scanned = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          scanned ? AppColors.background : Colors.black,
      body: scanned
          ? _buildScanSuccess()
          : _buildScanner(),
    );
  }

  // =========================================================
  // TRẠNG THÁI ĐANG QUÉT
  // =========================================================

  Widget _buildScanner() {
    return Stack(
      children: [
        // Camera placeholder.
        Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF334155),
                Color(0xFF0F172A),
                Color(0xFF020617),
              ],
            ),
          ),
          child: const Center(
            child: Icon(
              Icons.camera_alt_outlined,
              size: 90,
              color: Colors.white24,
            ),
          ),
        ),

        // Lớp tối phủ lên camera.
        Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black.withValues(alpha: 0.25),
        ),

        SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  24,
                  16,
                  24,
                  0,
                ),
                child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                    _circleButton(
                      icon: Icons.close,
                      onPressed: () {
                        Navigator.pop(context);
                      },
                    ),

                    const Text(
                      'Quét WayMark',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(width: 44),
                  ],
                ),
              ),

              // QR frame
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                    ),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.accent,
                                width: 2,
                              ),
                              borderRadius:
                                  BorderRadius.circular(40),
                            ),
                          ),

                          Positioned.fill(
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.accent
                                      .withValues(alpha: 0.25),
                                  width: 4,
                                ),
                                borderRadius:
                                    BorderRadius.circular(44),
                              ),
                            ),
                          ),

                          // Giả lập đường quét.
                          Align(
                            alignment: Alignment.center,
                            child: Container(
                              height: 2,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Hướng dẫn
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  24,
                  0,
                  24,
                  40,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.qr_code_2,
                        color: Colors.white,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Hướng camera vào mã QR',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================
  // TRẠNG THÁI QUÉT THÀNH CÔNG
  // =========================================================

  Widget _buildScanSuccess() {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                24,
                40,
                24,
                24,
              ),
              child: Column(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 30),

                  // Success icon
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: AppColors.accent
                          .withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_outline,
                      size: 52,
                      color: AppColors.accent,
                    ),
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'Quét thành công!',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Bạn đang ở vị trí:',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // WayMark information
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppColors.border,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius:
                                BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.location_on_outlined,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),

                        const SizedBox(height: 16),

                        const Text(
                          'Cổng chính Khu A',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),

                        const SizedBox(height: 6),

                        const Text(
                          'WayMark ID: WM-A01',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),

                        const SizedBox(height: 18),

                        Container(
                          padding:
                              const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent
                                .withValues(alpha: 0.08),
                            borderRadius:
                                BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_outlined,
                                size: 16,
                                color: AppColors.accent,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Vị trí đã được xác nhận',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.accent,
                                  fontWeight:
                                      FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom action
          Container(
            padding: const EdgeInsets.fromLTRB(
              24,
              18,
              24,
              24,
            ),
            decoration: const BoxDecoration(
              color: AppColors.card,
              border: Border(
                top: BorderSide(
                  color: AppColors.border,
                ),
              ),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SearchPage(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(28),
                      ),
                    ),
                    child: const Text(
                      'Chọn điểm đến',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                TextButton(
                  onPressed: _resetScanner,
                  child: const Text(
                    'Quét lại',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
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
      color: Colors.black.withValues(alpha: 0.25),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            color: Colors.white,
            size: 23,
          ),
        ),
      ),
    );
  }
}