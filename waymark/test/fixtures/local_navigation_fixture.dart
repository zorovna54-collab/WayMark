import 'package:waymark/features/admin/draft_map.dart';

// Custom graph, unrelated to SQL/demo G/L1. Label is deliberately not a door.
DraftMap customNavigationDraft() {
  final d = DraftMap.local(
    'Custom site',
    'Clinic test',
    'Custom floor',
    'CUSTOM',
  );
  for (final n in [
    const DraftNode('S', 'Start', .1, .5, 'Entrance'),
    const DraftNode('J', 'Junction', .4, .5, 'Junction'),
    const DraftNode('DOOR', 'Door 101', .7, .5, 'Entrance'),
    const DraftNode('FAR', 'Other door', .8, .2, 'Entrance'),
    const DraftNode('ISO', 'Isolated door', .9, .9, 'Entrance'),
  ]) {
    d.putNode(n);
  }
  for (final e in [
    const DraftEdge('S', 'J', 4, 'Corridor'),
    const DraftEdge('J', 'DOOR', 6, 'Door'),
    const DraftEdge('S', 'DOOR', 20, 'Corridor'),
    const DraftEdge('S', 'FAR', 15, 'Corridor'),
  ]) {
    d.addEdge(e);
  }
  for (final (code, name, doors) in [
    ('101', 'Room 101', ['DOOR', 'FAR', 'ISO']),
    ('102', 'Start room', ['S']),
    ('103', 'Isolated room', ['ISO']),
  ]) {
    d.places.add({
      'id': newDraftGuid(),
      'placeCode': code,
      'name': name,
      'label': {'x': .85, 'y': .65},
      'polygon': [],
      'entranceNodeIds': doors.map(d.nodeId).toList(),
      'accessibility': 'Unknown',
    });
  }
  return d;
}
