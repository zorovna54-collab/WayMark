import 'dart:math' as math;

/// Version 1 uses Android monotonic nanoseconds, never wall-clock timestamps.
const sensorSchemaVersion = 1;

enum SensorKind {
  stepDetector(18, 'steps', 'none', 1, 1),
  stepCounter(19, 'steps', 'none', 1, 1),
  rotationVector(11, 'unitless', 'androidEastMagneticNorthUp', 3, 5),
  gameRotationVector(15, 'unitless', 'androidRelativeZUp', 3, 4),
  accelerometer(1, 'm/s2', 'androidDevice', 3, 3),
  gyroscope(4, 'rad/s', 'androidDevice', 3, 3);

  const SensorKind(
    this.androidType,
    this.units,
    this.referenceFrame,
    this.minValues,
    this.maxValues,
  );
  final int androidType, minValues, maxValues;
  final String units, referenceFrame;
  bool get isStep => this == stepDetector || this == stepCounter;

  static SensorKind parse(Object? value) => values.firstWhere(
    (kind) => kind.name == value,
    orElse: () => throw const FormatException('Unknown sensor kind.'),
  );
}

enum MotionPermission { granted, notRequired, denied, unavailable }

enum RegistrationState {
  notRequested,
  registered,
  unavailable,
  permissionDenied,
  failed,
  stopped,
}

enum SensorProviderPhase {
  registration,
  listening,
  running,
  paused,
  stopped,
  error,
  recoverableError,
  overflow,
  accuracyChanged,
}

Map<Object?, Object?> sensorMap(Object? raw) {
  if (raw is! Map) throw const FormatException('Expected a sensor map.');
  return raw;
}

int sensorInt(Object? value, {int min = 0}) {
  if (value is! int || value < min || value > 9223372036854775807) {
    throw const FormatException('Expected a valid int64.');
  }
  return value;
}

String sensorString(Object? value) {
  if (value is! String || value.length > 512) {
    throw const FormatException('Expected bounded sensor text.');
  }
  return value;
}

void checkSensorSchema(Map<Object?, Object?> data) {
  if (data['schemaVersion'] is! int ||
      data['schemaVersion'] != sensorSchemaVersion) {
    throw const FormatException('Unsupported sensor schema.');
  }
}

MotionPermission parseMotionPermission(Object? value) =>
    MotionPermission.values.firstWhere(
      (p) => p.name == value,
      orElse: () => throw const FormatException('Unknown permission state.'),
    );

class SensorSample {
  SensorSample._({
    required this.kind,
    required this.generation,
    required this.sequence,
    required this.sensorTimestampNs,
    required this.nativeReceiveTimestampNs,
    required this.values,
    required this.accuracy,
  });
  final SensorKind kind;
  final int generation, sequence, sensorTimestampNs, nativeReceiveTimestampNs;
  final List<double> values;
  final int accuracy;
  int get schemaVersion => sensorSchemaVersion;
  String get units => kind.units;
  String get referenceFrame => kind.referenceFrame;

  /// Both operands have the same Android elapsedRealtimeNanos time base.
  /// This does NOT measure transport latency to Dart.
  int? get nativeDeliveryLatencyNs =>
      nativeReceiveTimestampNs >= sensorTimestampNs
      ? nativeReceiveTimestampNs - sensorTimestampNs
      : null;

  /// Android rotation vector components, x/y/z/w; optional heading accuracy
  /// stays in values[4]. No travel heading or display-axis remapping is inferred.
  List<double>? get quaternion {
    if (kind != SensorKind.rotationVector &&
        kind != SensorKind.gameRotationVector) {
      return null;
    }
    return List.unmodifiable([
      ...values.take(3),
      if (values.length >= 4)
        values[3]
      else
        math.sqrt(
          math.max(0, 1 - values.take(3).fold(0.0, (s, v) => s + v * v)),
        ),
    ]);
  }

  factory SensorSample.decode(Object? raw) {
    final data = sensorMap(raw);
    checkSensorSchema(data);
    if (data['type'] != 'sample') {
      throw const FormatException('Expected sample.');
    }
    final kind = SensorKind.parse(data['kind']);
    if (data['androidType'] is! int ||
        data['androidType'] != kind.androidType ||
        data['units'] != kind.units ||
        data['referenceFrame'] != kind.referenceFrame) {
      throw const FormatException('Sensor type/units/frame mismatch.');
    }
    final rawValues = data['values'];
    if (rawValues is! List ||
        rawValues.length < kind.minValues ||
        rawValues.length > kind.maxValues) {
      throw const FormatException('Invalid sensor values length.');
    }
    final values = <double>[];
    for (final v in rawValues) {
      if (v is! num || !v.isFinite) {
        throw const FormatException('Non-finite sensor value.');
      }
      values.add(v.toDouble());
    }
    if (kind == SensorKind.stepDetector && values.single != 1 ||
        kind == SensorKind.stepCounter &&
            (values.single < 0 ||
                values.single != values.single.truncateToDouble())) {
      throw const FormatException('Invalid step reading.');
    }
    if (kind == SensorKind.rotationVector ||
        kind == SensorKind.gameRotationVector) {
      final q = values.take(4).toList();
      if (values.take(3).any((v) => v.abs() > 1.001) ||
          (q.length == 4 &&
              (q.fold(0.0, (s, v) => s + v * v) - 1).abs() > .02) ||
          (q.length == 3 && q.fold(0.0, (s, v) => s + v * v) > 1.02) ||
          (values.length == 5 && values[4] < 0 && values[4] != -1)) {
        throw const FormatException('Invalid rotation vector.');
      }
    }
    final accuracy = sensorInt(data['accuracy'], min: -1);
    if (accuracy > 3) throw const FormatException('Unknown Android accuracy.');
    return SensorSample._(
      kind: kind,
      generation: sensorInt(data['generation'], min: 1),
      sequence: sensorInt(data['sequence'], min: 1),
      sensorTimestampNs: sensorInt(data['sensorTimestampNs'], min: 1),
      nativeReceiveTimestampNs: sensorInt(
        data['nativeReceiveTimestampNs'],
        min: 1,
      ),
      values: List.unmodifiable(values),
      accuracy: accuracy,
    );
  }
}

class SensorRegistration {
  const SensorRegistration(this.kind, this.state, [this.reason = '']);
  final SensorKind kind;
  final RegistrationState state;
  final String reason;
  factory SensorRegistration.decode(Object? raw) {
    final m = sensorMap(raw);
    return SensorRegistration(
      SensorKind.parse(m['kind']),
      RegistrationState.values.firstWhere(
        (s) => s.name == m['state'],
        orElse: () =>
            throw const FormatException('Unknown registration state.'),
      ),
      sensorString(m['reason']),
    );
  }
}

class SensorCapability {
  const SensorCapability({
    required this.kind,
    required this.available,
    this.name = '',
    this.vendor = '',
    this.version = 0,
    this.maxRange = 0,
    this.resolution = 0,
    this.minDelayUs = 0,
    this.registration = RegistrationState.notRequested,
  });
  final SensorKind kind;
  final bool available;
  final String name, vendor;
  final int version, minDelayUs;
  final double maxRange, resolution;
  final RegistrationState registration;
  factory SensorCapability.decode(Object? raw) {
    final m = sensorMap(raw);
    if (m['available'] is! bool) {
      throw const FormatException('Invalid availability.');
    }
    double finite(Object? v) {
      if (v is! num || !v.isFinite || v < 0) {
        throw const FormatException('Invalid capability measurement.');
      }
      return v.toDouble();
    }

    return SensorCapability(
      kind: SensorKind.parse(m['kind']),
      available: m['available'] as bool,
      name: sensorString(m['name']),
      vendor: sensorString(m['vendor']),
      version: sensorInt(m['version']),
      minDelayUs: sensorInt(m['minDelayUs'], min: -1),
      maxRange: finite(m['maxRange']),
      resolution: finite(m['resolution']),
      registration: RegistrationState.values.firstWhere(
        (s) => s.name == m['registration'],
        orElse: () => throw const FormatException('Invalid registration.'),
      ),
    );
  }
}

class SensorCapabilities {
  SensorCapabilities({
    required this.permission,
    required Iterable<SensorCapability> sensors,
    this.device = 'Unsupported platform',
    this.androidApi = 0,
  }) : sensors = List.unmodifiable(sensors);
  final MotionPermission permission;
  final String device;
  final int androidApi;
  final List<SensorCapability> sensors;
  SensorCapability forKind(SensorKind kind) =>
      sensors.singleWhere((s) => s.kind == kind);
  factory SensorCapabilities.decode(Object? raw) {
    final m = sensorMap(raw);
    checkSensorSchema(m);
    final list = m['sensors'];
    if (list is! List) {
      throw const FormatException('Missing sensor capabilities.');
    }
    final sensors = list.map(SensorCapability.decode).toList();
    if (sensors.length != SensorKind.values.length ||
        sensors.map((s) => s.kind).toSet().length != SensorKind.values.length) {
      throw const FormatException('Incomplete/duplicate capability inventory.');
    }
    return SensorCapabilities(
      permission: parseMotionPermission(m['permission']),
      sensors: sensors,
      device: sensorString(m['device']),
      androidApi: sensorInt(m['androidApi']),
    );
  }
}

class SensorConfig {
  SensorConfig({
    Set<SensorKind> kinds = const {
      SensorKind.stepDetector,
      SensorKind.stepCounter,
      SensorKind.rotationVector,
    },
    this.samplingPeriodUs = 20000,
  }) : kinds = Set.unmodifiable(kinds) {
    if (kinds.isEmpty ||
        samplingPeriodUs < 20000 ||
        samplingPeriodUs > 1000000) {
      throw ArgumentError('Select sensors and a 20–1000 ms sample period.');
    }
  }
  final Set<SensorKind> kinds;
  final int samplingPeriodUs;
}

class SensorStartResult {
  SensorStartResult({
    required this.generation,
    required this.permission,
    required Iterable<SensorRegistration> registrations,
  }) : registrations = List.unmodifiable(registrations);
  final int generation;
  final MotionPermission permission;
  final List<SensorRegistration> registrations;
  Set<SensorKind> get registeredKinds => registrations
      .where((r) => r.state == RegistrationState.registered)
      .map((r) => r.kind)
      .toSet();
  bool get running => registeredKinds.isNotEmpty;
  factory SensorStartResult.decode(Object? raw) {
    final m = sensorMap(raw);
    checkSensorSchema(m);
    if (m['registrations'] is! List) {
      throw const FormatException('Missing registrations.');
    }
    final registrations = (m['registrations'] as List)
        .map(SensorRegistration.decode)
        .toList();
    if (registrations.map((r) => r.kind).toSet().length !=
        registrations.length) {
      throw const FormatException('Duplicate registrations.');
    }
    return SensorStartResult(
      generation: sensorInt(m['generation'], min: 1),
      permission: parseMotionPermission(m['permission']),
      registrations: registrations,
    );
  }
}

class SensorProviderStatus {
  const SensorProviderStatus(
    this.phase,
    this.generation,
    this.message, {
    this.registrations = const [],
  });
  final SensorProviderPhase phase;
  final int generation;
  final String message;
  final List<SensorRegistration> registrations;
  factory SensorProviderStatus.decode(Object? raw) {
    final m = sensorMap(raw);
    checkSensorSchema(m);
    if (m['type'] != 'status') throw const FormatException('Expected status.');
    return SensorProviderStatus(
      SensorProviderPhase.values.firstWhere(
        (s) => s.name == m['state'],
        orElse: () => throw const FormatException('Unknown provider status.'),
      ),
      sensorInt(m['generation']),
      sensorString(m['message']),
      registrations: m['registrations'] == null
          ? const []
          : List.unmodifiable(
              (m['registrations'] is List
                      ? m['registrations'] as List
                      : throw const FormatException(
                          'Invalid registration status.',
                        ))
                  .map(SensorRegistration.decode),
            ),
    );
  }
}

/// Stateful acceptance gate. Cross-sensor timestamps may arrive out of order;
/// duplicates/backwards timestamps are rejected only within the same sensor.
class SensorSampleGate {
  int? generation;
  Set<SensorKind> kinds = {};
  final _times = <SensorKind, int>{};
  final _sequences = <SensorKind, int>{};
  int rejected = 0;

  void reset(int? nextGeneration, [Set<SensorKind> registered = const {}]) {
    generation = nextGeneration;
    kinds = Set.of(registered);
    _times.clear();
    _sequences.clear();
  }

  bool accept(SensorSample sample) {
    if (sample.generation != generation ||
        !kinds.contains(sample.kind) ||
        sample.sensorTimestampNs <= (_times[sample.kind] ?? 0) ||
        sample.sequence <= (_sequences[sample.kind] ?? 0)) {
      rejected++;
      return false;
    }
    _times[sample.kind] = sample.sensorTimestampNs;
    _sequences[sample.kind] = sample.sequence;
    return true;
  }
}
