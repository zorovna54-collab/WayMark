import '../../models/route_models.dart';

enum QrRouteMatchKind {
  current,
  next,
  later,
  past,
  ambiguous,
  offRoute,
  unmapped,
  invalidRoute,
}

enum NavigationConfirmation { manual, qr }

class QrRouteMatch {
  const QrRouteMatch._(
    this.kind,
    this.location,
    this.indices,
    this.revision,
    this._owner,
  );
  final QrRouteMatchKind kind;
  final WayMarkMapLocation location;
  final List<int> indices;
  final int revision;
  final ManualNavigation _owner;
}

/// A local checklist, not a position estimate or a backend navigation session.
class ManualNavigation {
  ManualNavigation(this.route) : issue = validate(route);
  final WayMarkRoute route;
  final String? issue;
  int _nodeIndex = 0;
  bool _completed = false;
  int _revision = 0;
  final _confirmations = <int, NavigationConfirmation>{};
  final _qrIndices = <int>{};
  int? get lastVerifiedNodeIndex =>
      _qrIndices.isEmpty ? null : _qrIndices.reduce((a, b) => a > b ? a : b);
  NavigationConfirmation? _currentConfirmation;
  WayMarkMapLocation? _currentQr;

  NavigationConfirmation? get currentConfirmation => _currentConfirmation;
  WayMarkMapLocation? get currentQr => _currentQr;
  bool get hasQrConfirmations =>
      _confirmations.containsValue(NavigationConfirmation.qr);
  int get skippedUnconfirmedSteps => Iterable<int>.generate(
    _nodeIndex,
    (i) => i + 1,
  ).where((i) => !_confirmations.containsKey(i)).length;

  /// Compare database node IDs and floor IDs, never WayMarkCode with NodeCode.
  /// Classification alone cannot change navigation progress.
  QrRouteMatch inspectQr(WayMarkMapLocation location) {
    final node = location.node;
    final indices = <int>[];
    QrRouteMatchKind kind;
    if (!isValid) {
      kind = QrRouteMatchKind.invalidRoute;
    } else if (node == null || node.id <= 0 || node.floorId <= 0) {
      kind = QrRouteMatchKind.unmapped;
    } else {
      for (var i = 0; i < route.nodes.length; i++) {
        if (route.nodes[i].id == node.id &&
            route.nodes[i].floor.id == node.floorId) {
          indices.add(i);
        }
      }
      kind = indices.isEmpty
          ? QrRouteMatchKind.offRoute
          : indices.length > 1
          ? QrRouteMatchKind.ambiguous
          : indices.single == _nodeIndex
          ? QrRouteMatchKind.current
          : indices.single == _nodeIndex + 1
          ? QrRouteMatchKind.next
          : indices.single > _nodeIndex
          ? QrRouteMatchKind.later
          : QrRouteMatchKind.past;
    }
    return QrRouteMatch._(
      kind,
      location,
      List.unmodifiable(indices),
      _revision,
      this,
    );
  }

  bool acceptQr(
    QrRouteMatch match, {
    int? selectedIndex,
    bool confirmedSelection = false,
  }) {
    if (!identical(match._owner, this) || match.revision != _revision) {
      return false;
    }
    final checked = inspectQr(match.location);
    if ({
      QrRouteMatchKind.offRoute,
      QrRouteMatchKind.unmapped,
      QrRouteMatchKind.invalidRoute,
      QrRouteMatchKind.past,
    }.contains(checked.kind)) {
      return false;
    }
    if ((checked.kind == QrRouteMatchKind.later ||
            checked.kind == QrRouteMatchKind.ambiguous) &&
        !confirmedSelection) {
      return false;
    }
    final target =
        selectedIndex ??
        (checked.indices.length == 1 ? checked.indices.single : null);
    if (target == null ||
        target < _nodeIndex ||
        !checked.indices.contains(target)) {
      return false;
    }
    if (target > _nodeIndex) {
      _nodeIndex = target;
      _completed = _nodeIndex == route.nodes.length - 1;
    }
    _confirmations[target] = NavigationConfirmation.qr;
    _qrIndices.add(target);
    _currentConfirmation = NavigationConfirmation.qr;
    _currentQr = match.location;
    _revision++;
    return true;
  }

  bool get isValid => issue == null;
  int get nodeIndex => _nodeIndex;
  bool get completed => _completed;
  bool get canGoBack => isValid && (_nodeIndex > 0 || _completed);
  RouteNode? get currentNode => isValid ? route.nodes[_nodeIndex] : null;
  RouteEdge? get currentEdge =>
      isValid && !_completed && _nodeIndex < route.edges.length
      ? route.edges[_nodeIndex]
      : null;
  RouteEdge? get followingEdge =>
      currentEdge != null && _nodeIndex + 1 < route.edges.length
      ? route.edges[_nodeIndex + 1]
      : null;
  double get progress => !isValid
      ? 0
      : _completed
      ? 1
      : route.edges.isEmpty
      ? 0
      : _nodeIndex / route.edges.length;

  bool confirmNext() {
    if (!isValid || _completed) return false;
    if (_nodeIndex < route.nodes.length - 1) _nodeIndex++;
    _confirmations[_nodeIndex] = NavigationConfirmation.manual;
    _currentConfirmation = NavigationConfirmation.manual;
    _currentQr = null;
    _revision++;
    _completed = _nodeIndex == route.nodes.length - 1;
    return true;
  }

  bool previous() {
    if (!canGoBack) return false;
    if (_nodeIndex > 0) _nodeIndex--;
    _confirmations.removeWhere((index, source) => index > _nodeIndex);
    _qrIndices.removeWhere((index) => index > _nodeIndex);
    _currentConfirmation = null;
    _currentQr = null;
    _revision++;
    _completed = false;
    return true;
  }

  static String? validate(WayMarkRoute route) {
    if (route.options.wheelchair ||
        (route.options.avoidStairs &&
            route.edges.any((e) => e.edgeType == 'Stairs')) ||
        (route.accessibleOnly && route.edges.any((e) => !e.isAccessible))) {
      return 'Tuyến không đáp ứng hạn chế hoặc thiếu xác minh cho xe lăn.';
    }
    if (route.nodes.isEmpty) return 'Tuyến rỗng: không có node để dẫn đường.';
    if (route.edges.length != route.nodes.length - 1 ||
        !route.totalDistanceMeters.isFinite ||
        route.totalDistanceMeters < 0) {
      return 'Tuyến thiếu dữ liệu node, cạnh hoặc khoảng cách hợp lệ.';
    }
    if ([
          route.start,
          route.destination,
        ].any((p) => p.name.trim().isEmpty || p.wayMarkCode.trim().isEmpty) ||
        route.nodes.any(
          (n) =>
              n.id <= 0 ||
              n.name.trim().isEmpty ||
              n.nodeCode.trim().isEmpty ||
              n.floor.id <= 0 ||
              n.floor.name.trim().isEmpty ||
              n.floor.floorCode.trim().isEmpty,
        )) {
      return 'Tuyến thiếu thông tin điểm hoặc tầng hợp lệ.';
    }
    for (var i = 0; i < route.edges.length; i++) {
      final edge = route.edges[i];
      if (edge.sequence != i + 1 ||
          edge.fromNodeId != route.nodes[i].id ||
          edge.toNodeId != route.nodes[i + 1].id ||
          edge.fromFloorId != route.nodes[i].floor.id ||
          edge.toFloorId != route.nodes[i + 1].floor.id ||
          !edge.distanceMeters.isFinite ||
          edge.distanceMeters <= 0 ||
          edge.edgeType.trim().isEmpty ||
          edge.movement !=
              (edge.fromFloorId == edge.toFloorId
                  ? 'SameFloor'
                  : 'ChangeFloor')) {
        return 'Cạnh tuyến không khớp thứ tự node hoặc thiếu dữ liệu hợp lệ.';
      }
    }
    return null;
  }
}

String navigationEdgeLabel(String type) => switch (type) {
  'Corridor' => 'Hành lang',
  'Elevator' => 'Thang máy',
  'Stairs' => 'Cầu thang',
  'Ramp' => 'Đường dốc',
  _ => type,
};
