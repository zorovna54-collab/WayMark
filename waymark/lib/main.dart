import 'package:flutter/material.dart';

import 'features/auth/login/login_page.dart';

void main() {
  runApp(const WayMarkApp());
}

class WayMarkApp extends StatelessWidget {
  const WayMarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WayMark',
      home: const LoginPage(),
    );
  }
}
