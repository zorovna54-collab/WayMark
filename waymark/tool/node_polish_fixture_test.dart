// Explicit test-only input; not bundled or automatically opened by the app.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/admin/draft_map.dart';

import '../test/fixtures/multifloor_fixture.dart';
import '../test/multifloor_navigation_test.dart' show attachFloorImages;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Generate node-first multi-floor rehearsal', () async {
    final p = threeFloorProject();
    await attachFloorImages(p);
    for (final f in p.floors) {
      f.places.clear();
      for (final n in f.nodes) {
        f.putNode(
          DraftNode(
            n.code,
            n.name,
            n.x,
            n.y,
            n.type,
            displayName: n.code == 'DOOR'
                ? 'Quầy tiếp nhận ${f.floor.floorCode}'
                : null,
            searchableAsDestination: n.code == 'DOOR',
            landmarkNote: n.code == 'STAIR'
                ? 'Biển tầng ${f.floor.floorCode} tại chiếu nghỉ (TEST)'
                : n.code == 'DOOR'
                ? 'Quầy màu xanh — dữ liệu TEST'
                : null,
          ),
          replace: true,
        );
      }
    }
    Directory('build/node-polish-evidence').createSync(recursive: true);
    File('build/node-polish-evidence/project.json')
        .writeAsBytesSync(p.encode());
  });
}
