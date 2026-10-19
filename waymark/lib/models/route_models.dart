// Contracts from WayMark.Api/Contracts/MapDtos.cs and RouteDtos.cs.
// Distances come from the server; normalized map coordinates are not meters.
class RoutingOptions {
  const RoutingOptions({
    this.avoidStairs = false,
    this.wheelchair = false,
    this.preference = 'ShortestDistance',
  });
  final bool avoidStairs, wheelchair;
  final String preference;
  bool get isDefault =>
      !avoidStairs && !wheelchair && preference == 'ShortestDistance';
  Map<String, dynamic> toJson() => {
    'avoidStairs': avoidStairs,
    'wheelchair': wheelchair,
    'preference': preference,
  };
  factory RoutingOptions.fromJson(Map<String, dynamic> j) {
    final result = RoutingOptions(
      avoidStairs: j['avoidStairs'] as bool,
      wheelchair: j['wheelchair'] as bool,
      preference: j['preference'] as String,
    );
    if (![
      'ShortestDistance',
      'PreferElevators',
      'LessWalking',
    ].contains(result.preference)) {
      throw const FormatException('Unknown route preference.');
    }
    return result;
  }
  bool matches(RoutingOptions other) =>
      avoidStairs == other.avoidStairs &&
      wheelchair == other.wheelchair &&
      preference == other.preference;
}

class RouteRequest {
  const RouteRequest({
    required this.startWayMarkCode,
    required this.destinationWayMarkCode,
    this.options = const RoutingOptions(),
  });
  final String startWayMarkCode;
  final String destinationWayMarkCode;
  final RoutingOptions options;
  Map<String, dynamic> toJson() => {
    'startWayMarkCode': startWayMarkCode.trim(),
    'destinationWayMarkCode': destinationWayMarkCode.trim(),
    if (!options.isDefault) 'options': options.toJson(),
  };
}

class RoutePoint {
  const RoutePoint({
    required this.id,
    required this.name,
    required this.location,
    required this.wayMarkCode,
  });
  final int id;
  final String name, location, wayMarkCode;
  factory RoutePoint.fromJson(Map<String, dynamic> j) => RoutePoint(
    id: j['id'] as int,
    name: j['name'] as String,
    location: j['location'] as String,
    wayMarkCode: j['wayMarkCode'] as String,
  );
}

class MapNode {
  const MapNode({
    required this.id,
    required this.floorId,
    required this.nodeCode,
    required this.name,
    required this.x,
    required this.y,
    required this.nodeType,
  });
  final int id, floorId;
  final String nodeCode, name, nodeType;
  final double x, y;
  factory MapNode.fromJson(Map<String, dynamic> j) => MapNode(
    id: j['id'] as int,
    floorId: j['floorId'] as int,
    nodeCode: j['nodeCode'] as String,
    name: j['name'] as String,
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    nodeType: j['nodeType'] as String,
  );
}

class WayMarkMapLocation extends RoutePoint {
  const WayMarkMapLocation({
    required super.id,
    required super.name,
    required super.location,
    required super.wayMarkCode,
    required this.node,
  });
  final MapNode? node;
  factory WayMarkMapLocation.fromJson(Map<String, dynamic> j) =>
      WayMarkMapLocation(
        id: j['id'] as int,
        name: j['name'] as String,
        location: j['location'] as String,
        wayMarkCode: j['wayMarkCode'] as String,
        node: j['node'] == null
            ? null
            : MapNode.fromJson(j['node'] as Map<String, dynamic>),
      );
}

class RouteFloor {
  const RouteFloor({
    required this.id,
    required this.buildingId,
    required this.name,
    required this.floorCode,
    required this.sortOrder,
    this.floorPlanImageUrl,
  });
  final int id, buildingId, sortOrder;
  final String name, floorCode;
  final String? floorPlanImageUrl;
  factory RouteFloor.fromJson(Map<String, dynamic> j) => RouteFloor(
    id: j['id'] as int,
    buildingId: j['buildingId'] as int,
    name: j['name'] as String,
    floorCode: j['floorCode'] as String,
    sortOrder: j['sortOrder'] as int,
    floorPlanImageUrl: j['floorPlanImageUrl'] as String?,
  );
}

class RouteNode {
  const RouteNode({
    required this.id,
    required this.nodeCode,
    required this.name,
    required this.nodeType,
    required this.floor,
  });
  final int id;
  final String nodeCode, name, nodeType;
  final RouteFloor floor;
  factory RouteNode.fromJson(Map<String, dynamic> j) => RouteNode(
    id: j['id'] as int,
    nodeCode: j['nodeCode'] as String,
    name: j['name'] as String,
    nodeType: j['nodeType'] as String,
    floor: RouteFloor.fromJson(j['floor'] as Map<String, dynamic>),
  );
}

class RouteEdge {
  const RouteEdge({
    required this.sequence,
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.fromFloorId,
    required this.toFloorId,
    required this.edgeType,
    required this.distanceMeters,
    required this.isAccessible,
    required this.movement,
  });
  final int sequence, id, fromNodeId, toNodeId, fromFloorId, toFloorId;
  final String edgeType, movement;
  final double distanceMeters;
  final bool isAccessible;
  factory RouteEdge.fromJson(Map<String, dynamic> j) => RouteEdge(
    sequence: j['sequence'] as int,
    id: j['id'] as int,
    fromNodeId: j['fromNodeId'] as int,
    toNodeId: j['toNodeId'] as int,
    fromFloorId: j['fromFloorId'] as int,
    toFloorId: j['toFloorId'] as int,
    edgeType: j['edgeType'] as String,
    distanceMeters: (j['distanceMeters'] as num).toDouble(),
    isAccessible: j['isAccessible'] as bool,
    movement: j['movement'] as String,
  );
}

class WayMarkRoute {
  const WayMarkRoute({
    required this.start,
    required this.destination,
    required this.totalDistanceMeters,
    required this.accessibleOnly,
    required this.nodes,
    required this.edges,
    this.options = const RoutingOptions(),
  });
  final RoutePoint start, destination;
  final double totalDistanceMeters;
  final bool accessibleOnly;
  final RoutingOptions options;
  final List<RouteNode> nodes;
  final List<RouteEdge> edges;

  factory WayMarkRoute.fromJson(Map<String, dynamic> j) {
    final route = WayMarkRoute(
      start: RoutePoint.fromJson(j['start'] as Map<String, dynamic>),
      destination: RoutePoint.fromJson(
        j['destination'] as Map<String, dynamic>,
      ),
      totalDistanceMeters: (j['totalDistanceMeters'] as num).toDouble(),
      accessibleOnly: j['accessibleOnly'] as bool,
      options: j['options'] == null
          ? const RoutingOptions()
          : RoutingOptions.fromJson(j['options'] as Map<String, dynamic>),
      nodes: List.unmodifiable(
        (j['nodes'] as List).map(
          (n) => RouteNode.fromJson(n as Map<String, dynamic>),
        ),
      ),
      edges: List.unmodifiable(
        (j['edges'] as List).map(
          (e) => RouteEdge.fromJson(e as Map<String, dynamic>),
        ),
      ),
    );
    if (!route.totalDistanceMeters.isFinite ||
        route.totalDistanceMeters < 0 ||
        route.nodes.isEmpty ||
        route.edges.length != route.nodes.length - 1) {
      throw const FormatException('Invalid route shape.');
    }
    for (var i = 0; i < route.edges.length; i++) {
      final e = route.edges[i];
      if (e.sequence != i + 1 ||
          e.fromNodeId != route.nodes[i].id ||
          e.toNodeId != route.nodes[i + 1].id ||
          e.fromFloorId != route.nodes[i].floor.id ||
          e.toFloorId != route.nodes[i + 1].floor.id ||
          !e.distanceMeters.isFinite ||
          e.distanceMeters <= 0 ||
          (route.accessibleOnly && !e.isAccessible)) {
        throw const FormatException('Invalid ordered route edge.');
      }
    }
    if (route.options.wheelchair ||
        (route.options.avoidStairs &&
            route.edges.any((edge) => edge.edgeType == 'Stairs'))) {
      throw const FormatException(
        'Route violates restrictions or lacks wheelchair verification.',
      );
    }
    return route;
  }
}

/// Coordinates are obtained from the existing floor graph endpoint, not /routes.
/// Patient route maps ignore graph edges; draft editing may copy them separately.
class FloorMapData {
  const FloorMapData({
    required this.floor,
    required this.nodes,
    this.edges = const [],
  });
  final RouteFloor floor;
  final List<MapNode> nodes;
  final List<MapGraphEdge> edges;

  factory FloorMapData.fromJson(Map<String, dynamic> json) => FloorMapData(
    floor: RouteFloor.fromJson(json['floor'] as Map<String, dynamic>),
    nodes: List.unmodifiable(
      (json['nodes'] as List).map(
        (node) => MapNode.fromJson(node as Map<String, dynamic>),
      ),
    ),
    edges: List.unmodifiable(
      ((json['edges'] as List?) ?? []).map(
        (edge) => MapGraphEdge.fromJson(edge as Map<String, dynamic>),
      ),
    ),
  );
}

class MapGraphEdge {
  const MapGraphEdge(
    this.fromNodeId,
    this.toNodeId,
    this.distanceMeters,
    this.edgeType,
    this.isActive,
  );
  final int fromNodeId, toNodeId;
  final double distanceMeters;
  final String edgeType;
  final bool isActive;
  factory MapGraphEdge.fromJson(Map<String, dynamic> json) => MapGraphEdge(
    json['fromNodeId'] as int,
    json['toNodeId'] as int,
    (json['distanceMeters'] as num).toDouble(),
    json['edgeType'] as String,
    json['isActive'] as bool,
  );
}

String formatMeters(double meters) =>
    '${meters.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')} m';
