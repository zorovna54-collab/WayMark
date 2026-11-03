import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../sensors/sensor_models.dart';
import '../sensors/sensor_provider.dart';
import '../sensors/sensor_session_controller.dart';

/// Install only in the standalone debug application, never the product router.
final sensorProbeRouteObserver = RouteObserver<ModalRoute<void>>();

class SensorProbePage extends StatefulWidget {
  const SensorProbePage({super.key, this.provider});
  final SensorProvider? provider;
  @override
  State<SensorProbePage> createState() => _SensorProbePageState();
}

class _SensorProbePageState extends State<SensorProbePage>
    with WidgetsBindingObserver, RouteAware {
  late final SensorSessionController _session;
  ModalRoute<void>? _route;
  bool _appActive = true, _routeVisible = true, _rawDiagnostics = false;
  bool _permissionBusy = false;

  @override
  void initState() {
    super.initState();
    if (!kDebugMode) {
      _session = SensorSessionController(UnsupportedSensorProvider());
      return;
    }
    _session = SensorSessionController(
      widget.provider ?? createSensorProvider(),
    );
    WidgetsBinding.instance.addObserver(this);
    _appActive =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    unawaited(_session.refresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (_route != route) {
      if (_route != null) sensorProbeRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) sensorProbeRouteObserver.subscribe(this, route);
    }
    _routeVisible = route?.isCurrent ?? true;
    _updateVisibility();
  }

  void _updateVisibility() {
    unawaited(_session.setVisible(_appActive && _routeVisible));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _updateVisibility();
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _updateVisibility();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _updateVisibility();
  }

  Future<void> _permission() async {
    setState(() => _permissionBusy = true);
    try {
      await _session.requestPermission();
    } finally {
      if (mounted) setState(() => _permissionBusy = false);
    }
  }

  SensorConfig _config() {
    final capabilities = _session.capabilities;
    final rotation =
        capabilities?.forKind(SensorKind.rotationVector).available == true
        ? SensorKind.rotationVector
        : SensorKind.gameRotationVector;
    return SensorConfig(
      kinds: {
        SensorKind.stepDetector,
        SensorKind.stepCounter,
        rotation,
        if (_rawDiagnostics) SensorKind.accelerometer,
        if (_rawDiagnostics) SensorKind.gyroscope,
      },
    );
  }

  String _registration(SensorKind kind) {
    final registration = _session.result?.registrations
        .where((r) => r.kind == kind)
        .firstOrNull;
    if (registration == null) return 'notRequested';
    if (registration.state == RegistrationState.registered &&
        _session.state != SensorSessionState.running) {
      return 'stopped';
    }
    return registration.state.name;
  }

  @override
  void dispose() {
    sensorProbeRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('Debug only')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('WayMark • Sensor probe (DEBUG)')),
      body: AnimatedBuilder(
        animation: _session,
        builder: (context, _) {
          final state = _session.state;
          final busy = state == SensorSessionState.starting;
          final running = state == SensorSessionState.running;
          final caps = _session.capabilities;
          final result = _session.result;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Chỉ quan sát cảm biến. Không định vị, không tính quãng đường.',
              ),
              Text(
                'Thiết bị: ${caps?.device ?? 'Đang kiểm tra…'} • API ${caps?.androidApi ?? '—'}',
              ),
              Text('Trạng thái: ${state.name}', key: const Key('sensor-state')),
              Text(
                'Activity permission: ${_session.permission?.name ?? 'unknown'}',
              ),
              const Text(
                'Orientation là tư thế điện thoại, không phải hướng người đi.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: const Key('sensor-permission'),
                    onPressed: _permissionBusy || busy || running
                        ? null
                        : _permission,
                    child: Text(
                      _permissionBusy
                          ? 'Đang xin quyền…'
                          : 'Xin quyền bước chân',
                    ),
                  ),
                  FilledButton(
                    key: const Key('sensor-start'),
                    onPressed:
                        running || busy || _permissionBusy || caps == null
                        ? null
                        : () => _session.start(_config()),
                    child: const Text('Start'),
                  ),
                  OutlinedButton(
                    key: const Key('sensor-stop'),
                    onPressed: () => _session.stop(),
                    child: const Text('Stop'),
                  ),
                  OutlinedButton(
                    key: const Key('sensor-pause'),
                    onPressed: running ? () => _session.pause() : null,
                    child: const Text('Pause'),
                  ),
                  OutlinedButton(
                    key: const Key('sensor-resume'),
                    onPressed:
                        state == SensorSessionState.paused && !_permissionBusy
                        ? () => _session.resume()
                        : null,
                    child: const Text('Resume'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => _session.refresh(),
                    child: const Text('Probe lại'),
                  ),
                ],
              ),
              if (_session.permission == MotionPermission.denied)
                const Text(
                  'Quyền bước chân bị từ chối. Nhấn nút để thử lại hoặc đổi quyền trong Android Settings. Orientation vẫn có thể hoạt động.',
                ),
              if (state == SensorSessionState.unavailable)
                const Text(
                  'Không có cảm biến đăng ký được. Navigation tĩnh/QR hiện tại vẫn độc lập.',
                ),
              CheckboxListTile(
                title: const Text('Raw accelerometer/gyroscope diagnostics'),
                value: _rawDiagnostics,
                onChanged: running || busy
                    ? null
                    : (value) =>
                          setState(() => _rawDiagnostics = value ?? false),
              ),
              Text('Generation: ${result?.generation ?? '—'}'),
              Text(
                'Step Detector events: ${_session.detectorEvents}',
                key: const Key('sensor-step-count'),
              ),
              Text(
                'Step Counter raw: ${_session.counterRaw ?? '—'} (không cộng vào Detector)',
              ),
              Text(
                'Counter resets: ${_session.counterResets} • rejected: ${_session.rejectedEvents}',
              ),
              Text(
                'Buffer: ${_session.recent.length}/128; hiển thị tối đa 5 lần/giây.',
              ),
              if (_session.lastError != null)
                Text(
                  'Lỗi: ${_session.lastError}',
                  key: const Key('sensor-error'),
                ),
              const Divider(),
              const Text(
                'Capability / registration (không phải chứng nhận tracking ready)',
              ),
              for (final kind in SensorKind.values)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${kind.name}: ${caps?.forKind(kind).available == true ? 'available' : 'unavailable'}',
                  ),
                  subtitle: Text(
                    [
                      if (caps != null)
                        '${caps.forKind(kind).name} / ${caps.forKind(kind).vendor}',
                      if (caps != null)
                        'minDelay=${caps.forKind(kind).minDelayUs}µs range=${caps.forKind(kind).maxRange} resolution=${caps.forKind(kind).resolution}',
                      'registration=${_registration(kind)}',
                      if (result != null)
                        result.registrations
                                .where((r) => r.kind == kind)
                                .firstOrNull
                                ?.reason ??
                            '',
                    ].where((s) => s.isNotEmpty).join('\n'),
                  ),
                ),
              const Divider(),
              for (final sample in _session.latest.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '${sample.kind.name}: ${sample.values}\n'
                    '${sample.units} • ${sample.referenceFrame} • accuracy=${sample.accuracy}\n'
                    'sensorNs=${sample.sensorTimestampNs}\n'
                    'nativeReceiveNs=${sample.nativeReceiveTimestampNs}\n'
                    'native delivery latencyNs=${sample.nativeDeliveryLatencyNs ?? 'invalid clock sample'}\n'
                    'generation=${sample.generation} sequence=${sample.sequence}',
                  ),
                ),
              const Text(
                'Latency trên chỉ đo sensor → native callback cùng đồng hồ; không bao gồm native → Dart. Không lưu file hoặc gửi mạng.',
              ),
            ],
          );
        },
      ),
    );
  }
}
