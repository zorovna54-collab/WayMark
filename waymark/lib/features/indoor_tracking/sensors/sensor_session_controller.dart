import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'sensor_models.dart';
import 'sensor_provider.dart';

enum SensorSessionState {
  idle,
  starting,
  running,
  paused,
  permissionDenied,
  unavailable,
  error,
  disposed,
}

/// Sensor diagnostics only. Does not estimate position, heading or distance.
/// This controller owns and disposes its injected provider.
class SensorSessionController extends ChangeNotifier {
  SensorSessionController(
    this.provider, {
    this.displayInterval = const Duration(milliseconds: 200),
  }) {
    _samples = provider.samples.listen(
      _onSample,
      onError: (Object _) {
        _providerFailure('Sensor sample stream failed.');
      },
    );
    _statuses = provider.statuses.listen(
      _onStatus,
      onError: (Object _) {
        _providerFailure('Sensor status stream failed.');
      },
    );
  }
  final SensorProvider provider;
  final Duration displayInterval;
  SensorSessionState state = SensorSessionState.idle;
  SensorCapabilities? capabilities;
  SensorStartResult? result;
  MotionPermission? permission;
  String? lastError;
  int detectorEvents = 0, rejectedEvents = 0, counterResets = 0;
  int overflowEvents = 0;
  double? counterRaw;
  final latest = <SensorKind, SensorSample>{};
  final _recent = ListQueue<SensorSample>();
  List<SensorSample> get recent => List.unmodifiable(_recent);
  final _gate = SensorSampleGate();
  final _observations = StreamController<SensorSample>.broadcast(sync: true);

  /// Accepted, generation-fenced samples for positioning consumers. Lifecycle
  /// remains owned by this controller; callers must not pause this subscription.
  Stream<SensorSample> get observations => _observations.stream;
  final _startingSamples = <SensorSample>[];
  late final StreamSubscription<SensorSample> _samples;
  late final StreamSubscription<SensorProviderStatus> _statuses;
  Future<void> _tail = Future.value();
  Future<void>? _shutdown;
  Timer? _displayTimer;
  int _revision = 0;
  bool _closed = false, _visible = true, _wantsRun = false;
  SensorConfig? _config;

  Future<void> _serial(Future<void> Function() action) {
    final future = _tail.then((_) => action());
    _tail = future.catchError((Object _) {});
    return future;
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> refresh() => _serial(() async {
    if (_closed) return;
    try {
      capabilities = await provider.probe();
      if (_closed) return;
      permission = capabilities!.permission;
      if (permission == MotionPermission.denied &&
          state == SensorSessionState.running &&
          result!.registeredKinds.any((kind) => kind.isStep)) {
        _revision++;
        _wantsRun = false;
        _gate.reset(null);
        await provider.stop();
        if (_closed) return;
        state = SensorSessionState.permissionDenied;
        lastError = 'Activity permission revoked. Start explicitly to observe available sensors.';
      }
      _notify();
    } catch (_) {
      if (!_closed) {
        _revision++;
        _wantsRun = false;
        _gate.reset(null);
        try {
          await provider.stop();
        } catch (_) {}
        if (_closed) return;
        lastError = 'Cannot probe sensors.';
        state = SensorSessionState.error;
        _notify();
      }
    }
  });

  /// Only the explicit permission button calls this. Resume never prompts.
  Future<void> requestPermission() => _serial(() async {
    if (_closed || !_visible) return;
    try {
      final granted = await provider.requestPermission();
      if (_closed) return;
      permission = granted;
      if (granted == MotionPermission.denied &&
          state != SensorSessionState.running) {
        state = SensorSessionState.permissionDenied;
      }
      _notify();
    } catch (_) {
      if (!_closed) {
        lastError = 'Cannot request activity permission.';
        state = SensorSessionState.error;
        _notify();
      }
    }
  });

  Future<void> start([SensorConfig? config]) {
    if (_closed) return Future.value();
    _wantsRun = true;
    _config = config ?? _config ?? SensorConfig();
    final revision = _revision;
    return _serial(() => _start(revision));
  }

  Future<void> _start(int revision) async {
    if (_closed ||
        !_visible ||
        !_wantsRun ||
        revision != _revision ||
        state == SensorSessionState.running) {
      return;
    }
    state = SensorSessionState.starting;
    _startingSamples.clear();
    latest.clear();
    counterRaw = null;
    lastError = null;
    _notify();
    try {
      capabilities = await provider.probe();
      if (_closed || revision != _revision || !_visible) return;
      permission = capabilities!.permission;
      final started = await provider.start(_config!);
      if (_closed || revision != _revision || !_visible) {
        await provider.stop();
        return;
      }
      result = started;
      permission = started.permission;
      _gate.reset(started.generation, started.registeredKinds);
      state = started.running
          ? SensorSessionState.running
          : started.permission == MotionPermission.denied &&
                started.registrations.any(
                  (r) => r.state == RegistrationState.permissionDenied,
                )
          ? SensorSessionState.permissionDenied
          : started.registrations.any(
              (r) => r.state == RegistrationState.failed,
            )
          ? SensorSessionState.error
          : SensorSessionState.unavailable;
      for (final sample in _startingSamples) {
        _acceptSample(sample);
      }
      _startingSamples.clear();
      _notify();
    } catch (_) {
      try {
        await provider.stop();
      } catch (_) {}
      if (!_closed && revision == _revision) {
        _gate.reset(null);
        _startingSamples.clear();
        state = SensorSessionState.error;
        lastError = 'Sensor start failed; listeners cleaned up.';
        _notify();
      }
    }
  }

  void _onSample(SensorSample sample) {
    if (_closed || !_visible || !_wantsRun) return;
    if (state == SensorSessionState.starting) {
      if (_startingSamples.length < 128) {
        _startingSamples.add(sample);
      } else {
        rejectedEvents++;
      }
      return;
    }
    _acceptSample(sample);
  }

  void _acceptSample(SensorSample sample) {
    if (state != SensorSessionState.running || !_gate.accept(sample)) {
      rejectedEvents++;
      return;
    }
    latest[sample.kind] = sample;
    _observations.add(sample);
    if (sample.kind == SensorKind.stepDetector) detectorEvents++;
    if (sample.kind == SensorKind.stepCounter) {
      if (counterRaw != null && sample.values.single < counterRaw!) {
        counterResets++;
      }
      counterRaw = sample.values.single;
      // Raw cumulative reading only: never synthesize steps or resume backlog.
    }
    if (_recent.length == 128) _recent.removeFirst();
    _recent.addLast(sample);
    _displayTimer ??= Timer(displayInterval, () {
      _displayTimer = null;
      _notify();
    });
  }

  void _onStatus(SensorProviderStatus status) {
    if (_closed) return;
    if (state != SensorSessionState.starting &&
        status.generation != _gate.generation) {
      return;
    }
    if (status.phase == SensorProviderPhase.error ||
        status.phase == SensorProviderPhase.recoverableError ||
        status.phase == SensorProviderPhase.overflow) {
      if (status.phase == SensorProviderPhase.overflow) overflowEvents++;
      lastError = status.message;
      _notify();
    }
    if (status.phase == SensorProviderPhase.error) {
      _providerFailure(status.message);
      return;
    }
    if (status.phase == SensorProviderPhase.paused ||
        status.phase == SensorProviderPhase.stopped) {
      if (state == SensorSessionState.running ||
          state == SensorSessionState.starting) {
        unawaited(pause());
      }
    }
  }

  void _providerFailure(String message) {
    if (_closed) return;
    lastError = message;
    unawaited(
      stop().then((_) {
        if (!_closed) {
          state = SensorSessionState.error;
          _notify();
        }
      }),
    );
  }

  Future<void> _halt(SensorSessionState next, {required bool forgetIntent}) {
    if (_closed) return Future.value();
    _revision++;
    if (forgetIntent) _wantsRun = false;
    _gate.reset(null);
    _startingSamples.clear();
    _displayTimer?.cancel();
    _displayTimer = null;
    state = next;
    _notify();
    return _serial(() async {
      try {
        await provider.stop();
      } catch (_) {
        if (!_closed) {
          state = SensorSessionState.error;
          lastError = 'Native stop failed; event subscription cancelled.';
          _notify();
        }
      }
    });
  }

  Future<void> stop() => _halt(SensorSessionState.idle, forgetIntent: true);
  Future<void> pause() => _halt(SensorSessionState.paused, forgetIntent: false);
  Future<void> resume() {
    if (_closed || !_wantsRun || !_visible) return Future.value();
    return start(_config);
  }

  /// Combine app foreground AND route visibility at the UI boundary.
  Future<void> setVisible(bool visible) {
    if (_visible == visible) return Future.value();
    _visible = visible;
    // Returning from a covered route/background never silently starts sensors.
    // The user explicitly presses Resume; that re-probes permissions/capability.
    return !visible && _wantsRun ? pause() : Future.value();
  }

  Future<void> close() {
    if (_shutdown case final future?) return future;
    _closed = true;
    _revision++;
    _wantsRun = false;
    _gate.reset(null);
    _displayTimer?.cancel();
    state = SensorSessionState.disposed;
    return _shutdown = _serial(() async {
      await _samples.cancel();
      await _statuses.cancel();
      await _observations.close();
      await provider.dispose();
    });
  }

  @override
  void dispose() {
    unawaited(close().catchError((Object _) {}));
    super.dispose();
  }
}
