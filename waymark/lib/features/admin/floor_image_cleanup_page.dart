import 'package:flutter/material.dart';

import 'floor_image_cleanup.dart';
import 'floor_plan_asset.dart';
import 'draft_file_gateway.dart';

class CleanupPoint {
  const CleanupPoint(this.label, this.source);
  final String label;
  final Offset source;
}

class FloorImageCleanupPage extends StatefulWidget {
  const FloorImageCleanupPage({
    super.key,
    required this.original,
    required this.floorName,
    required this.files,
    this.initial,
    this.points = const [],
  });
  final FloorPlanAsset original;
  final String floorName;
  final DraftFileGateway files;
  final ImageCleanupSettings? initial;
  final List<CleanupPoint> points;
  @override
  State<FloorImageCleanupPage> createState() => _FloorImageCleanupPageState();
}

class _FloorImageCleanupPageState extends State<FloorImageCleanupPage> {
  late ImageCleanupSettings _settings =
      widget.initial ?? ImageCleanupSettings();
  final _undo = <ImageCleanupSettings>[];
  final _previewAnchor = GlobalKey();
  CleanedFloorImage? _result;
  bool _busy = false, _after = false, _perspective = false;
  String? _error;
  void _change(ImageCleanupSettings next) {
    setState(() {
      _undo.add(_settings);
      if (_undo.length > 40) _undo.removeAt(0);
      _settings = next;
      _result = null;
      _after = false;
      _error = null;
    });
  }

  List<String> _excluded() {
    final crop = ImageTransform.fromQuad(_settings.corners);
    return widget.points
        .where((p) => !ImageTransform.inside(crop.map(p.source)))
        .map((p) => p.label)
        .toList();
  }

  void _moveCorner(int i, DragUpdateDetails d, Rect rect) {
    final q = List<Offset>.of(_settings.corners), old = q[i];
    final p = Offset(
      (old.dx + d.delta.dx / rect.width).clamp(0.0, 1.0),
      (old.dy + d.delta.dy / rect.height).clamp(0.0, 1.0),
    );
    if (_perspective) {
      q[i] = p;
    } else {
      final opposite = q[(i + 2) % 4];
      final left = i == 0 || i == 3 ? p.dx : opposite.dx,
          right = i == 1 || i == 2 ? p.dx : opposite.dx,
          top = i < 2 ? p.dy : opposite.dy,
          bottom = i > 1 ? p.dy : opposite.dy;
      q.setAll(0, [
        Offset(left, top),
        Offset(right, top),
        Offset(right, bottom),
        Offset(left, bottom),
      ]);
    }
    _change(_settings.copyWith(corners: q));
  }

  Future<void> _preview() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await cleanupFloorImage(widget.original, _settings);
      if (mounted) {
        setState(() {
          _result = result;
          _after = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final target = _previewAnchor.currentContext;
          if (mounted && target != null) {
            Scrollable.ensureVisible(target, alignment: .1);
          }
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException
              ? e.message
              : 'Không xử lý được ảnh. Ảnh gốc vẫn giữ nguyên.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    if (_result == null) return;
    final excluded = _excluded();
    if (excluded.isNotEmpty) {
      setState(
        () => _error =
            'Khung loại bỏ ${excluded.length} node/nhãn/đỉnh phòng. Điều chỉnh khung hoặc hiệu chỉnh chúng thủ công trước.',
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Áp dụng ảnh và tọa độ?'),
        content: Text(
          'Cập nhật ${widget.points.length} điểm bằng cùng homography đã xem trước. Giữ nguyên GUID, Entrance và mét. Hãy đối chiếu ảnh với thực tế; không xác nhận lối đi an toàn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Xem lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Áp dụng lên tầng này'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.pop(context, _result);
  }

  Future<void> _savePng() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.files.save(
        _result!.asset.bytes,
        'floor-cleaned.png',
        'image/png',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Đã lưu PNG đã xử lý. Bản nháp chỉ thay đổi khi Apply.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Chưa lưu được PNG hoặc bạn đã hủy lưu.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final excluded = _result == null ? <String>[] : _excluded();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chỉnh ảnh sơ đồ'),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              '${widget.floorName} • chỉnh cục bộ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text(
              'Kéo 4 góc trên ảnh gốc. Crop giữ khung chữ nhật; Phối cảnh chọn bốn góc bảng theo thứ tự 1–2–3–4. Không đoán nội dung bằng AI.',
            ),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Crop'),
                  selected: !_perspective,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _perspective = false),
                ),
                ChoiceChip(
                  label: const Text('Phối cảnh 4 góc'),
                  selected: _perspective,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _perspective = true),
                ),
                TextButton(
                  onPressed: _busy || _undo.isEmpty
                      ? null
                      : () => setState(() {
                          _settings = _undo.removeLast();
                          _result = null;
                          _after = false;
                          _error = null;
                        }),
                  child: const Text('Undo'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _change(ImageCleanupSettings()),
                  child: const Text('Reset gốc'),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Before'),
                  selected: !_after,
                  onSelected: (_) => setState(() => _after = false),
                ),
                ChoiceChip(
                  label: const Text('After'),
                  selected: _after,
                  onSelected: _result == null
                      ? null
                      : (_) => setState(() => _after = true),
                ),
                Text(
                  '${widget.original.width} × ${widget.original.height} → ${_result == null ? 'chưa xử lý' : '${_result!.asset.width} × ${_result!.asset.height} PNG'}',
                ),
              ],
            ),
            SizedBox(
              key: _previewAnchor,
              height: MediaQuery.sizeOf(context).height * .45,
              child: LayoutBuilder(
                builder: (context, box) {
                  final asset = _after ? _result!.asset : widget.original;
                  final size = applyBoxFit(
                    BoxFit.contain,
                    Size(asset.width.toDouble(), asset.height.toDouble()),
                    Size(
                      (box.maxWidth - 48).clamp(1.0, double.infinity),
                      (box.maxHeight - 48).clamp(1.0, double.infinity),
                    ),
                  ).destination;
                  final rect = Alignment.center.inscribe(
                    size,
                    Offset.zero & box.biggest,
                  );
                  return Container(
                    color: Colors.blueGrey.shade50,
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned.fromRect(
                          rect: rect,
                          child: Image(
                            image: asset.imageProvider,
                            fit: BoxFit.fill,
                            key: const Key('cleanup-image'),
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _CleanupOverlay(
                                rect,
                                _after ? null : _settings.corners,
                                _after ? _result!.edit.transform : null,
                                widget.points,
                              ),
                            ),
                          ),
                        ),
                        if (!_after)
                          for (var i = 0; i < 4; i++)
                            Positioned(
                              left:
                                  rect.left +
                                  _settings.corners[i].dx * rect.width -
                                  22,
                              top:
                                  rect.top +
                                  _settings.corners[i].dy * rect.height -
                                  22,
                              child: GestureDetector(
                                key: Key('cleanup-corner-$i'),
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragUpdate: _busy
                                    ? null
                                    : (d) => _moveCorner(i, d, rect),
                                onVerticalDragUpdate: _busy
                                    ? null
                                    : (d) => _moveCorner(i, d, rect),
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .9),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.deepOrange,
                                      width: 3,
                                    ),
                                  ),
                                  child: Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _change(
                          _settings.copyWith(
                            quarterTurns: (_settings.quarterTurns + 1) % 4,
                          ),
                        ),
                  child: Text('Xoay 90° (${_settings.quarterTurns * 90}°)'),
                ),
                FilterChip(
                  label: const Text('Grayscale'),
                  selected: _settings.grayscale,
                  onSelected: _busy
                      ? null
                      : (v) => _change(_settings.copyWith(grayscale: v)),
                ),
              ],
            ),
            Text('Góc tinh chỉnh: ${_settings.degrees.toStringAsFixed(1)}°'),
            Slider(
              key: const Key('cleanup-angle'),
              value: _settings.degrees,
              min: -15,
              max: 15,
              divisions: 150,
              onChanged: _busy
                  ? null
                  : (v) => _change(_settings.copyWith(degrees: v)),
            ),
            Text('Brightness: ${_settings.brightness.toStringAsFixed(2)}'),
            Slider(
              key: const Key('cleanup-brightness'),
              value: _settings.brightness,
              min: -.5,
              max: .5,
              onChanged: _busy
                  ? null
                  : (v) => _change(_settings.copyWith(brightness: v)),
            ),
            Text('Contrast: ${_settings.contrast.toStringAsFixed(2)}'),
            Slider(
              key: const Key('cleanup-contrast'),
              value: _settings.contrast,
              min: .5,
              max: 2,
              onChanged: _busy
                  ? null
                  : (v) => _change(_settings.copyWith(contrast: v)),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            if (excluded.isNotEmpty)
              Text(
                'Không thể Apply: ${excluded.take(6).join(', ')} nằm ngoài crop.',
                style: const TextStyle(color: Colors.red),
              ),
            const Text(
              'Phối cảnh chỉ dùng homography phẳng. Tỷ lệ vật lý không biết trước; không sửa được bề mặt cong, chữ mờ hoặc méo ống kính. Điểm xanh dùng cùng transform với ảnh; cần kiểm tra thủ công.',
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  key: const Key('cleanup-preview'),
                  onPressed: _busy ? null : _preview,
                  child: const Text('Xem kết quả'),
                ),
                OutlinedButton(
                  onPressed: _busy || _result == null ? null : _savePng,
                  child: const Text('Xuất PNG'),
                ),
                FilledButton(
                  key: const Key('cleanup-apply'),
                  onPressed: _busy || _result == null || excluded.isNotEmpty
                      ? null
                      : _apply,
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CleanupOverlay extends CustomPainter {
  _CleanupOverlay(this.rect, this.corners, this.transform, this.points);
  final Rect rect;
  final List<Offset>? corners;
  final ImageTransform? transform;
  final List<CleanupPoint> points;
  Offset pixel(Offset p) =>
      rect.topLeft + Offset(p.dx * rect.width, p.dy * rect.height);
  @override
  void paint(Canvas canvas, Size size) {
    if (corners != null) {
      final path = Path()..moveTo(pixel(corners![0]).dx, pixel(corners![0]).dy);
      for (final p in corners!.skip(1)) {
        path.lineTo(pixel(p).dx, pixel(p).dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.deepOrange
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    for (final p in points) {
      final mapped = transform?.map(p.source) ?? p.source;
      if (ImageTransform.inside(mapped)) {
        canvas.drawCircle(pixel(mapped), 5, Paint()..color = Colors.green);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CleanupOverlay old) => true;
}
