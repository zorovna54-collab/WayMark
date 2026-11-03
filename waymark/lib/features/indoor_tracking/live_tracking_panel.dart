import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';

import 'indoor_position.dart';
import 'indoor_tracking_controller.dart';
import 'pdr_engine.dart';
import 'sensors/sensor_models.dart';
import 'tracking_guidance.dart';
import 'tracking_graph.dart';
import 'map_readiness.dart';
import 'published_live_preflight.dart';
import 'debug/pilot_evidence_panel.dart';
import 'debug/pilot_evidence.dart';
export 'tracking_guidance.dart'
    show trackingStatusLabel, trackingReasonLabel, confidenceLabel;

class LiveTrackingPanel extends StatefulWidget {
  const LiveTrackingPanel({
    super.key,
    required this.controller,
    required this.onScan,
    required this.onManual,
    this.readiness,
    this.pilotEvidence,
  });
  final IndoorTrackingController controller;
  final Future<void> Function() onScan;
  final Future<void> Function() onManual;
  final MapReadinessReport? readiness;
  final PilotEvidenceSession? pilotEvidence;
  @override
  State<LiveTrackingPanel> createState() => _LiveTrackingPanelState();
}

class _LiveTrackingPanelState extends State<LiveTrackingPanel>
    with WidgetsBindingObserver {
  final _stride = TextEditingController(text: '0.70');
  final _walkMeters = TextEditingController(),
      _walkSteps = TextEditingController();
  String? _anchor, _edge, _error;
  String? _lastPoseNode, _lastChoice;
  String? _lastHoldReason;
  int _lastGeneration = 0, _setupStep = 0;
  bool _setupOpen = true;
  String _lastGuidedReason = '';
  bool _straight = false,
      _manualDirection = false,
      _stayedStill = false,
      _reverse = false,
      _busy = false;
  bool _appActive = true, _routeActive = true, _lastVisible = true;
  IndoorTrackingController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appActive =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeActive = ModalRoute.isCurrentOf(context) ?? true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _visibility();
    });
  }

  void _visibility() {
    final visible = _appActive && _routeActive;
    if (visible != _lastVisible) {
      _lastVisible = visible;
      unawaited(c.setVisible(visible));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _visibility();
  }

  Future<void> _run(FutureOr<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() => _error = null);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Chưa thực hiện được. Giữ vị trí cũ; dùng manual/QR.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stride.dispose();
    _walkMeters.dispose();
    _walkSteps.dispose();
    super.dispose();
  }

  void _go(int step) => setState(() {
    _setupStep = step;
    _setupOpen = true;
    _error = null;
  });

  Future<void> _recover(TrackingRecovery action) async {
    switch (action) {
      case TrackingRecovery.anchor:
        _go(0);
      case TrackingRecovery.sensors:
        _go(1);
      case TrackingRecovery.stride:
        _go(2);
      case TrackingRecovery.direction:
        _go(3);
      case TrackingRecovery.manual:
        await widget.onManual();
      case TrackingRecovery.none:
        break;
    }
  }

  Widget _button(String label, Key key, FutureOr<void> Function() action) =>
      OutlinedButton(
        key: key,
        onPressed: _busy ? null : () => _run(action),
        child: Text(label),
      );

  String _edgeLabel(TrackingEdge e, int index) {
    final previous = c.position.value?.travelDirection;
    final turn = previous == null || e.bearing == null
        ? 'Hướng'
        : angleDifference(e.bearing!, previous) < .6
        ? 'Đi thẳng'
        : angleDifference(e.bearing!, previous) > 2.5
        ? 'Quay lại'
        : 'Rẽ';
    final recommended = c.recommendedEdgeAt(e.from)?.id == e.id
        ? ' • tuyến gợi ý'
        : '';
    return '${index + 1}. $turn ${c.graph.nodes[e.from]!.name} → ${c.graph.nodes[e.to]!.name}$recommended';
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final p = c.position.value, graph = c.graph;
      final atDestination =
          p?.nodeId != null && p?.nodeId == c.destinationNodeId;
      if (_lastPoseNode != p?.nodeId) {
        _lastPoseNode = p?.nodeId;
        _anchor = null;
      }
      final anchor = _anchor ?? p?.nodeId ?? graph.nodes.values.first.id;
      final exits = c.candidates
          .where((e) => graph.nodes[e.to]!.floorKey == p?.floorKey)
          .toList();
      final transitions = c.candidates.where(graph.isTransition).toList();
      final choices = p?.edgeId != null ? [graph.edges[p!.edgeId]!] : exits;
      final selected = choices.any((e) => e.id == _edge)
          ? _edge
          : choices
                .where((e) => widget.readiness?.eligible(e.id) ?? true)
                .firstOrNull
                ?.id;
      if (_lastChoice != selected) {
        _lastChoice = selected;
        _straight =
            selected != null &&
            c.matcher.confirmedStraightEdges.contains(selected);
      }
      if (_lastGeneration != c.pdr.generation) {
        _lastGeneration = c.pdr.generation;
        _stayedStill = false;
        _reverse = false;
      }
      if (!c.canIntegrate && _lastHoldReason != c.reason) {
        _lastHoldReason = c.reason;
        _stayedStill = false;
      }
      if (_lastGuidedReason != c.reason) {
        if (c.reason == 'estimated' &&
            _lastGuidedReason == 'candidateNodeConfirm') {
          _setupOpen = false;
        }
        _lastGuidedReason = c.reason;
        if (!atDestination &&
            (c.reason == 'junctionConfirmation' ||
                c.reason == 'candidateNodeConfirm')) {
          _setupOpen = true;
          _setupStep = 3;
        } else if (c.reason == 'anchorAged' ||
            c.reason == 'sensorOverflow' ||
            c.reason == 'confirmNewFloor') {
          _setupOpen = true;
          _setupStep = 0;
        }
      }
      final guidance = atDestination
          ? const TrackingGuidance(
              'Vị trí đang ở điểm cuối theo ước lượng hoặc xác nhận của bạn. Quét QR ở đích hoặc về manual để xác nhận hoàn tất. Chấm xanh không tự xác nhận đã đến.',
              TrackingRecovery.manual,
              'Về manual / QR',
            )
          : c.reason == 'qrCorrectionRejected'
          ? qrTrackingGuidance(c.lastError ?? c.reason)
          : trackingGuidance(c.reason);
      final currentFloor = graph.floors[p?.floorKey]?.name ?? 'Chưa có vị trí';
      final remaining = c.estimatedRouteRemaining;
      final missing = <String>[
        if (p == null ||
            c.requiresAnchor ||
            p.kind == PositionKind.floorTransition)
          'Bước 1: xác nhận đúng điểm và tầng đang đứng.',
        if (!c.sensorRunning) 'Bước 2: cấp quyền và bật cảm biến bước.',
        if (!c.strideConfirmed) 'Bước 3: xác nhận chiều dài bước (mét/bước).',
        if (selected == null) 'Bước 4: chọn hành lang nối từ vị trí hiện tại.',
        if (selected != null && widget.readiness?.eligible(selected) == false) 'Đoạn này chưa đủ điều kiện dữ liệu. Chọn đoạn phù hợp hoặc dùng manual/QR.',
        if (selected != null && !_straight)
          'Bước 4: đối chiếu và xác nhận hành lang thẳng, mét phù hợp.',
        if (p?.edgeId != null && !_stayedStill)
          'Bước 4: xác nhận chưa đổi vị trí khi dừng; nếu đã đi hãy về bước 1.',
        if (!_manualDirection && !c.orientationFresh) 'Bước 4: chờ hướng điện thoại mới, giữ máy gần nằm ngang; hoặc chọn chiều thủ công thử nghiệm.',
      ];
      final contents = <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Chọn điểm và tầng bạn thực sự đang đứng. Xác nhận thủ công không phải QR xác minh qua server.',
            ),
            DropdownButtonFormField<String>(
              key: ValueKey('live-anchor-${p?.nodeId}'),
              initialValue: anchor,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Điểm đang đứng • xác nhận thủ công',
              ),
              items: [
                for (final n in graph.nodes.values)
                  DropdownMenuItem(
                    value: n.id,
                    child: Text(
                      '${graph.floors[n.floorKey]!.name} • ${n.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _busy ? null : (v) => setState(() => _anchor = v),
            ),
            _button(
              'Tôi xác nhận đang ở điểm này (thủ công)',
              const Key('live-confirm-anchor'),
              () => c.manualAnchor(anchor),
            ),
            if (c.qr.available)
              _button(
                'Quét QR Published để xác minh vị trí',
                const Key('live-setup-qr'),
                widget.onScan,
              ),
            if (!c.qr.available)
              const Text(
                'Local pilot không có QR server; mốc luôn được ghi là thủ công.',
              ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Cảm biến bước: ${c.sensors.capabilities == null
                  ? 'chưa kiểm tra'
                  : c.sensors.capabilities!.forKind(SensorKind.stepDetector).available
                  ? 'có trên máy'
                  : 'không có'}. Quyền: ${c.sensors.permission?.name ?? 'chưa kiểm tra'}.',
            ),
            const Text(
              'Chỉ Step Detector được dùng để tiến vị trí. Nếu quyền đã bị chặn, bạn có thể bật lại quyền Nhận diện hoạt động trong Cài đặt Android của ứng dụng.',
            ),
            _button(
              'Kiểm tra cảm biến (không xin quyền)',
              const Key('live-probe'),
              c.sensors.refresh,
            ),
            _button(
              'Quyền bước chân',
              const Key('live-permission'),
              c.requestPermission,
            ),
            if (c.sensorRunning)
              const Text(
                'Cảm biến đã bật. Chọn Tiếp theo để chuẩn bị bước chân.',
              )
            else
              _button(
                'Bật / Tiếp tục cảm biến',
                const Key('live-start'),
                c.startSensors,
              ),
            if (c.status == TrackingStatus.sensorUnavailable ||
                c.status == TrackingStatus.permissionDenied)
              const Text(
                'Bạn vẫn có thể dùng nút Về manual / QR bên trên. Không tạo bước giả để thay thế.',
              ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Chiều dài mỗi bước không giống nhau giữa mọi người. 0,70 m dưới đây chỉ là gợi ý chưa đo; cần bấm xác nhận mới áp dụng.',
            ),
            TextField(
              controller: _stride,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Chiều dài bước (mét/bước)',
              ),
            ),
            TextField(
              controller: _walkMeters,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Hoặc quãng đường đo thật (m), tùy chọn',
              ),
            ),
            TextField(
              controller: _walkSteps,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Số bước đếm tay trên quãng đo',
              ),
            ),
            const Text(
              'Chỉ dùng phép đo đi liên tục đã hoàn tất. Nếu gián đoạn, đo lại; để trống cả hai ô đo để nhập mét/bước trực tiếp.',
            ),
            _button(
              'Xác nhận chiều dài bước (lưu trong phiên)',
              const Key('live-save-stride'),
              () {
                double parse(String s) =>
                    double.tryParse(s.trim().replaceAll(',', '.')) ??
                    double.nan;
                final calibration =
                    _walkMeters.text.trim().isNotEmpty ||
                        _walkSteps.text.trim().isNotEmpty
                    ? StrideCalibration.fromWalk(
                        parse(_walkMeters.text),
                        int.tryParse(_walkSteps.text) ?? 0,
                      )
                    : StrideCalibration(parse(_stride.text));
                c.setStride(calibration);
                _stride.text = calibration.meters.toStringAsFixed(3);
              },
            ),
            if (c.strideConfirmed)
              Text(
                'Đã xác nhận: ${c.pdr.stride!.meters.toStringAsFixed(3)} mét/bước.',
              ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              p?.source == PositionSource.pdr && p?.nodeId != null
                  ? 'Bạn có thể đang gần một điểm giao. Chọn hành lang đang đi. Điểm này vẫn là ước lượng; việc chọn hướng không đặt lại mốc hay giới hạn 40 bước.'
                  : 'Chọn hành lang sắp đi, không chọn chỉ vì đó là tuyến gợi ý. Số lựa chọn tương ứng dấu trên bản đồ.',
            ),
            if (choices.isNotEmpty)
              DropdownButtonFormField<String>(
                key: ValueKey('live-edge-${p?.nodeId}-${p?.edgeId}'),
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Hành lang thực tế',
                ),
                items: [
                  for (var i = 0; i < choices.length; i++)
                    DropdownMenuItem(
                      value: choices[i].id,
                      enabled:
                          widget.readiness?.eligible(choices[i].id) ?? true,
                      child: Text(
                        _edgeLabel(choices[i], i),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy ? null : (v) => setState(() => _edge = v),
              ),
            if (selected != null)
              CheckboxListTile(
                value: _straight,
                onChanged: (v) => setState(() => _straight = v ?? false),
                title: const Text(
                  'Đã đối chiếu thực tế: hành lang thẳng, mét đúng và không xuyên vật cản.',
                ),
              ),
            for (final e in choices.where(
              (e) => widget.readiness?.eligible(e.id) == false,
            ))
              Text(
                '${graph.nodes[e.from]!.name} → ${graph.nodes[e.to]!.name}: ${widget.readiness!.issues.where((i) => i.edge == e.id).firstOrNull?.message ?? 'Chưa đủ dữ liệu Live; dùng manual/QR.'}',
              ),
            const Text(
              'Hướng đỉnh vật lý của điện thoại theo hành lang, giữ gần nằm ngang. Đổi tay/bỏ túi/đi lùi cần xác nhận lại. Quay máy không chứng minh đã rẽ.',
            ),
            CheckboxListTile(
              value: _manualDirection,
              onChanged: (v) => setState(() => _manualDirection = v ?? false),
              title: const Text(
                'Chọn chiều thủ công nếu hướng máy không tin cậy (giả định thử nghiệm, luôn chưa chắc chắn)',
              ),
            ),
            if (p?.edgeId != null) ...[
              CheckboxListTile(
                value: _stayedStill,
                onChanged: (v) => setState(() => _stayedStill = v ?? false),
                title: const Text(
                  'Tôi chưa đổi vị trí khi tạm dừng / xác nhận lại tại chỗ',
                ),
              ),
              CheckboxListTile(
                value: _reverse,
                onChanged: (v) => setState(() => _reverse = v ?? false),
                title: const Text('Tôi sẽ đi ngược chiều hành lang đang đứng'),
              ),
            ],
            for (final e in transitions)
              _button(
                'Chuyển tầng: ${graph.nodes[e.to]!.name} • cần xác nhận ở tầng mới',
                ValueKey('live-transition-${e.id}'),
                () => c.confirmEdge(e.id, straightGeometry: false),
              ),
            if (choices.isEmpty && transitions.isEmpty)
              const Text(
                'Chưa có hành lang phù hợp. Quay bước 1 xác nhận vị trí hoặc quét QR.',
              ),
            ExpansionTile(
              title: const Text(
                'Đối chiếu thêm hành lang trước khi đi (tùy chọn)',
              ),
              children: [
                const Text(
                  'Chỉ đánh dấu đoạn đã kiểm tra thật. Cho phép tự tiếp tục khi candidate duy nhất; không bảo đảm tự đi qua mọi ngã rẽ.',
                ),
                for (final e in graph.edges.values.where(
                  (e) =>
                      e.geometryEligible &&
                      e.active &&
                      graph.nodes[e.from]!.floorKey == p?.floorKey,
                ))
                  CheckboxListTile(
                    value: c.matcher.confirmedStraightEdges.contains(e.id),
                    title: Text(
                      '${graph.nodes[e.from]!.name} → ${graph.nodes[e.to]!.name} • ${e.meters} m',
                    ),
                    onChanged: (v) {
                      c.confirmGeometry(e.id, v ?? false);
                      if (e.id == selected) {
                        setState(() => _straight = v ?? false);
                      }
                    },
                  ),
              ],
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (missing.isNotEmpty) ...[
              const Text(
                'Chưa sẵn sàng bắt đầu:',
                key: Key('live-missing-conditions'),
              ),
              for (final text in missing) Text('• $text'),
            ] else
              const Text(
                'Đã đủ điều kiện chuẩn bị. Hướng máy theo hành lang đã chọn rồi bắt đầu; vị trí tiếp theo vẫn là ước lượng.',
              ),
            FilledButton(
              key: const Key('live-align'),
              onPressed: _busy
                  ? null
                  : () => _run(() {
                      if (missing.isNotEmpty) {
                        throw FormatException(missing.first);
                      }
                      c.confirmEdge(
                        selected!,
                        straightGeometry: _straight,
                        manualDirection: _manualDirection,
                        stayedStill: _stayedStill,
                        reverse: _reverse,
                      );
                      setState(() => _setupOpen = false);
                    }),
              child: const Text('Bắt đầu / tiếp tục Live Navigation'),
            ),
          ],
        ),
      ];
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.readiness != null)
                PublishedLivePreflight(
                  report: widget.readiness!,
                  surveyed: c.matcher.confirmedStraightEdges,
                  sensorMessage: c.sensorRunning
                      ? 'Step Detector đã đăng ký và cảm biến đang bật.'
                      : 'Cảm biến chưa sẵn sàng; kiểm tra quyền và đăng ký tại bước 2.',
                  onManual: () => _run(widget.onManual),
                ),
              Text(
                'Live • ${trackingStatusLabel(c.status)}',
                key: const Key('live-status'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('${confidenceLabel(p?.confidence)} • $currentFloor'),
              if (graph.localPilot)
                const Text('LOCAL PILOT • mốc thủ công, sơ đồ tổng hợp'),
              if (p?.edgeId != null)
                Text(
                  'Đang ước lượng: ${graph.nodes[graph.edges[p!.edgeId]!.from]!.name} → ${graph.nodes[graph.edges[p.edgeId]!.to]!.name}',
                ),
              Text(guidance.message, key: const Key('live-next-action')),
              if (c.pdr.manualBearing != null)
                const Text(
                  'Chiều đi do bạn khai báo; đổi hướng phải xác nhận lại.',
                ),
              if (remaining != null)
                Text(
                  'Còn khoảng ${remaining.toStringAsFixed(1)} m theo tuyến gợi ý (ước lượng; không xác nhận đã đến).',
                ),
              if (c.offRoute)
                const Text(
                  'Ước lượng ngoài tuyến gợi ý. Xác nhận điểm / QR trước khi tính lại đường.',
                ),
              if (c.budgetNearLimit)
                Text(
                  'Gần giới hạn: còn ${c.remainingBudget} bước ước lượng trước khi cần xác nhận lại vị trí.',
                  key: const Key('live-budget-warning'),
                ),
              Text(
                c.sensorRunning
                    ? 'Cảm biến đang bật • chấm chỉ tiến khi có bước hợp lệ.'
                    : 'Cảm biến đã dừng • không ước lượng khi bạn đi trong lúc dừng.',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (guidance.action != TrackingRecovery.none &&
                      guidance.action != TrackingRecovery.manual)
                    _button(
                      guidance.button,
                      const Key('live-recover'),
                      () => _recover(guidance.action),
                    ),
                  _button(
                    c.sensorRunning ? 'Tạm dừng' : 'Chuẩn bị tiếp tục',
                    const Key('live-pause'),
                    () async {
                      if (c.sensorRunning) {
                        await c.pause();
                      } else {
                        _go(1);
                      }
                    },
                  ),
                  _button(
                    'Xác nhận lại vị trí',
                    const Key('live-reanchor'),
                    () => _go(0),
                  ),
                  if (c.qr.available)
                    _button(
                      'QR hiệu chỉnh',
                      const Key('live-qr'),
                      widget.onScan,
                    ),
                  _button(
                    'Về manual / QR',
                    const Key('live-manual'),
                    widget.onManual,
                  ),
                ],
              ),
              if (_error != null)
                Text(
                  _error!,
                  key: const Key('live-setup-error'),
                  style: const TextStyle(color: Colors.red),
                ),
              TextButton(
                key: const Key('live-calibration'),
                onPressed: () => setState(() => _setupOpen = !_setupOpen),
                child: Text(
                  _setupOpen
                      ? 'Thu gọn hướng dẫn chuẩn bị'
                      : 'Mở 5 bước chuẩn bị / điều chỉnh',
                ),
              ),
              if (_setupOpen)
                Stepper(
                  key: const Key('live-guided-setup'),
                  currentStep: _setupStep,
                  physics: const NeverScrollableScrollPhysics(),
                  onStepTapped: _busy ? null : _go,
                  controlsBuilder: (context, details) => Wrap(
                    spacing: 8,
                    children: [
                      if (_setupStep < 4)
                        TextButton(
                          key: ValueKey('live-next-${details.stepIndex}'),
                          onPressed: _busy
                              ? null
                              : () {
                                  final ready = switch (_setupStep) {
                                    0 =>
                                      p != null &&
                                          !c.requiresAnchor &&
                                          p.kind !=
                                              PositionKind.floorTransition,
                                    1 => c.sensorRunning,
                                    2 => c.strideConfirmed,
                                    _ => selected != null && _straight,
                                  };
                                  if (!ready) {
                                    setState(
                                      () => _error =
                                          'Hãy hoàn tất bước ${_setupStep + 1} trước khi tiếp tục.',
                                    );
                                    return;
                                  }
                                  _go(_setupStep + 1);
                                },
                          child: const Text('Tiếp theo'),
                        ),
                      if (_setupStep > 0)
                        TextButton(
                          key: ValueKey('live-back-${details.stepIndex}'),
                          onPressed: _busy ? null : () => _go(_setupStep - 1),
                          child: const Text('Quay lại'),
                        ),
                    ],
                  ),
                  steps: [
                    for (var i = 0; i < 5; i++)
                      Step(
                        title: Text(
                          const [
                            'Xác nhận vị trí',
                            'Chuẩn bị cảm biến',
                            'Hiệu chuẩn bước chân',
                            'Chọn hướng bắt đầu',
                            'Bắt đầu Live Navigation',
                          ][i],
                        ),
                        isActive: _setupStep == i,
                        content: contents[i],
                      ),
                  ],
                ),
              if (kDebugMode)
                ExpansionTile(
                  key: const Key('live-diagnostics'),
                  title: const Text('Diagnostics • nâng cao'),
                  children: [
                    if (const bool.fromEnvironment('WAYMARK_LIVE_TEST'))
                      PilotEvidencePanel(
                        session: widget.pilotEvidence,
                        mode: c.graph.localPilot
                            ? PilotMode.local
                            : PilotMode.published,
                        controller: c,
                        readiness: widget.readiness,
                      ),
                    Text(
                      'Thiết bị: ${c.sensors.capabilities?.device ?? 'unknown'} API ${c.sensors.capabilities?.androidApi ?? 0}',
                    ),
                    Text(
                      'Sensor • permission=${c.sensors.permission?.name ?? 'unknown'}; detector registration=${c.sensors.result?.registrations.where((r) => r.kind == SensorKind.stepDetector).firstOrNull?.state.name ?? 'notRequested'}',
                    ),
                    Text(
                      'Steps=${c.sensors.detectorEvents}; last accepted ns=${c.lastAcceptedStepNs}; orientation fresh=${c.orientationFresh}; overflow=${c.sensors.overflowEvents}',
                    ),
                    Text(
                      'PDR • stride=${c.pdr.stride?.meters}; integrated=${c.integratedDistance.toStringAsFixed(2)} m; heading aligned=${c.pdr.heading != null}; accepted/rejected movements=${c.acceptedMovements}/${c.rejectedMovements}',
                    ),
                    Text(
                      'Map matching • candidate count=${c.candidates.length}; hold=${c.holdReason}; confidence=${p?.confidence.name}; edge=${p?.edgeId}; progress=${p?.progressMeters}',
                    ),
                    Text(
                      'Tracking • state=${c.status.name}; reason=${c.reason}; transition=${c.lastTransition}; pause=${c.pauseReason}; generation=${c.pdr.generation}; reanchors=${c.reanchors}; budget=${c.stepsSinceAnchor}/${IndoorTrackingController.movementBudget}',
                    ),
                    Text(
                      'QR=${c.lastCorrection}; corrections=${c.corrections}; reroutes=${c.reroutes}',
                    ),
                    Text('Last error code: ${c.lastError ?? 'none'}'),
                    for (final s
                        in c.sensors.capabilities?.sensors ??
                            const <SensorCapability>[])
                      Text(
                        '${s.kind.name}: ${s.available ? 'available' : 'missing'}',
                      ),
                    const Text('Timeline • mã nội bộ, tối đa 96 sự kiện'),
                    for (final e in c.timeline.events.reversed.take(16))
                      Text(e.sanitized),
                    TextButton.icon(
                      key: const Key('live-copy-diagnostics'),
                      onPressed: () => _run(
                        () => Clipboard.setData(
                          ClipboardData(text: c.sanitizedDiagnostics()),
                        ),
                      ),
                      icon: const Icon(Icons.copy),
                      label: const Text('Sao chép chẩn đoán đã làm sạch'),
                    ),
                    const Text(
                      'Không xuất QR/JWT, ID vị trí, tên điểm, tọa độ hoặc trace. Không tự upload. Ảnh chụp panel này có thể chứa thông tin vị trí.',
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
    },
  );
}
