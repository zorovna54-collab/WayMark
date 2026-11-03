import 'dart:async';

import 'package:flutter/services.dart';

import 'sensor_models.dart';
import 'sensor_provider.dart';

/// Owns one native event subscription. No permissions are requested implicitly.
class AndroidSensorProvider implements SensorProvider {
  static AndroidSensorProvider? _owner;
  AndroidSensorProvider({
    this._control = const MethodChannel('waymark/sensors/control'),
    this._events = const EventChannel('waymark/sensors/events'),
    this.listenTimeout = const Duration(seconds: 5),
  });
  final MethodChannel _control;
  final EventChannel _events;
  final Duration listenTimeout;
  final _samples = StreamController<SensorSample>.broadcast();
  final _statuses = StreamController<SensorProviderStatus>.broadcast();
  final _gate = SensorSampleGate();
  final _pendingSamples = <SensorSample>[];
  StreamSubscription<Object?>? _subscription;
  Completer<void>? _listening;
  Future<void> _tail = Future.value();
  int _nextGeneration = 0, _epoch = 0;
  int? _pendingGeneration;
  SensorStartResult? _lastResult;
  bool _disposed = false;
  Future<void>? _disposing;

  @override
  Stream<SensorSample> get samples => _samples.stream.where(
    (sample) => !_disposed && sample.generation == _gate.generation,
  );
  @override
  Stream<SensorProviderStatus> get statuses =>
      _statuses.stream.where((_) => !_disposed);

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _checkOpen() {
    if (_disposed) throw StateError('Sensor provider disposed.');
  }

  @override
  Future<SensorCapabilities> probe() => _serial(() async {
    _checkOpen();
    return SensorCapabilities.decode(
      await _control.invokeMethod<Object?>('probe'),
    );
  });

  @override
  Future<MotionPermission> requestPermission() => _serial(() async {
    _checkOpen();
    final m = sensorMap(
      await _control.invokeMethod<Object?>('requestPermission'),
    );
    checkSensorSchema(m);
    return parseMotionPermission(m['permission']);
  });

  void _status(SensorProviderPhase phase, String message, [int? generation]) {
    if (!_disposed) {
      _statuses.add(
        SensorProviderStatus(
          phase,
          generation ?? _gate.generation ?? _pendingGeneration ?? 0,
          message,
        ),
      );
    }
  }

  void _onEvent(Object? event) {
    if (_disposed) return;
    try {
      final m = sensorMap(event);
      if (m['type'] == 'status') {
        final status = SensorProviderStatus.decode(m);
        if (status.phase == SensorProviderPhase.listening) {
          if (_listening?.isCompleted == false) _listening!.complete();
          return;
        }
        if (status.generation != (_gate.generation ?? _pendingGeneration)) {
          return;
        }
        _statuses.add(status);
        if (status.phase == SensorProviderPhase.paused ||
            status.phase == SensorProviderPhase.stopped ||
            status.phase == SensorProviderPhase.error) {
          _epoch++;
          _gate.reset(null);
          _pendingGeneration = null;
          _pendingSamples.clear();
          // Release the channel subscription as well as fencing samples. A
          // direct provider consumer may restart without a session controller.
          unawaited(stop().catchError((Object _) {}));
        }
      } else {
        final sample = SensorSample.decode(m);
        if (_pendingGeneration == sample.generation) {
          if (_pendingSamples.length == 128) {
            _pendingSamples.removeAt(0);
            _status(
              SensorProviderPhase.overflow,
              'Start buffer overflow; samples lost.',
            );
          }
          _pendingSamples.add(sample);
        } else if (_gate.accept(sample)) {
          _samples.add(sample);
        }
      }
    } on FormatException catch (error) {
      _status(SensorProviderPhase.recoverableError, error.message);
      // Malformed payloads are recoverable and do not stop the valid stream.
    }
  }

  @override
  Future<SensorStartResult> start(SensorConfig config) {
    final epoch = _epoch;
    return _serial(() async {
      _checkOpen();
      if (_gate.generation != null) {
        return _lastResult!;
      }
      // Native clock prevents ID reuse if Dart provider is recreated in the
      // same Activity. No wall clock or cross-clock subtraction is involved.
      final clock = sensorMap(await _control.invokeMethod<Object?>('clock'));
      checkSensorSchema(clock);
      final now = sensorInt(clock['nativeTimestampNs'], min: 1);
      _nextGeneration = now > _nextGeneration ? now : _nextGeneration + 1;
      final generation = _nextGeneration;
      if (_owner != null && !identical(_owner, this)) {
        throw StateError(
          'Only one sensor provider may own the engine channels.',
        );
      }
      _owner = this;
      try {
        _listening = Completer<void>();
        _subscription = _events.receiveBroadcastStream().listen(
          _onEvent,
          onError: (Object error) {
            if (_listening?.isCompleted == false) {
              _listening!.completeError(error);
            }
            _status(SensorProviderPhase.error, 'Sensor event channel failed.');
            unawaited(stop().catchError((Object _) {}));
          },
          onDone: () {
            _status(SensorProviderPhase.error, 'Sensor event channel closed.');
            unawaited(stop().catchError((Object _) {}));
          },
        );
        await _listening!.future.timeout(listenTimeout);
        if (_disposed || epoch != _epoch) {
          throw StateError('Sensor start cancelled.');
        }
        _pendingGeneration = generation;
        final result = SensorStartResult.decode(
          await _control.invokeMethod<Object?>('start', {
            'schemaVersion': sensorSchemaVersion,
            'generation': generation,
            'kinds': config.kinds.map((k) => k.name).toList(),
            'samplingPeriodUs': config.samplingPeriodUs,
          }),
        );
        if (_disposed || epoch != _epoch) {
          throw StateError('Sensor start cancelled.');
        }
        if (result.generation != generation ||
            result.registrations.length != config.kinds.length ||
            result.registrations.any((r) => !config.kinds.contains(r.kind))) {
          throw const FormatException(
            'Native start result does not match request.',
          );
        }
        _gate.reset(generation, result.registeredKinds);
        _pendingGeneration = null;
        for (final sample in _pendingSamples) {
          if (_gate.accept(sample)) _samples.add(sample);
        }
        _pendingSamples.clear();
        if (!result.running) await _stopNative();
        _lastResult = result;
        return result;
      } catch (_) {
        await _stopNative();
        rethrow;
      }
    });
  }

  Future<void> _stopNative() async {
    _gate.reset(null);
    _pendingGeneration = null;
    _pendingSamples.clear();
    if (!identical(_owner, this)) return;
    try {
      await _control.invokeMethod<void>('stop');
    } finally {
      final subscription = _subscription;
      _subscription = null;
      try {
        await subscription?.cancel();
      } finally {
        _listening = null;
        if (identical(_owner, this)) _owner = null;
      }
    }
  }

  @override
  Future<void> stop() {
    _epoch++;
    _gate.reset(null);
    _pendingGeneration = null;
    _pendingSamples.clear();
    return _serial(_stopNative);
  }

  @override
  Future<void> dispose() {
    if (_disposing case final pending?) return pending;
    _disposed = true;
    _epoch++;
    _gate.reset(null);
    return _disposing = _serial(() async {
      try {
        await _stopNative();
      } finally {
        await _samples.close();
        await _statuses.close();
      }
    });
  }
}
