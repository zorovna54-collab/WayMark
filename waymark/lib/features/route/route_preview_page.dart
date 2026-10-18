import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/route_models.dart';
import '../../services/waymark_api_service.dart';
import '../auth/login/login_page.dart';

class RoutePreviewPage extends StatefulWidget {
  const RoutePreviewPage({
    super.key,
    required this.startWayMarkCode,
    required this.destinationWayMarkCode,
    this.accessibleOnly = false,
    this.api,
  });
  final String startWayMarkCode, destinationWayMarkCode;
  final bool accessibleOnly;
  final WayMarkApiService? api;

  @override
  State<RoutePreviewPage> createState() => _RoutePreviewPageState();
}

class _RoutePreviewPageState extends State<RoutePreviewPage> {
  late final WayMarkApiService _api = widget.api ?? WayMarkApiService();
  late Future<WayMarkRoute> _route = _loadRoute();

  Future<WayMarkRoute> _loadRoute() => _api.findRoute(
    RouteRequest(
      startWayMarkCode: widget.startWayMarkCode,
      destinationWayMarkCode: widget.destinationWayMarkCode,
    ),
    accessibleOnly: widget.accessibleOnly,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFE2E8F0),
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Material(
                  color: AppColors.card,
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const Flexible(
                  child: Text(
                    'Xem trước tuyến đường',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<WayMarkRoute>(
              future: _route,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Đang tìm tuyến đường...'),
                      ],
                    ),
                  );
                }
                if (snapshot.hasError) return _error(snapshot.error!);
                return _routeSheet(snapshot.requireData);
              },
            ),
          ),
        ],
      ),
    ),
  );

  Widget _error(Object error) {
    final needsLogin = error is WayMarkApiException && error.statusCode == 401;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.route_outlined,
              size: 56,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 16),
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (needsLogin)
              ElevatedButton(
                onPressed: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const LoginPage()),
                  (_) => false,
                ),
                child: const Text('Đăng nhập lại'),
              )
            else
              ElevatedButton(
                onPressed: () => setState(() {
                  _route = _loadRoute();
                }),
                child: const Text('Thử lại'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Chọn lại điểm đến'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _routeSheet(WayMarkRoute route) => Container(
    padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
    decoration: const BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      boxShadow: [
        BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -6)),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 48,
            height: 6,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    route.destination.name,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    route.destination.location,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  Text('WayMark: ${route.destination.wayMarkCode}'),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              formatMeters(route.totalDistanceMeters),
              key: const Key('route-distance'),
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Xuất phát: ${route.start.name} • ${route.start.wayMarkCode}'),
        if (route.accessibleOnly)
          const Text('Chỉ các cạnh được đánh dấu accessible.'),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Các chặng theo bản đồ đã thiết lập. Chưa có định vị trực tiếp hoặc hướng rẽ trái/phải.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
        if (route.edges.isEmpty)
          const Text('Điểm xuất phát và điểm đến cùng một node.'),
        Expanded(
          child: ListView.builder(
            itemCount: route.nodes.length,
            itemBuilder: (context, index) {
              final node = route.nodes[index];
              final edge = index < route.edges.length
                  ? route.edges[index]
                  : null;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: AppColors.secondary,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(color: AppColors.primary),
                      ),
                    ),
                    title: Text(
                      node.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('${node.floor.name} • ${node.nodeCode}'),
                  ),
                  if (edge != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 20, bottom: 12),
                      child: Row(
                        children: [
                          Icon(
                            edge.movement == 'ChangeFloor'
                                ? Icons.elevator_outlined
                                : Icons.south,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${_edgeLabel(edge.edgeType)} • ${formatMeters(edge.distanceMeters)}'
                              '${edge.movement == 'ChangeFloor' ? ' → ${route.nodes[index + 1].floor.name}' : ''}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          child: const Text('Dẫn đường trực tiếp chưa khả dụng'),
        ),
      ],
    ),
  );

  String _edgeLabel(String type) => switch (type) {
    'Corridor' => 'Hành lang',
    'Elevator' => 'Thang máy',
    'Stairs' => 'Cầu thang',
    _ => type,
  };
}
