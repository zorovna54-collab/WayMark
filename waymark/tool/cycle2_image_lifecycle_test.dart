import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/admin/floor_plan_asset.dart';
import 'package:waymark/features/indoor_tracking/indoor_tracking_controller.dart';
import 'package:waymark/features/indoor_tracking/tracking_graph.dart';
import 'package:waymark/features/indoor_tracking/sensors/sensor_provider.dart';

import '../test/fixtures/published_benchmark_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Cycle2 isolated image decode and session cleanup timings; RAM not measured', () async {
    final rows = <Map<String, Object?>>[];
    for (final width in [256, 1024, 2048]) {
      final fixture = await PublishedBenchmarkFixture.create(
        2,
        20,
        imageWidth: width,
      );
      final decode = <double>[], close = <double>[];
      final session = await fixture.api.loadQr(fixture.payload);
      final graph = await TrackingGraph.fromNavigation(session.map);
      final target = session.map.destinationNodes.last;
      final route = session.map.routeToNode(
        session.startKey,
        target.nodeId,
        target.floorId,
      );
      for (var i = 0; i < 11; i++) {
        final watch = Stopwatch()..start();
        final image = await FloorPlanAsset.validate(
          fixture.image,
          'fixture.png',
          'image/png',
        );
        watch.stop();
        if (i > 0) decode.add(watch.elapsedMicroseconds / 1000);
        expect(image.width, width);
        final controller = IndoorTrackingController(
          graph: graph,
          map: session.map,
          route: route,
          provider: UnsupportedSensorProvider(),
        );
        watch
          ..reset()
          ..start();
        await controller.close();
        controller.dispose();
        watch.stop();
        if (i > 0) close.add(watch.elapsedMicroseconds / 1000);
        expect(controller.acceptedMovements, 0);
      }
      decode.sort();
      close.sort();
      rows.add({
        'width': width,
        'height': width ~/ 2,
        'iterations': 10,
        'warmup': 1,
        'imageValidationDecodeMedianMs': decode[5],
        'controllerCloseDisposeMedianMs': close[5],
        'memory': 'MEMORY NOT MEASURED',
        'limitation': 'Desktop test engine; unsupported sensor provider; no real sensor/native disposal or GC retained heap measurement',
      });
    }
    final output = File(
      'build/full-product-cycle2-20261031/image-lifecycle-benchmark.json',
    );
    if (await output.exists()) {
      throw StateError('Preserve prior benchmark output');
    }
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(rows),
    );
    stdout.writeln(jsonEncode(rows));
  });
}
