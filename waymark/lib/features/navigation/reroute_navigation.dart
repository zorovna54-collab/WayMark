import '../../models/route_models.dart';
import '../../services/waymark_api_service.dart';
import 'manual_navigation.dart';

/// Produces a replacement without mutating the session the user is following.
Future<ManualNavigation> rerouteNavigation(
  ManualNavigation current,
  WayMarkMapLocation location,
  WayMarkApiService api,
) async {
  final node = location.node;
  if (!current.isValid || node == null || node.id <= 0 || node.floorId <= 0) {
    throw const WayMarkApiException('QR hoặc tuyến hiện tại không hợp lệ.');
  }
  final previous = current.route;
  final route = await api.findRoute(
    RouteRequest(
      startWayMarkCode: location.wayMarkCode,
      destinationWayMarkCode: previous.destination.wayMarkCode,
      options: previous.options,
    ),
    accessibleOnly: previous.accessibleOnly,
  );
  final issue = ManualNavigation.validate(route);
  if (issue != null ||
      route.start.wayMarkCode.toLowerCase() !=
          location.wayMarkCode.toLowerCase() ||
      route.destination.wayMarkCode.toLowerCase() !=
          previous.destination.wayMarkCode.toLowerCase() ||
      route.nodes.first.id != node.id ||
      route.nodes.first.floor.id != node.floorId ||
      route.nodes.last.id != previous.nodes.last.id ||
      route.nodes.last.floor.id != previous.nodes.last.floor.id ||
      route.accessibleOnly != previous.accessibleOnly ||
      !route.options.matches(previous.options) ||
      (previous.accessibleOnly &&
          route.edges.any((edge) => !edge.isAccessible))) {
    throw const WayMarkApiException(
      'Tuyến mới không khớp QR, điểm đến hoặc bộ lọc.',
    );
  }
  final replacement = ManualNavigation(route);
  replacement.acceptQr(
    replacement.inspectQr(location),
    selectedIndex: 0,
    confirmedSelection: true,
  );
  return replacement;
}
