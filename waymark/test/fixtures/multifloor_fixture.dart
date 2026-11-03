import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/admin/local_map_project.dart';

LocalMapProject threeFloorProject() {
  final floors = <DraftMap>[];
  for (final (i, code) in ['G', 'I', 'II'].indexed) {
    final d = DraftMap.local(
      'Local clinic',
      'Local building',
      'Tầng $code',
      code,
    );
    d.putNode(const DraftNode('START', 'Bắt đầu', .1, .5, 'Entrance'));
    d.putNode(const DraftNode('STAIR', 'Cầu thang', .5, .5, 'Stairs'));
    d.putNode(const DraftNode('DOOR', 'Cửa phòng', .8, .5, 'Entrance'));
    d.addEdge(const DraftEdge('START', 'STAIR', 4, 'Corridor'));
    d.addEdge(const DraftEdge('STAIR', 'DOOR', 6, 'Door'));
    d.addEdge(const DraftEdge('DOOR', 'STAIR', 6, 'Door'));
    d.places.add({
      'id': newDraftGuid(),
      'placeCode': '${i + 1}01',
      'name': 'Phòng ${i + 1}01',
      'label': {'x': .8, 'y': .25},
      'polygon': [],
      'entranceNodeIds': [d.nodeId('DOOR')],
      'accessibility': 'Unknown',
    });
    floors.add(d);
  }
  final p = LocalMapProject(floors.first)..floors.addAll(floors.skip(1));
  for (var i = 0; i < 2; i++) {
    p.links.add(
      LocalFloorLink(
        fromFloor: floors[i].localWorkspaceId!,
        fromNode: floors[i].nodeId('STAIR'),
        toFloor: floors[i + 1].localWorkspaceId!,
        toNode: floors[i + 1].nodeId('STAIR'),
        meters: 10,
        type: 'Stairs',
      ),
    );
  }
  return p;
}
