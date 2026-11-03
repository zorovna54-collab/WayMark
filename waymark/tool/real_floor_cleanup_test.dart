// Opt-in local-only real-image test. Never bundled assets and never uploaded.
import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/admin/floor_plan_asset.dart';
import 'package:waymark/features/admin/floor_image_cleanup.dart';
import 'package:waymark/features/admin/local_map_project.dart';

import '../test/fixtures/multifloor_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const input = String.fromEnvironment('WAYMARK_TEST_IMAGE_DIR');
  test(
    'Real hospital images: crop/perspective/rotate/tone -> actual PNG, no network',
    () async {
      final root = Directory('build/image-cleanup-evidence')
        ..createSync(recursive: true);
      final report = <String, dynamic>{};
      final project = threeFloorProject();
      for (final (i, name) in [
        'floor_1_layout.png',
        'floor_2_layout.png',
        'ground_campus.png',
        'floor_1_directory.png',
        'floor_2_directory.png',
      ].indexed) {
        final original = await FloorPlanAsset.validate(
          await File('$input/$name').readAsBytes(),
          name,
          'image/png',
        );
        final settings = ImageCleanupSettings(
          corners: i == 2
              ? const [
                  Offset(.012, .008),
                  Offset(.99, .035),
                  Offset(.99, .99),
                  Offset(.012, .99),
                ]
              : const [
                  Offset(.012, .012),
                  Offset(.99, .008),
                  Offset(.99, .99),
                  Offset(.008, .99),
                ],
          degrees: i == 1 ? -.4 : 0,
          contrast: i == 2 ? 1.12 : 1.15,
          brightness: .01,
        );
        final result = await cleanupFloorImage(original, settings);
        File('${root.path}/${name.replaceAll('.png', '')}-after.png')
            .writeAsBytesSync(result.asset.bytes);
        if (i < 3) {
          final f = project.floors[i];
          f.image = original;
          f.applyImageCleanup(result);
        }
        if (i == 0) {
          final rotated = await cleanupFloorImage(
            original,
            ImageCleanupSettings(quarterTurns: 1),
          );
          File('${root.path}/floor-1-rotate90.png')
              .writeAsBytesSync(rotated.asset.bytes);
          expect(rotated.asset.width, original.height);
        }
        report[name] = {
          'before': [original.width, original.height],
          'after': [result.asset.width, result.asset.height],
          'bytes': result.asset.bytes.length,
          'settings': settings.toJson(),
          'sourceToProcessed': result.edit.transform.m,
        };
      }
      File(
        '${root.path}/processing.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
      File('${root.path}/coordinate-test-project-v3.json')
          .writeAsBytesSync(project.encode());
      final restored = await LocalMapProject.decode(project.encode());
      for (var i = 0; i < 3; i++) {
        expect(
          restored.floors[i].imageEdit!.original.bytes,
          project.floors[i].imageEdit!.original.bytes,
        );
        expect(restored.floors[i].image!.bytes, project.floors[i].image!.bytes);
      }
    },
    skip: input.isEmpty
        ? 'Supply WAYMARK_TEST_IMAGE_DIR; never bundle hospital photos.'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
