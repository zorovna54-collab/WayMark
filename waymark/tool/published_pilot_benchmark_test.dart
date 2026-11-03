import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/navigation/local_map_navigation.dart';
import 'package:waymark/features/indoor_tracking/tracking_graph.dart';
import 'package:waymark/features/indoor_tracking/map_readiness.dart';

import '../test/fixtures/published_benchmark_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Deterministic Published load benchmark, desktop-only; no real HTTP or SQL',
    () async {
      final rows = <Map<String, Object?>>[];
      for (final spec in [
        ('small', 1, 20, 256),
        ('medium', 4, 100, 1024),
        ('large', 8, 200, 2048),
      ]) {
        final fixture = await PublishedBenchmarkFixture.create(
          spec.$2,
          spec.$3,
          imageWidth: spec.$4,
        );
        final times = <String, List<double>>{
          for (final phase in [
            'jsonDecode',
            'projectWithImageValidation',
            'navigationClone',
            'trackingGraphClone',
            'readinessInput',
            'validator',
          ])
            phase: [],
        };
        for (var iteration = 0; iteration < 4; iteration++) {
          final watch = Stopwatch();
          void begin() {
            watch.reset();
            watch.start();
          }

          void end(String key) {
            watch.stop();
            if (iteration > 0) {
              times[key]!.add(watch.elapsedMicroseconds / 1000);
            }
          }

          begin();
          final doc = jsonDecode(
            utf8.decode(fixture.snapshotBytes),
          ) as Map<String, dynamic>;
          end('jsonDecode');
          begin();
          final project = await fixture.api.project(doc, public: true);
          end('projectWithImageValidation');
          begin();
          final map = await LocalMapNavigation.fromProject(project);
          map.bindPublishedOrigin(doc['mapId'] as String, 1);
          end('navigationClone');
          begin();
          final graph = await TrackingGraph.fromNavigation(map);
          end('trackingGraphClone');
          final target = map.destinationNodes.last;
          final route = map.routeToNode(
            map.startChoices.first.key,
            target.nodeId,
            target.floorId,
          );
          begin();
          final input = MapReadinessInput.fromNavigation(map, route);
          end('readinessInput');
          begin();
          final report = MapReadinessValidator.evaluate(
            input,
            graph: graph,
            requireGraph: true,
          );
          end('validator');
          expect(graph.nodes.length, fixture.expectedNodes);
          expect(graph.edges.length, fixture.expectedEdges);
          expect(report.canStartLive, true);
          expect(graph.key.mapId, benchmarkGuid(1));
          // No persistent loader cache: each new project requests every floor image.
          expect(fixture.imageRequests, (iteration + 1) * spec.$2);
        }
        final medians = <String, double>{};
        times.forEach((key, values) {
          values.sort();
          medians[key] = values[values.length ~/ 2];
        });
        rows.add({
          'fixture': spec.$1,
          'floors': spec.$2,
          'nodes': fixture.expectedNodes,
          'edges': fixture.expectedEdges,
          'imageWidth': spec.$4,
          'imageHeight': spec.$4 ~/ 2,
          'imageCount': spec.$2,
          'imageBytesTotal': fixture.image.length * spec.$2,
          'snapshotBytes': fixture.snapshotBytes.length,
          'timingsMsMedianOf3After1Warmup': medians,
          'imageRequestsAcross4Loads': fixture.imageRequests,
          'memory': 'NOT_MEASURED: process RSS/GC/native pixels cannot isolate per-map allocations reliably here',
        });
      }
      final output = File(
        const String.fromEnvironment(
          'PUBLISHED_BENCHMARK_OUTPUT',
          defaultValue: 'build/sprint7-evidence-20261028-v2/published-loading-benchmark.json',
        ),
      );
      if (await output.exists()) {
        throw StateError(
          'Benchmark artifact exists; preserve it and choose a new output path',
        );
      }
      await output.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'environment': 'Windows Flutter test desktop, not Android phone',
          'method': 'fixed fixture order; 1 warmup + 3 measured loads; medians; MockClient images, no real network',
          'imageCodecNote': 'Source paths validate images twice in project(), then navigation clone and tracking graph clone; timing groups are inclusive, not summed with a separate total.',
          'cases': rows,
        }),
      );
      for (final r in rows) {
        stdout.writeln(jsonEncode(r));
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
