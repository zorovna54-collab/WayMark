import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/route_models.dart';
import '../../services/waymark_api_service.dart';
import 'floor_route_geometry.dart';
import 'floor_plan_canvas.dart';

class FloorRouteMap extends StatefulWidget {
  const FloorRouteMap({
    super.key,
    required this.route,
    required this.api,
    this.activeNodeIndex,
    this.activeNodeStatus,
    this.verifiedNodeIndex,
    this.activeIsManual = false,
  });
  final WayMarkRoute route;
  final WayMarkApiService api;

  /// Manual selection in the route order; never a measured physical position.
  final int? activeNodeIndex;
  final String? activeNodeStatus;
  final int? verifiedNodeIndex;
  final bool activeIsManual;

  @override
  State<FloorRouteMap> createState() => _FloorRouteMapState();
}

class _FloorRouteMapState extends State<FloorRouteMap>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _graphs = <int, Future<FloorMapData>>{};
  int? _selectedFloorId;
  int? get _activeFloorId {
    final index = widget.activeNodeIndex;
    return index != null && index >= 0 && index < widget.route.nodes.length
        ? widget.route.nodes[index].floor.id
        : null;
  }

  @override
  void didUpdateWidget(covariant FloorRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route != widget.route || oldWidget.api != widget.api) {
      _graphs.clear();
      _selectedFloorId = null;
    } else if (oldWidget.activeNodeIndex != widget.activeNodeIndex) {
      _selectedFloorId = _activeFloorId;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final route = widget.route;
    if (route.nodes.isEmpty) {
      return const Text('Tuyến rỗng: không có node để hiển thị bản đồ.');
    }
    final visits = floorVisits(route);
    final floors = <int, RouteFloor>{
      for (final node in route.nodes) node.floor.id: node.floor,
    };
    final selected = _selectedFloorId ?? _activeFloorId ?? floors.keys.first;
    final floor = floors[selected]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Bản đồ tuyến theo tầng',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tòa (ID ${floor.buildingId}) / ${floor.name}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Thứ tự qua tầng: ${visits.map((visit) => visit.floor.name).join(' → ')}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        if (_activeFloorId != null) ...[
          Text(
            widget.activeNodeStatus ??
                'Ô vàng: node đang chọn theo xác nhận thủ công.',
            style: const TextStyle(fontSize: 12, color: AppColors.primary),
          ),
          if (selected != _activeFloorId)
            TextButton(
              onPressed: () =>
                  setState(() => _selectedFloorId = _activeFloorId),
              child: const Text('Về tầng của bước hiện tại'),
            ),
        ],
        const SizedBox(height: 8),
        if (floor.id <= 0 || floor.name.trim().isEmpty)
          const Text('Thiếu thông tin tầng hợp lệ để tải bản đồ.')
        else
          FutureBuilder<FloorMapData>(
            future: _graphs.putIfAbsent(
              selected,
              () => widget.api.getFloorGraph(selected),
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 180,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 8),
                        Text('Đang tải tọa độ tầng...'),
                      ],
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final available in floors.values)
                            _floorChoice(available, selected),
                        ],
                      ),
                      Text(
                        'Không thể hiển thị bản đồ tầng.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _graphs.remove(selected);
                        }),
                        child: const Text('Tải lại bản đồ'),
                      ),
                    ],
                  ),
                );
              }
              final graph = snapshot.requireData;
              final geometry = FloorRouteGeometry.build(route, graph);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _canvas(route, graph, geometry),
                  const SizedBox(height: 8),
                  const Text(
                    'S: xuất phát • Đ: điểm đến • E: thang máy • T: cầu thang\nSố trên node là thứ tự bước; mũi tên là chiều đi.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  for (final transition in geometry.transitions)
                    Text(
                      'Bước ${transition.at.routeIndex + 1}: ${_transitionType(transition.edge.edgeType)} '
                      '${transition.departing ? '→' : '←'} ${transition.otherFloor.name}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                      ),
                    ),
                  for (final issue in geometry.issues)
                    Text(
                      issue,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.redAccent,
                      ),
                    ),
                  if (geometry.stops.isEmpty)
                    const Text('Không có tọa độ tuyến hợp lệ trên tầng này.'),
                  if (widget.verifiedNodeIndex != null)
                    const Text(
                      'Vòng nét đứt: QR gần nhất, chỉ tại thời điểm quét. Ô vàng: bước thủ công.',
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _canvas(
    WayMarkRoute route,
    FloorMapData graph,
    FloorRouteGeometry geometry,
  ) {
    final imageUri = Uri.tryParse(graph.floor.floorPlanImageUrl ?? '');
    final hasImage =
        imageUri != null &&
        imageUri.host.isNotEmpty &&
        imageUri.userInfo.isEmpty &&
        (imageUri.scheme == 'http' || imageUri.scheme == 'https');
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: (constraints.maxWidth * 0.9).clamp(260.0, 440.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Semantics(
                    label:
                        'Tuyến trên ${graph.floor.name}, ${geometry.stops.length} node, ${geometry.segments.length} cạnh cùng tầng',
                    child: FloorPlanCanvas(
                      key: ValueKey('floor-plan-${graph.floor.id}'),
                      image: hasImage
                          ? NetworkImage(imageUri.toString())
                          : null,
                      painter: FloorRoutePainter(
                        geometry: geometry,
                        lastRouteIndex: route.nodes.length - 1,
                        activeNodeIndex: widget.activeNodeIndex,
                        verifiedNodeIndex: widget.verifiedNodeIndex,
                        activeIsManual: widget.activeIsManual,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  constraints: const BoxConstraints(
                    maxHeight: 210,
                    maxWidth: 80,
                  ),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.layers_outlined,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                        for (final floor in {
                          for (final node in route.nodes)
                            node.floor.id: node.floor,
                        }.values)
                          _floorChoice(floor, graph.floor.id),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _floorChoice(RouteFloor floor, int selectedFloorId) => Tooltip(
    message: floor.name,
    child: ChoiceChip(
      key: ValueKey('floor-${floor.id}'),
      showCheckmark: false,
      label: Text(floor.floorCode, overflow: TextOverflow.ellipsis),
      selected: floor.id == selectedFloorId,
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        color: floor.id == selectedFloorId ? Colors.white : AppColors.primary,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (_) => setState(() => _selectedFloorId = floor.id),
    ),
  );

  String _transitionType(String type) => switch (type) {
    'Elevator' => 'Chuyển tầng bằng thang máy',
    'Stairs' => 'Chuyển tầng bằng cầu thang',
    _ => 'Chuyển tầng ($type)',
  };
}

class FloorRoutePainter extends CustomPainter {
  const FloorRoutePainter({
    required this.geometry,
    required this.lastRouteIndex,
    this.activeNodeIndex,
    this.verifiedNodeIndex,
    this.activeIsManual = false,
  });
  final FloorRouteGeometry geometry;
  final int lastRouteIndex;
  final int? activeNodeIndex;
  final int? verifiedNodeIndex;
  final bool activeIsManual;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;
    Offset point(MapRouteStop stop) =>
        normalizedMapPoint(stop.coordinate.x, stop.coordinate.y, size)!;
    final linePaint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (final segment in geometry.segments) {
      final from = point(segment.from);
      final to = point(segment.to);
      // Separate subpaths prevent accidental links across missing nodes or visits.
      path.moveTo(from.dx, from.dy);
      path.lineTo(to.dx, to.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(path, linePaint);
    for (final segment in geometry.segments) {
      if (segment.from.routeIndex == activeNodeIndex) {
        canvas.drawLine(
          point(segment.from),
          point(segment.to),
          Paint()
            ..color = AppColors.accent
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    final arrowPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    for (final segment in geometry.segments) {
      final from = point(segment.from);
      final to = point(segment.to);
      final delta = to - from;
      if (delta.distance < 1) continue;
      final middle = Offset.lerp(from, to, 0.55)!;
      final angle = math.atan2(delta.dy, delta.dx);
      canvas.drawLine(
        middle,
        middle - Offset(math.cos(angle - 0.5), math.sin(angle - 0.5)) * 8,
        arrowPaint,
      );
      canvas.drawLine(
        middle,
        middle - Offset(math.cos(angle + 0.5), math.sin(angle + 0.5)) * 8,
        arrowPaint,
      );
    }
    for (final stop in geometry.stops) {
      final at = point(stop);
      if (stop.routeIndex == activeNodeIndex &&
          (activeIsManual || stop.routeIndex != verifiedNodeIndex)) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: at, width: 38, height: 38),
            const Radius.circular(6),
          ),
          Paint()
            ..color = activeIsManual ? Colors.amber : AppColors.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4,
        );
      }
      if (stop.routeIndex == verifiedNodeIndex) {
        final ring = Paint()
          ..color = AppColors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        for (var dash = 0; dash < 24; dash++) {
          canvas.drawArc(
            Rect.fromCircle(center: at, radius: 22),
            dash * math.pi / 12,
            math.pi / 20,
            false,
            ring,
          );
        }
        final qrLabel = TextPainter(
          text: const TextSpan(
            text: 'QR gần nhất',
            style: TextStyle(
              fontSize: 9,
              color: AppColors.primary,
              fontFamily: 'Inter',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        qrLabel.paint(canvas, at + const Offset(12, -36));
      }
      final start = stop.routeIndex == 0;
      final end = stop.routeIndex == lastRouteIndex;
      final transition = geometry.transitions.any(
        (t) => t.at.routeIndex == stop.routeIndex,
      );
      final elevator = stop.node.nodeType == 'Elevator';
      final stairs = stop.node.nodeType == 'Stairs';
      final marker =
          '${start ? 'S' : ''}${end ? 'Đ' : ''}${elevator
              ? 'E'
              : stairs
              ? 'T'
              : ''}';
      if (transition) {
        canvas.drawCircle(
          at,
          14,
          Paint()
            ..color = Colors.orange
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
      canvas.drawCircle(
        at,
        10,
        Paint()
          ..color = start
              ? AppColors.primary
              : end
              ? AppColors.accent
              : Colors.white,
      );
      canvas.drawCircle(
        at,
        10,
        Paint()
          ..color = AppColors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      final text = TextPainter(
        text: TextSpan(
          text: '${stop.routeIndex + 1}',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: start || end ? Colors.white : AppColors.primary,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, at - Offset(text.width / 2, text.height / 2));
      if (marker.isNotEmpty) {
        final label = TextPainter(
          text: TextSpan(
            text: marker,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, at + const Offset(11, -23));
      }
    }
  }

  @override
  bool shouldRepaint(covariant FloorRoutePainter oldDelegate) =>
      oldDelegate.geometry != geometry ||
      oldDelegate.lastRouteIndex != lastRouteIndex ||
      oldDelegate.activeNodeIndex != activeNodeIndex ||
      oldDelegate.verifiedNodeIndex != verifiedNodeIndex ||
      oldDelegate.activeIsManual != activeIsManual;
}
