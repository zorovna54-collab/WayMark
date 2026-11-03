import 'dart:async';

import 'package:flutter/foundation.dart';

import 'android_sensor_provider.dart';
import 'sensor_models.dart';

abstract interface class SensorProvider {
  Stream<SensorSample> get samples;
  Stream<SensorProviderStatus> get statuses;
  Future<SensorCapabilities> probe();

  /// Call only from an explicit user gesture; start/probe never request it.
  Future<MotionPermission> requestPermission();
  Future<SensorStartResult> start(SensorConfig config);
  Future<void> stop();
  Future<void> dispose();
}

SensorProvider createSensorProvider() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? AndroidSensorProvider()
    : UnsupportedSensorProvider();

class UnsupportedSensorProvider implements SensorProvider {
  @override
  Stream<SensorSample> get samples => const Stream.empty();
  @override
  Stream<SensorProviderStatus> get statuses => const Stream.empty();
  @override
  Future<SensorCapabilities> probe() async => SensorCapabilities(
    permission: MotionPermission.unavailable,
    sensors: [
      for (final kind in SensorKind.values)
        SensorCapability(kind: kind, available: false),
    ],
  );
  @override
  Future<MotionPermission> requestPermission() async =>
      MotionPermission.unavailable;
  @override
  Future<SensorStartResult> start(SensorConfig config) async =>
      SensorStartResult(
        generation: 1,
        permission: MotionPermission.unavailable,
        registrations: [
          for (final kind in config.kinds)
            SensorRegistration(
              kind,
              RegistrationState.unavailable,
              'Unsupported platform',
            ),
        ],
      );
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
