import 'package:flutter/material.dart';

/// Both image and graph occupy this rectangle, without stretching either axis.
Size containedFloorSize(Size image, Size viewport) {
  if (image.isEmpty || viewport.isEmpty) return Size.zero;
  return applyBoxFit(BoxFit.contain, image, viewport).destination;
}

class FloorPlanCanvas extends StatefulWidget {
  const FloorPlanCanvas({
    super.key,
    required this.painter,
    this.image,
    this.onPoint,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
    this.canvasKey = const Key('floor-route-canvas'),
  });
  final CustomPainter painter;
  final ImageProvider? image;
  final ValueChanged<Offset>? onPoint;
  final bool Function(Offset)? onDragStart;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDragEnd, onDragCancel;
  final Key canvasKey;
  @override
  State<FloorPlanCanvas> createState() => _FloorPlanCanvasState();
}

class _FloorPlanCanvasState extends State<FloorPlanCanvas> {
  final _transform = TransformationController();
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _frame;
  bool _imageFailed = false;
  bool _showImage = true;
  int _generation = 0;
  Size? _viewport;
  int? _dragPointer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant FloorPlanCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _transform.value = Matrix4.identity();
      _showImage = true;
      _resolve();
    }
  }

  void _resolve() {
    final generation = ++_generation;
    if (_listener != null) _stream?.removeListener(_listener!);
    _releaseFrame();
    _imageFailed = false;
    if (widget.image == null) return;
    _stream = widget.image!.resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener(
      (info, synchronous) {
        if (!mounted || generation != _generation) {
          info.dispose();
          return;
        }
        void update() {
          _releaseFrame();
          // Keep the exact decoded frame that will be painted. A second Image
          // widget/stream must not silently fail independently of this state.
          _frame = info;
          _imageFailed = false;
          _transform.value = Matrix4.identity();
        }

        if (synchronous) {
          update();
        } else if (mounted) {
          setState(update);
        }
      },
      onError: (Object error, StackTrace? stack) {
        if (mounted && generation == _generation) {
          setState(() => _imageFailed = true);
        }
      },
    );
    _stream!.addListener(_listener!);
  }

  void _releaseFrame() {
    final previous = _frame;
    _frame = null;
    // The previous painter can still be in the current frame's display list.
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _generation++;
    _releaseFrame();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: LayoutBuilder(
          builder: (context, bounds) {
            final viewport = Size(bounds.maxWidth, bounds.maxHeight);
            if (_viewport != null && _viewport != viewport) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _transform.value = Matrix4.identity();
              });
            }
            _viewport = viewport;
            final frame = _frame;
            final loading =
                widget.image != null && frame == null && !_imageFailed;
            final size = containedFloorSize(
              frame == null
                  ? viewport
                  : Size(
                      frame.image.width.toDouble(),
                      frame.image.height.toDouble(),
                    ),
              viewport,
            );
            return Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    transformationController: _transform,
                    panEnabled: _dragPointer == null,
                    scaleEnabled: _dragPointer == null,
                    minScale: 1,
                    maxScale: 5,
                    child: Center(
                      child: SizedBox(
                        width: size.width,
                        height: size.height,
                        child: loading
                            ? const Center(child: CircularProgressIndicator())
                            : Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: widget.onDragStart == null
                                    ? null
                                    : (event) {
                                        final point = Offset(
                                          event.localPosition.dx / size.width,
                                          event.localPosition.dy / size.height,
                                        );
                                        if (_dragPointer == null &&
                                            widget.onDragStart!(point)) {
                                          setState(
                                            () => _dragPointer = event.pointer,
                                          );
                                        }
                                      },
                                onPointerMove: (event) {
                                  if (_dragPointer == event.pointer) {
                                    widget.onDragUpdate?.call(
                                      Offset(
                                        (event.localPosition.dx / size.width)
                                            .clamp(0, 1),
                                        (event.localPosition.dy / size.height)
                                            .clamp(0, 1),
                                      ),
                                    );
                                  }
                                },
                                onPointerUp: (event) {
                                  if (_dragPointer != event.pointer) return;
                                  widget.onDragEnd?.call();
                                  setState(() => _dragPointer = null);
                                },
                                onPointerCancel: (event) {
                                  if (_dragPointer != event.pointer) return;
                                  widget.onDragCancel?.call();
                                  setState(() => _dragPointer = null);
                                },
                                child: GestureDetector(
                                  onTapUp: widget.onPoint == null
                                      ? null
                                      : (details) => widget.onPoint!(
                                          Offset(
                                            (details.localPosition.dx /
                                                    size.width)
                                                .clamp(0, 1),
                                            (details.localPosition.dy /
                                                    size.height)
                                                .clamp(0, 1),
                                          ),
                                        ),
                                  child: RepaintBoundary(
                                    key: const Key('floor-plan-surface'),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (frame == null || !_showImage)
                                          CustomPaint(
                                            painter: _FloorGridPainter(),
                                          ),
                                        if (frame != null && _showImage)
                                          CustomPaint(
                                            key: const Key(
                                              'floor-plan-image-layer',
                                            ),
                                            painter: FloorPlanImagePainter(
                                              frame,
                                            ),
                                          ),
                                        if (frame == null || !_showImage)
                                          Align(
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              !_showImage
                                                  ? 'Đã ẩn ảnh mặt bằng — tọa độ graph được giữ nguyên'
                                                  : _imageFailed
                                                  ? 'Không render được ảnh mặt bằng. Hãy thử chọn lại ảnh.'
                                                  : 'Sơ đồ node — chưa có ảnh tầng',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.blueGrey,
                                              ),
                                            ),
                                          ),
                                        CustomPaint(
                                          key: widget.canvasKey,
                                          painter: widget.painter,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      // Outside the viewport: controls never obscure the image's four corners.
      Wrap(
        spacing: 8,
        alignment: WrapAlignment.center,
        children: [
          Tooltip(
            message: 'Đặt lại thu phóng',
            child: TextButton.icon(
              key: const Key('fit-floor-image'),
              icon: const Icon(Icons.center_focus_strong),
              label: const Text('Fit Image'),
              onPressed: () => _transform.value = Matrix4.identity(),
            ),
          ),
          TextButton.icon(
            key: const Key('toggle-floor-image'),
            onPressed: _frame == null
                ? null
                : () => setState(() => _showImage = !_showImage),
            icon: Icon(_showImage ? Icons.visibility : Icons.visibility_off),
            label: Text(_showImage ? 'Ẩn mặt bằng' : 'Hiện mặt bằng'),
          ),
        ],
      ),
    ],
  );
}

/// Paint pixels from the same retained frame used to size the graph surface.
/// Containment guarantees valid source/destination rects without stretching.
class FloorPlanImagePainter extends CustomPainter {
  FloorPlanImagePainter(this.frame);
  final ImageInfo frame;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    paintImage(
      canvas: canvas,
      rect: Offset.zero & size,
      image: frame.image,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant FloorPlanImagePainter oldDelegate) =>
      oldDelegate.frame != frame;
}

class _FloorGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFCBD5E1);
    // A visual grid only, not a physical distance scale or a floor geometry.
    for (double x = 4; x < size.width; x += 20) {
      for (double y = 4; y < size.height; y += 20) {
        canvas.drawCircle(Offset(x, y), .65, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
