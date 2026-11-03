// Run explicitly with -t tool/mobile_map_demo.dart. No login, HTTP or SQL.
import 'package:flutter/material.dart';
import 'package:waymark/features/route/demo_floor_plan.dart';
import 'package:waymark/features/search/search_page.dart';

import 'mobile_demo_data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = MobileDemoData(await DemoHospitalMap.load());
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Inter',
        colorSchemeSeed: const Color(0xff0f172a),
      ),
      builder: (context, child) => Column(
        children: [
          const SafeArea(
            bottom: false,
            child: Material(
              color: Color(0xfffef3c7),
              child: Padding(
                padding: EdgeInsets.all(6),
                child: Text(
                  'DEMO OFFLINE • Fixture, không gọi API',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ),
          ),
          Expanded(child: child!),
        ],
      ),
      home: SearchPage(
        start: api.location(MobileDemoData.destination),
        api: api,
        initialQuery: '001',
      ),
    ),
  );
}
