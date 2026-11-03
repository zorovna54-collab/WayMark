// Test fixture generator only. Never loaded automatically by the app.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../test/fixtures/multifloor_fixture.dart';
import '../test/multifloor_navigation_test.dart' show attachFloorImages;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Generate isolated three-floor project for real Android picker',
    () async {
      final p = threeFloorProject();
      await attachFloorImages(p);
      Directory('build/multifloor-evidence').createSync(recursive: true);
      File('build/multifloor-evidence/project-v3.json')
          .writeAsBytesSync(p.encode());
    },
  );
}
