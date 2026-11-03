import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../indoor_tracking_controller.dart';
import '../map_readiness.dart';
import 'pilot_evidence.dart';
import 'field_trial_measurement.dart';

class PilotHandoffPage extends StatelessWidget {
  const PilotHandoffPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Published Pilot • checklist & báo cáo')),
    body: const SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: PilotEvidencePanel(mode: PilotMode.published),
      ),
    ),
  );
}

class PilotEvidencePanel extends StatefulWidget {
  const PilotEvidencePanel({
    super.key,
    required this.mode,
    this.controller,
    this.readiness,
    this.session,
  });
  final PilotMode mode;
  final IndoorTrackingController? controller;
  final MapReadinessReport? readiness;
  final PilotEvidenceSession? session;
  @override
  State<PilotEvidencePanel> createState() => _PilotEvidencePanelState();
}

class _PilotEvidencePanelState extends State<PilotEvidencePanel> {
  late PilotEvidenceSession session =
      widget.session ?? PilotEvidenceSession(mode: widget.mode);
  @override
  void didUpdateWidget(covariant PilotEvidencePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      if (oldWidget.session == null) session.dispose();
      session = widget.session ?? PilotEvidenceSession(mode: widget.mode);
    }
  }

  final fields = {
    for (final key in [
      'truth',
      'manual',
      'detector',
      'stride',
      'estimated',
      'before',
      'after',
      'falseStill',
    ])
      key: TextEditingController(),
  };
  String? error, copied;
  PhoneHold hold = PhoneHold.unknown;
  String uncertain = 'notRecorded',
      budget = 'notRecorded',
      reselected = 'notRecorded';
  @override
  void dispose() {
    if (widget.session == null) session.dispose();
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void _act(VoidCallback action) {
    try {
      action();
      setState(() {
        error = null;
        copied = null;
      });
    } on FormatException catch (e) {
      setState(() => error = e.message);
    }
  }

  void _saveMeasurement() {
    double number(String key) =>
        double.tryParse(fields[key]!.text.trim().replaceAll(',', '.')) ??
        double.nan;
    int integer(String key) => int.tryParse(fields[key]!.text.trim()) ?? -1;
    double? optional(String key) =>
        fields[key]!.text.trim().isEmpty ? null : number(key);
    bool? observed(String value) =>
        value == 'notRecorded' ? null : value == 'yes';
    session.setMeasurement(
      FieldTrialMeasurement(
        groundTruthMeters: number('truth'),
        manualSteps: integer('manual'),
        detectorEvents: integer('detector'),
        strideMeters: number('stride'),
        estimatedMeters: number('estimated'),
        endpointErrorBeforeQrMeters: optional('before'),
        endpointErrorAfterQrMeters: optional('after'),
        falseStepsStill: fields['falseStill']!.text.trim().isEmpty
            ? null
            : integer('falseStill'),
        hold: hold,
        uncertainObserved: observed(uncertain),
        budgetHeld: observed(budget),
        edgeReselected: observed(reselected),
      ),
    );
  }

  Widget _number(String key, String label) => TextField(
    key: ValueKey('pilot-field-$key'),
    controller: fields[key],
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label),
  );
  Widget _observation(
    String label,
    String value,
    ValueChanged<String> change,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: const [
      DropdownMenuItem(value: 'notRecorded', child: Text('Chưa ghi nhận')),
      DropdownMenuItem(value: 'yes', child: Text('Có')),
      DropdownMenuItem(value: 'no', child: Text('Không')),
    ],
    onChanged: (v) => setState(() => change(v!)),
  );
  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Text('Pilot toolkit chỉ có trong Live Test debug.');
    }
    return AnimatedBuilder(
      animation: session,
      builder: (_, child) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Bộ ghi nhận thử nghiệm • không tự upload',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text(
            'Mọi checklist mặc định NOT TESTED. PASS/FAIL do bạn quan sát và tự chọn; không phải xác minh tự động. Không dùng trạng thái này để chứng nhận độ chính xác.',
          ),
          if (widget.controller == null && widget.session == null)
            const Text(
              'Checklist này không nối một phiên tracking. Để có số liệu cảm biến, mở toolkit trong Diagnostics của Live Navigation.',
            ),
          if (widget.controller == null && widget.session != null)
            const Text(
              'Phiên Live đã đóng. Số liệu đã chốt trong bộ nhớ; hãy ghi checklist và sao chép trước khi rời Navigation.',
            ),
          ExpansionTile(
            title: const Text('Checklist Published Pilot (do người thử ghi)'),
            children: [
              for (final check in PilotCheck.values)
                DropdownButtonFormField<PilotCheckStatus>(
                  key: ValueKey('pilot-check-${check.name}'),
                  initialValue: session.checks[check],
                  decoration: InputDecoration(
                    labelText: pilotCheckLabel(check),
                  ),
                  items: [
                    for (final s in PilotCheckStatus.values)
                      DropdownMenuItem(
                        value: s,
                        child: Text(pilotStatusLabel(s)),
                      ),
                  ],
                  onChanged: (v) => session.mark(check, v!),
                ),
            ],
          ),
          DropdownButtonFormField<PilotPhase>(
            initialValue: session.phase,
            decoration: const InputDecoration(labelText: 'Giai đoạn thử'),
            items: [
              for (final p in PilotPhase.values)
                DropdownMenuItem(
                  value: p,
                  child: Text(switch (p) {
                    PilotPhase.preparation => 'Chuẩn bị',
                    PilotPhase.straightWalk => 'Đi thẳng',
                    PilotPhase.stationary => 'Đứng yên',
                    PilotPhase.rotateInPlace => 'Quay tại chỗ',
                    PilotPhase.reverseWalk => 'Đi ngược',
                    PilotPhase.qrCorrection => 'QR hiệu chỉnh',
                    PilotPhase.lifecycle => 'Pause/resume',
                    PilotPhase.fallback => 'Manual fallback',
                  }),
                ),
            ],
            onChanged: (v) => session.setPhase(v!),
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                key: const Key('pilot-begin'),
                onPressed: widget.session != null && widget.controller == null
                    ? null
                    : () => _act(
                        () => session.begin(
                          controller: widget.controller,
                          readiness: widget.readiness,
                        ),
                      ),
                child: const Text('Bắt đầu ghi nhận (không bật sensor)'),
              ),
              OutlinedButton(
                key: const Key('pilot-end'),
                onPressed: widget.session != null && widget.controller == null
                    ? null
                    : () => _act(
                        () => session.end(
                          controller: widget.controller,
                          readiness: widget.readiness,
                        ),
                      ),
                child: const Text('Chốt số liệu (không dừng sensor)'),
              ),
            ],
          ),
          Text(
            'Bắt đầu: ${session.startedAt?.toIso8601String() ?? 'chưa bắt đầu'} • Kết thúc: ${session.endedAt?.toIso8601String() ?? 'chưa chốt'}',
          ),
          if (widget.controller != null)
            Text(
              'Detector events: ${widget.controller!.sensors.detectorEvents}; displacement observations: ${widget.controller!.acceptedMovements}; rejected movement: ${widget.controller!.rejectedMovements}. Các số này khác nhau.',
            ),
          ExpansionTile(
            title: const Text(
              'Lượt đo thật • nhập số quan sát, không lấy fixture làm chuẩn',
            ),
            children: [
              const Text(
                'Đo hành lang 10–20 m bằng thước. Có thể nhập 0 m / 0 bước cho ca đứng yên; không chia cho 0. Sai lệch endpoint phải tự đo trước/sau QR, không tự đặt 0.',
              ),
              _number('truth', 'Quãng đường đo thật (m)'),
              _number('manual', 'Số bước đếm tay'),
              _number('detector', 'StepDetector events quan sát trong lượt'),
              _number('stride', 'Chiều dài bước đã cấu hình (m/bước)'),
              _number(
                'estimated',
                'Quãng đường WayMark ước lượng trong lượt (m)',
              ),
              _number('before', 'Sai lệch endpoint trước QR (m, tùy chọn)'),
              _number('after', 'Sai lệch endpoint sau QR (m, tùy chọn)'),
              _number('falseStill', 'False step khi đứng yên (tùy chọn)'),
              DropdownButtonFormField<PhoneHold>(
                initialValue: hold,
                decoration: const InputDecoration(
                  labelText: 'Cách cầm điện thoại',
                ),
                items: [
                  for (final h in PhoneHold.values)
                    DropdownMenuItem(
                      value: h,
                      child: Text(switch (h) {
                        PhoneHold.topForwardHorizontal =>
                          'Đỉnh máy hướng đi, gần nằm ngang',
                        PhoneHold.tilted => 'Cầm lệch',
                        PhoneHold.changedHand => 'Đổi tay',
                        PhoneHold.pocket => 'Bỏ túi',
                        PhoneHold.unknown => 'Chưa ghi nhận',
                      }),
                    ),
                ],
                onChanged: (v) => setState(() => hold = v!),
              ),
              _observation('Có uncertain?', uncertain, (v) => uncertain = v),
              _observation('Dừng vì budget?', budget, (v) => budget = v),
              _observation(
                'Cần chọn hành lang lại?',
                reselected,
                (v) => reselected = v,
              ),
              OutlinedButton(
                key: const Key('pilot-save-measurement'),
                onPressed: () => _act(_saveMeasurement),
                child: const Text('Ghi số đo vào báo cáo'),
              ),
              if (session.measurement case final m?)
                Text(
                  'Bias quãng đường: ${m.distanceBiasMeters.toStringAsFixed(2)} m; relative error: ${m.relativeDistanceError?.toStringAsFixed(3) ?? 'N/A (ground truth = 0)'}. Đây không phải sai lệch vị trí endpoint.',
                ),
            ],
          ),
          ExpansionTile(
            title: const Text('Ghi chú có cấu trúc (không nhập tên/URL/token)'),
            children: [
              for (final n in PilotNote.values)
                FilterChip(
                  label: Text(switch (n) {
                    PilotNote.falseSteps => 'Có false steps',
                    PilotNote.missedSteps => 'Có bước bỏ sót',
                    PilotNote.headingStale => 'Hướng cũ',
                    PilotNote.changedPhoneHold => 'Đổi cách cầm',
                    PilotNote.junctionHeld => 'Giữ ở giao lộ',
                    PilotNote.budgetHeld => 'Giữ vì budget',
                    PilotNote.imageUnavailable => 'Thiếu ảnh',
                    PilotNote.qrRejected => 'QR bị từ chối',
                    PilotNote.networkUnavailable => 'Mất kết nối',
                    PilotNote.lifecycleInterrupted => 'Lượt bị gián đoạn',
                  }),
                  selected: session.notes.contains(n),
                  onSelected: (v) => session.note(n, v),
                ),
            ],
          ),
          if (error != null)
            Text(
              error!,
              key: const Key('pilot-input-error'),
              style: const TextStyle(color: Colors.red),
            ),
          TextButton.icon(
            key: const Key('pilot-copy-report'),
            icon: const Icon(Icons.copy),
            label: const Text('Sao chép báo cáo thử nghiệm đã làm sạch'),
            onPressed: () async {
              try {
                await Clipboard.setData(
                  ClipboardData(
                    text: session.export(
                      controller: widget.controller,
                      readiness: widget.readiness,
                    ),
                  ),
                );
                if (mounted) {
                  setState(
                    () => copied = 'Đã sao chép; bạn tự chọn nơi gửi. Không upload tự động.',
                  );
                }
              } catch (_) {
                if (mounted) {
                  setState(
                    () => error = 'Chưa sao chép được báo cáo. Thử lại clipboard; không có dữ liệu được gửi tự động.',
                  );
                }
              }
            },
          ),
          if (copied != null) Text(copied!),
        ],
      ),
    );
  }
}
