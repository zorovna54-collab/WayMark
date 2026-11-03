import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/ai_graph_proposal.dart';
import '../route/floor_plan_canvas.dart';
import '../route/map_paint_scale.dart';
import 'ai_graph_review.dart';

class AiGraphReviewPanel extends StatefulWidget {
  const AiGraphReviewPanel({
    super.key,
    required this.review,
    required this.onEditNode,
    required this.onApply,
    this.enabled = true,
  });
  final AiGraphReview review;
  final Future<void> Function(int index) onEditNode;
  final ValueChanged<AiGraphBatch> onApply;
  final bool enabled;
  @override
  State<AiGraphReviewPanel> createState() => _AiGraphReviewPanelState();
}

class _AiGraphReviewPanelState extends State<AiGraphReviewPanel> {
  String? _selection, _error;
  Size _scene = const Size(1, 1);
  double _scale = 1;
  AiGraphReview get review => widget.review;
  void _act(VoidCallback action) {
    setState(() {
      try {
        action();
        _error = null;
      } on FormatException catch (e) {
        _error = e.message;
      }
    });
  }

  Map<String, Offset> get _points => {
    for (final n in review.input.existing) n.ref: Offset(n.x, n.y),
    for (final n in review.nodes) n.node.id: Offset(n.node.x, n.node.y),
  };
  String _label(String ref) {
    final existing = review.input.existing
        .where((n) => n.ref == ref)
        .firstOrNull;
    if (existing != null) return existing.label;
    final index = review.nodes.indexWhere((n) => n.node.id == ref);
    return index < 0 ? ref : 'P${index + 1} • ${review.nodes[index].node.name}';
  }

  void _pick(Offset p) {
    final screen = Offset(p.dx * _scene.width, p.dy * _scene.height);
    for (final (i, n) in review.nodes.indexed) {
      if (review.nodeStatus(n.node.id) == AiReviewStatus.rejected) continue;
      if ((screen - Offset(n.node.x * _scene.width, n.node.y * _scene.height))
                  .distance *
              _scale <=
          24) {
        setState(() => _selection = 'node:${n.node.id}');
        _details(
          'Node ${i + 1}: ${n.node.name}',
          '${n.evidence}\nChưa xác minh: ${n.node.uncertainty}',
        );
        return;
      }
    }
    for (final e in review.edges) {
      if (review.edgeStatus(e.id) == AiReviewStatus.rejected) continue;
      final a = _points[e.from], b = _points[e.to];
      if (a == null || b == null) continue;
      final start = Offset(a.dx * _scene.width, a.dy * _scene.height),
          end = Offset(b.dx * _scene.width, b.dy * _scene.height);
      final d = end - start;
      final t = d.distanceSquared == 0
          ? 0.0
          : (((screen - start).dx * d.dx + (screen - start).dy * d.dy) /
                    d.distanceSquared)
                .clamp(0.0, 1.0);
      if ((screen - (start + d * t)).distance * _scale <= 14) {
        setState(() => _selection = 'edge:${e.id}');
        _details(
          'Edge ${e.id}',
          '${_label(e.from)} → ${_label(e.to)}\n${e.evidence}\nChưa xác minh: ${e.uncertainty}',
        );
        return;
      }
    }
  }

  void _details(String title, String text) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> _edge(AiGraphEdge edge) async {
    var from = edge.from, to = edge.to, type = edge.type;
    AiEdgeDirection? direction = review.reviewedEdges[edge.id]?.direction;
    final meters = TextEditingController(
      text: review.reviewedEdges[edge.id]?.meters.toString() ?? '',
    );
    var confirmed = false;
    String? error;
    final refs = [
      ...review.input.existing.map((n) => n.ref),
      ...review.nodes.map((n) => n.node.id),
    ];
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: Text('Duyệt cạnh ${edge.id}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Bằng chứng AI: ${edge.evidence}\nChưa chắc: ${edge.uncertainty}',
                ),
                const Text(
                  'Chỉ cùng tầng. Mét do bạn nhập; không tính từ pixel. Accessibility: Unknown.',
                ),
                DropdownButtonFormField<String>(
                  key: const Key('ai-edge-from'),
                  initialValue: from,
                  isExpanded: true,
                  items: [
                    for (final ref in refs)
                      DropdownMenuItem(
                        value: ref,
                        child: Text(
                          _label(ref),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => from = v!,
                  decoration: const InputDecoration(labelText: 'Source node'),
                ),
                DropdownButtonFormField<String>(
                  key: const Key('ai-edge-to'),
                  initialValue: to,
                  isExpanded: true,
                  items: [
                    for (final ref in refs)
                      DropdownMenuItem(
                        value: ref,
                        child: Text(
                          _label(ref),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => to = v!,
                  decoration: const InputDecoration(labelText: 'Target node'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  items: [
                    for (final t in AiGraphEdge.types)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) => type = v!,
                  decoration: const InputDecoration(labelText: 'Loại cạnh'),
                ),
                TextField(
                  key: const Key('ai-edge-meters'),
                  controller: meters,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Khoảng cách đã kiểm tra (mét)',
                  ),
                ),
                DropdownButtonFormField<AiEdgeDirection>(
                  key: const Key('ai-edge-direction'),
                  initialValue: direction,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Hướng do bạn xác nhận',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: AiEdgeDirection.forward,
                      child: Text('Source → Target'),
                    ),
                    DropdownMenuItem(
                      value: AiEdgeDirection.reverse,
                      child: Text('Target → Source'),
                    ),
                    DropdownMenuItem(
                      value: AiEdgeDirection.both,
                      child: Text('Hai chiều (2 cạnh, cùng mét)'),
                    ),
                  ],
                  onChanged: (v) => update(() => direction = v),
                ),
                CheckboxListTile(
                  key: const Key('ai-edge-confirm'),
                  value: confirmed,
                  onChanged: (v) => update(() => confirmed = v!),
                  title: const Text(
                    'Tôi xác nhận kết nối, hướng và số mét; chưa xác nhận an toàn xe lăn.',
                  ),
                ),
                if (error != null)
                  Text(
                    error!,
                    key: const Key('ai-edge-error'),
                    style: const TextStyle(color: Colors.red),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Hủy'),
            ),
            FilledButton(
              key: const Key('ai-edge-save'),
              onPressed: () {
                try {
                  review.editEdge(edge.id, from: from, to: to, type: type);
                  review.acceptEdge(
                    edge.id,
                    meters: double.tryParse(
                      meters.text.trim().replaceAll(',', '.'),
                    ),
                    direction: direction,
                    confirmed: confirmed,
                  );
                  Navigator.pop(dialog);
                } on FormatException catch (e) {
                  update(() => error = e.message);
                }
              },
              child: const Text('Accept cạnh'),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => meters.dispose());
    if (mounted) setState(() {});
  }

  Future<void> _apply() async {
    try {
      final batch = review.batch();
      if (batch.nodes.isEmpty && batch.edges.isEmpty) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(
            'Thêm ${batch.nodes.length} Node / ${batch.directedEdges} Edge vào Draft?',
          ),
          content: const Text(
            'Chỉ thêm mục đã duyệt. Không ghi đè graph, không Save/Publish, không thay QR. Mọi vị trí/lối đi và accessibility vẫn cần kiểm tra.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              key: const Key('ai-graph-final-confirm'),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Xác nhận thêm'),
            ),
          ],
        ),
      );
      if (yes == true && mounted && widget.enabled) widget.onApply(batch);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  String _status(AiReviewStatus status) => switch (status) {
    AiReviewStatus.pending => 'Chờ duyệt',
    AiReviewStatus.accepted => 'Đã chọn • chưa thêm vào bản nháp',
    AiReviewStatus.rejected => 'Đã loại',
  };
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Xám: điểm hiện có • cam/tím: AI đề xuất • xanh: đã chọn để thêm. Chạm trên ảnh để xem bằng chứng. Chưa thay đổi bản nháp.',
      ),
      SizedBox(
        height: 340,
        child: FloorPlanCanvas(
          image: review.input.image.imageProvider,
          onViewMetrics: (scene, scale) {
            _scene = scene;
            _scale = scale;
          },
          onPoint: widget.enabled ? _pick : null,
          painterBuilder: (scale) => AiProposalPainter(
            review,
            viewScale: scale,
            selection: _selection,
          ),
        ),
      ),
      if (_error != null)
        Text(
          _error!,
          key: const Key('ai-graph-error'),
          style: const TextStyle(color: Colors.red),
        ),
      if (review.nodes.isNotEmpty)
        Wrap(
          children: [
            TextButton(
              key: const Key('ai-accept-all-nodes'),
              onPressed: widget.enabled
                  ? () => _act(() {
                      for (final n in review.nodes) {
                        review.acceptNode(n.node.id);
                      }
                    })
                  : null,
              child: const Text('Chọn tất cả Node để duyệt'),
            ),
            TextButton(
              onPressed: widget.enabled
                  ? () => _act(() {
                      for (final n in review.nodes) {
                        review.rejectNode(n.node.id);
                      }
                      for (final e in review.edges) {
                        review.rejectEdge(e.id);
                      }
                    })
                  : null,
              child: const Text('Reject tất cả'),
            ),
          ],
        ),
      for (final (i, n) in review.nodes.indexed)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('P${i + 1}. ${n.node.name} • ${n.node.type}'),
                Text(
                  'AI ước lượng ${(n.node.confidence * 100).round()}% • ${_status(review.nodeStatus(n.node.id))}',
                ),
                Text('Cần kiểm tra: ${n.node.uncertainty}'),
                ExpansionTile(
                  title: const Text('Bằng chứng và tọa độ'),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'X ${n.node.x.toStringAsFixed(3)} • Y ${n.node.y.toStringAsFixed(3)}\n${n.evidence}',
                      ),
                    ),
                  ],
                ),
                if (n.node.landmarkNote != null)
                  Text('Landmark: ${n.node.landmarkNote}'),
                Wrap(
                  children: [
                    OutlinedButton(
                      key: Key('graph-accept-node-${n.node.id}'),
                      onPressed: widget.enabled
                          ? () => _act(() => review.acceptNode(n.node.id))
                          : null,
                      child: const Text('Accept'),
                    ),
                    TextButton(
                      key: Key('graph-edit-node-${n.node.id}'),
                      onPressed: widget.enabled
                          ? () => widget.onEditNode(i)
                          : null,
                      child: const Text('Edit'),
                    ),
                    TextButton(
                      key: Key('graph-reject-node-${n.node.id}'),
                      onPressed: widget.enabled
                          ? () => _act(() => review.rejectNode(n.node.id))
                          : null,
                      child: const Text('Reject'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      for (final e in review.edges)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${e.id}: ${_label(e.from)} → ${_label(e.to)} • ${e.type}',
                ),
                Text(
                  '${_status(review.edgeStatus(e.id))} • ${review.reviewedEdges[e.id]?.meters.toString() ?? 'Chưa có mét'} • hint AI ${e.directionHint} (chưa xác minh)',
                ),
                Text(
                  'Confidence: ${e.confidence == null ? 'không cung cấp' : '${(e.confidence! * 100).round()}%'} (do AI tự ước lượng)',
                ),
                Text('Bằng chứng: ${e.evidence}\nChưa chắc: ${e.uncertainty}'),
                Wrap(
                  children: [
                    OutlinedButton(
                      key: Key('graph-accept-edge-${e.id}'),
                      onPressed: widget.enabled ? () => _edge(e) : null,
                      child: const Text('Accept / Edit cạnh'),
                    ),
                    TextButton(
                      key: Key('graph-reject-edge-${e.id}'),
                      onPressed: widget.enabled
                          ? () => _act(() => review.rejectEdge(e.id))
                          : null,
                      child: const Text('Reject'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      for (final a in review.proposal.areas)
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: Text(a.name),
          subtitle: Text('Chưa chắc: ${a.reason}'),
        ),
      FilledButton(
        key: const Key('ai-graph-apply'),
        onPressed:
            widget.enabled &&
                (review.nodeStatuses.values.contains(AiReviewStatus.accepted) ||
                    review.reviewedEdges.isNotEmpty)
            ? _apply
            : null,
        child: Text(
          'Áp dụng ${review.nodeStatuses.values.where((s) => s == AiReviewStatus.accepted).length} Node / ${review.reviewedEdges.length} đề xuất Edge đã duyệt',
        ),
      ),
    ],
  );
}

/// One image-space geometry, screen-sized annotations. Never handles Draft dragging.
class AiProposalPainter extends CustomPainter {
  AiProposalPainter(this.review, {this.viewScale = 1, this.selection});
  final AiGraphReview review;
  final double viewScale;
  final String? selection;
  @override
  void paint(Canvas canvas, Size size) {
    final scene = beginScreenSizedMapPaint(canvas, size, viewScale);
    Offset point(double x, double y) =>
        Offset(x * scene.width, y * scene.height);
    final points = {
      for (final n in review.input.existing) n.ref: point(n.x, n.y),
      for (final n in review.nodes) n.node.id: point(n.node.x, n.node.y),
    };
    final codes = {for (final n in review.input.existing) n.code: n.ref};
    for (final pair in review.input.existingPairs) {
      final ends = pair.split('\u0000');
      final a = points[codes[ends[0]]], b = points[codes[ends[1]]];
      if (a != null && b != null) {
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = Colors.blueGrey.withValues(alpha: .5)
            ..strokeWidth = 2,
        );
      }
    }
    for (final e in review.edges) {
      if (review.edgeStatus(e.id) == AiReviewStatus.rejected ||
          review.nodeStatus(e.from) == AiReviewStatus.rejected ||
          review.nodeStatus(e.to) == AiReviewStatus.rejected) {
        continue;
      }
      final a = points[e.from], b = points[e.to];
      if (a == null || b == null) continue;
      final delta = b - a, length = delta.distance;
      if (length == 0) continue;
      final color = review.edgeStatus(e.id) == AiReviewStatus.accepted
          ? Colors.green.shade800
          : Colors.deepPurple;
      final paint = Paint()
        ..color = color
        ..strokeWidth = selection == 'edge:${e.id}' ? 5 : 3;
      for (double at = 0; at < length; at += 13) {
        canvas.drawLine(
          a + delta * (at / length),
          a + delta * (math.min(at + 7, length) / length),
          paint,
        );
      }
      final approved = review.reviewedEdges[e.id];
      void arrow(Offset from, Offset to) {
        final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
        final mid = from + (to - from) * .65;
        canvas.drawLine(
          mid,
          mid - Offset(math.cos(angle - .5), math.sin(angle - .5)) * 10,
          paint,
        );
        canvas.drawLine(
          mid,
          mid - Offset(math.cos(angle + .5), math.sin(angle + .5)) * 10,
          paint,
        );
      }

      if (approved != null) {
        if (approved.direction != AiEdgeDirection.reverse) arrow(a, b);
        if (approved.direction != AiEdgeDirection.forward) arrow(b, a);
      }
    }
    void label(Offset p, String text, Color color, double radius) {
      canvas.drawCircle(p, radius, Paint()..color = color);
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }

    for (final (i, n) in review.input.existing.indexed) {
      label(points[n.ref]!, 'N${i + 1}', Colors.blueGrey, 11);
    }
    for (final (i, n) in review.nodes.indexed) {
      if (review.nodeStatus(n.node.id) == AiReviewStatus.rejected) continue;
      final p = points[n.node.id]!;
      if (selection == 'node:${n.node.id}') {
        canvas.drawCircle(p, 17, Paint()..color = Colors.amber);
      }
      label(
        p,
        'P${i + 1}',
        review.nodeStatus(n.node.id) == AiReviewStatus.accepted
            ? Colors.green.shade800
            : Colors.deepOrange.shade800,
        13,
      );
    }
    for (final a in review.proposal.areas) {
      label(point(a.x, a.y), '?', Colors.black54, 11);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AiProposalPainter oldDelegate) => true;
}
