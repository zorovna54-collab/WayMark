import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:waymark/features/indoor_tracking/debug/sensor_probe_page.dart';

void main() {
  // No product route/menu is changed. Never instantiate a provider in release.
  if (!kDebugMode) return;
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: true,
      navigatorObservers: [sensorProbeRouteObserver],
      home: const SensorProbePage(),
    ),
  );
}
