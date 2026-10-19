import 'package:waymark/models/route_models.dart';

import 'routing_fixture.dart';

Map<String, dynamic> navigationQrJson(int id, int floorId, {String? code}) => {
  'id': 1000 + id,
  'name': 'QR point $id',
  'location': 'Floor $floorId',
  'wayMarkCode': code ?? 'SCAN-$id',
  'node': {
    'id': id,
    'floorId': floorId,
    'nodeCode': 'NODE-$id',
    'name': 'Node $id',
    'nodeType': 'Destination',
    'x': 0.5,
    'y': 0.5,
  },
};

WayMarkMapLocation qrLocation(int id, int floorId) =>
    WayMarkMapLocation.fromJson(navigationQrJson(id, floorId));

WayMarkRoute repeatingNodeRoute() {
  final json = routeJson();
  final original = json['nodes'] as List;
  // A (floor 1) -> B (floor 2) -> A again. Same physical node, distinct occurrences.
  json['nodes'] = [original[0], original[2], original[0]];
  json['edges'] = [
    {
      'sequence': 1,
      'id': 31,
      'fromNodeId': 11,
      'toNodeId': 13,
      'fromFloorId': 1,
      'toFloorId': 2,
      'edgeType': 'Elevator',
      'distanceMeters': 5,
      'isAccessible': true,
      'movement': 'ChangeFloor',
    },
    {
      'sequence': 2,
      'id': 32,
      'fromNodeId': 13,
      'toNodeId': 11,
      'fromFloorId': 2,
      'toFloorId': 1,
      'edgeType': 'Elevator',
      'distanceMeters': 5,
      'isAccessible': true,
      'movement': 'ChangeFloor',
    },
  ];
  json['totalDistanceMeters'] = 10;
  return WayMarkRoute.fromJson(json);
}
