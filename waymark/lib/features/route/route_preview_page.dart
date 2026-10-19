import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/map_ui_theme.dart';
import '../../models/route_models.dart';
import '../../services/waymark_api_service.dart';
import '../auth/login/login_page.dart';
import '../navigation/navigation_page.dart';
import '../navigation/manual_navigation.dart';
import 'floor_route_map.dart';
import 'floor_route_geometry.dart';
import 'route_preferences.dart';

class RoutePreviewPage extends StatefulWidget {
  const RoutePreviewPage({
    super.key,
    required this.startWayMarkCode,
    required this.destinationWayMarkCode,
    this.accessibleOnly = false,
    this.api,
    this.options = const RoutingOptions(),
  });
  final String startWayMarkCode, destinationWayMarkCode;
  final bool accessibleOnly;
  final WayMarkApiService? api;
  final RoutingOptions options;

  @override
  State<RoutePreviewPage> createState() => _RoutePreviewPageState();
}

class _RoutePreviewPageState extends State<RoutePreviewPage> {
  late final WayMarkApiService _api = widget.api ?? WayMarkApiService();
  late Future<WayMarkRoute> _route = _loadRoute();
  bool _openingNavigation = false;
  late RoutingOptions _options = widget.options;
  late String _startCode = widget.startWayMarkCode;
  final _sheetController = DraggableScrollableController();

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  void _toggleInstructions() {
    if (!_sheetController.isAttached) return;
    _sheetController.animateTo(
      _sheetController.size < .6 ? .8 : .36,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _startNavigation(WayMarkRoute route) async {
    if (_openingNavigation) return;
    _openingNavigation = true;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => NavigationPage(
            route: route,
            api: _api,
            onRouteChanged: (replacement) {
              if (!mounted) return;
              setState(() {
                _startCode = replacement.start.wayMarkCode;
                _route = Future.value(replacement);
              });
            },
          ),
        ),
      );
    } finally {
      _openingNavigation = false;
    }
  }

  Future<WayMarkRoute> _loadRoute() {
    final request = _api.findRoute(
      RouteRequest(
        startWayMarkCode: _startCode,
        destinationWayMarkCode: widget.destinationWayMarkCode,
        options: _options,
      ),
      accessibleOnly: widget.accessibleOnly,
    );
    // Observe immediately: a fast failure can precede the next frame after a
    // dialog closes. FutureBuilder still receives this same future and shows
    // the error; disposed/replaced requests cannot emit an unhandled error.
    request.ignore();
    return request;
  }

  @override
  Widget build(BuildContext context) => mapUiTheme(
    context,
    Scaffold(
      backgroundColor: AppColors.background,
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
                  IconButton(
                    tooltip: 'Tùy chọn tuyến',
                    icon: const Icon(Icons.tune),
                    onPressed: () async {
                      final selected = await showRoutePreferences(
                        context,
                        _options,
                      );
                      if (!mounted || selected == null) return;
                      setState(() {
                        _options = selected;
                        _route = _loadRoute();
                      });
                    },
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

  Widget _routeSheet(WayMarkRoute route) => Stack(
    children: [
      Positioned.fill(
        child: SingleChildScrollView(
          key: const Key('preview-map-scroll'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 230),
          child: FloorRouteMap(route: route, api: _api),
        ),
      ),
      DraggableScrollableSheet(
        controller: _sheetController,
        initialChildSize: .36,
        minChildSize: .22,
        maxChildSize: .88,
        builder: (context, controller) => Container(
          padding: const EdgeInsets.only(bottom: 80),
          decoration: const BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 16)],
          ),
          child: ListView(
            key: const Key('route-instructions'),
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 90),
            children: [
              Center(
                child: Tooltip(
                  message: 'Mở/thu gọn hướng dẫn',
                  child: InkWell(
                    onTap: _toggleInstructions,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 8,
                      ),
                      child: SizedBox(width: 40, child: Divider(thickness: 4)),
                    ),
                  ),
                ),
              ),
              const Text(
                'ĐIỂM ĐẾN CỦA BẠN',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: AppColors.textMuted,
                ),
              ),
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
                            fontSize: 19,
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          route.destination.location,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatMeters(route.totalDistanceMeters),
                    key: const Key('route-distance'),
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Xuất phát: ${route.start.name}'),
              if (route.accessibleOnly)
                const Text(
                  'Chỉ các cạnh được đánh dấu accessible; không phải xác nhận an toàn xe lăn.',
                ),
              if (route.options.avoidStairs)
                const Text('Hạn chế: không đi qua cầu thang.'),
              OutlinedButton.icon(
                onPressed: () async {
                  final selected = await showRoutePreferences(
                    context,
                    _options,
                  );
                  if (!mounted || selected == null) return;
                  setState(() {
                    _options = selected;
                    _route = _loadRoute();
                  });
                },
                icon: const Icon(Icons.accessibility_new),
                label: Text(routingOptionsLabel(route.options)),
              ),
              Text(
                '${route.edges.length} chặng • ${floorVisits(route).map((visit) => visit.floor.floorCode).join(' → ')}',
              ),
              const Text(
                'Kéo lên để xem các chặng. Chưa có định vị trực tiếp hoặc hướng rẽ trái/phải.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              if (route.edges.isEmpty)
                const Text('Điểm xuất phát và điểm đến cùng một node.'),
              Text(
                'QR xuất phát: ${route.start.wayMarkCode}',
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                'WayMark đích: ${route.destination.wayMarkCode}',
                style: const TextStyle(fontSize: 12),
              ),
              for (var i = 0; i < route.nodes.length; i++) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.secondary,
                    child: Text('${i + 1}'),
                  ),
                  title: Text(route.nodes[i].name),
                  subtitle: Text(
                    '${route.nodes[i].floor.name} • ${route.nodes[i].nodeCode}',
                  ),
                ),
                if (i < route.edges.length)
                  Padding(
                    padding: const EdgeInsets.only(left: 20, bottom: 12),
                    child: Text(
                      '${_edgeLabel(route.edges[i].edgeType)} • ${formatMeters(route.edges[i].distanceMeters)}'
                      '${route.edges[i].movement == 'ChangeFloor' ? ' → ${route.nodes[i + 1].floor.name}' : ''}',
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      Positioned(
        left: 16,
        right: 16,
        bottom: 12,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (ManualNavigation.validate(route) case final issue?)
              Text(issue, style: const TextStyle(color: Colors.redAccent)),
            ElevatedButton(
              onPressed: ManualNavigation.validate(route) == null
                  ? () => _startNavigation(route)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Bắt đầu dẫn đường'),
            ),
          ],
        ),
      ),
    ],
  );
  String _edgeLabel(String type) => switch (type) {
    'Corridor' => 'Hành lang',
    'Elevator' => 'Thang máy',
    'Stairs' => 'Cầu thang',
    _ => type,
  };
}
