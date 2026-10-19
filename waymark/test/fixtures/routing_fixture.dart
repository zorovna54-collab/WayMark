const startCode = 'WM-DEMO-2A-START';
const destinationCode = 'WM-DEMO-2A-DEST';

Map<String, dynamic> floorGraphJson(int floorId) {
  final route = routeJson();
  final nodes = (route['nodes'] as List)
      .cast<Map<String, dynamic>>()
      .where((node) => node['floor']['id'] == floorId)
      .toList();
  return {
    'floor': nodes.first['floor'],
    'nodes': [
      for (var i = 0; i < nodes.length; i++)
        {
          'id': nodes[i]['id'],
          'floorId': floorId,
          'nodeCode': nodes[i]['nodeCode'],
          'name': nodes[i]['name'],
          'nodeType': nodes[i]['nodeType'],
          'x': 0.2 + i * 0.5,
          'y': 0.3 + i * 0.4,
        },
    ],
    'edges': [], // Drawing must use route edges, not graph edges.
  };
}

Map<String, dynamic> pointJson({bool destination = false}) => {
  'id': destination ? 2 : 1,
  'name': destination ? 'Demo destination' : 'Demo entrance',
  'location': destination ? 'Floor two' : 'Floor one',
  'wayMarkCode': destination ? destinationCode : startCode,
};

Map<String, dynamic> mapLocationJson({bool mapped = true}) => {
  ...pointJson(),
  'node': mapped
      ? {
          'id': 11,
          'floorId': 1,
          'nodeCode': 'TEST-START',
          'name': 'Entrance',
          'x': 0.1,
          'y': 0.2,
          'nodeType': 'Entrance',
        }
      : null,
};

// Contract fixture only, not a claim about database IDs/topology.
Map<String, dynamic> routeJson({bool accessibleOnly = false}) => {
  'start': pointJson(),
  'destination': pointJson(destination: true),
  'totalDistanceMeters': 40,
  'accessibleOnly': accessibleOnly,
  'nodes': [
    for (var i = 0; i < 3; i++)
      {
        'id': 11 + i,
        'nodeCode': 'TEST-$i',
        'name': ['Entrance', 'Lift', 'Arrival'][i],
        'nodeType': i == 1 ? 'Elevator' : 'Destination',
        'floor': {
          'id': i == 2 ? 2 : 1,
          'buildingId': 1,
          'name': i == 2 ? 'Floor two' : 'Floor one',
          'floorCode': i == 2 ? 'F2' : 'F1',
          'sortOrder': i == 2 ? 1 : 0,
          'floorPlanImageUrl': null,
        },
      },
  ],
  'edges': [
    for (var i = 0; i < 2; i++)
      {
        'sequence': i + 1,
        'id': i + 21,
        'fromNodeId': 11 + i,
        'toNodeId': 12 + i,
        'fromFloorId': 1,
        'toFloorId': i == 1 ? 2 : 1,
        'edgeType': i == 1 ? 'Elevator' : 'Corridor',
        'distanceMeters': i == 1 ? 15.25 : 24.75,
        'isAccessible': true,
        'movement': i == 1 ? 'ChangeFloor' : 'SameFloor',
      },
  ],
};
