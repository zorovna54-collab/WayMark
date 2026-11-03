import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/indoor_tracking/indoor_position.dart';
import 'package:waymark/features/indoor_tracking/indoor_tracking_controller.dart';
import 'package:waymark/features/indoor_tracking/live_tracking_panel.dart';
import 'package:waymark/features/indoor_tracking/published_live_preflight.dart';
import 'package:waymark/features/indoor_tracking/tracking_graph.dart';
import 'package:waymark/features/indoor_tracking/map_readiness.dart';
import 'package:waymark/features/navigation/navigation_page.dart';
import 'package:waymark/features/scanner/public_map_entry_page.dart';
import 'package:waymark/features/search/local_map_search_page.dart';
import 'package:waymark/services/published_map_api_service.dart';
import 'package:waymark/services/published_read_failure.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/models/route_models.dart';

import 'fixtures/published_live_fixture.dart';
import 'published_map_test.dart' show SessionApi;
import 'live_navigation_ui_test.dart'
    show liveTap, waitLive, cacheLiveMap, unmountLive;
import 'support/fake_sensor_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(AuthSession.clear);

  test('Endpoint rejects credentials/query/unsupported scheme and never follows QR host', () async {
    for (final value in [
      'not a url',
      'file:///api',
      'https://u:p@host/api',
      'https://host/api?jwt=secret',
      'https://host/api#secret',
      'https://host:70000/api',
    ]) {
      expect(publishedEndpoint(value), isNull);
    }
    expect(
      publishedEndpoint(' https://fixture.test/api/ '),
      'https://fixture.test/api',
    );
    var calls = 0;
    final api = PublishedMapApiService(
      baseUrl: 'invalid endpoint',
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      api.resolve('WMQR1:${List.filled(64, 'a').join()}'),
      throwsA(
        isA<PublishedReadException>().having(
          (e) => e.kind,
          'kind',
          PublishedReadCode.invalidEndpoint,
        ),
      ),
    );
    expect(calls, 0);
  });

  for (final mode in [
    'revoked',
    'offline',
    'timeout',
    'wrongMap',
    'wrongVersion',
    'missingNode',
    'missingFloor',
  ]) {
    test(
      'Published QR $mode has sanitized typed error and preserves anchor/snapshot',
      () async {
        final f = await PublishedLiveFixture.create();
        var changed = false;
        final api = PublishedMapApiService(
          baseUrl: 'https://fixture.test/api',
          timeout: const Duration(milliseconds: 20),
          client: MockClient((r) async {
            if (changed && r.url.path.contains('/qr/')) {
              if (mode == 'offline') {
                throw http.ClientException('SECRET URL TOKEN');
              }
              if (mode == 'timeout') return Completer<http.Response>().future;
              if (mode == 'revoked') {
                return http.Response(
                  '{"code":"qr_revoked","title":"DO-NOT-EXPORT"}',
                  410,
                );
              }
              return http.Response(
                jsonEncode({
                  'mapId': mode == 'wrongMap'
                      ? '22222222-2222-4222-8222-222222222222'
                      : f.session.mapId,
                  'version': mode == 'wrongVersion'
                      ? f.session.version + 1
                      : f.session.version,
                  'floorKey': mode == 'missingFloor'
                      ? '22222222-2222-4222-8222-222222222222'
                      : f.session.floorKey,
                  'nodeId': mode == 'missingNode'
                      ? '22222222-2222-4222-8222-222222222222'
                      : f.session.nodeId,
                }),
                200,
              );
            }
            return f.http.client.get(r.url);
          }),
        );
        final session = await api.loadQr(f.http.payload);
        final graph = await TrackingGraph.fromNavigation(session.map);
        final fake = FakeSensorProvider();
        final target = session.map.destinationNodes.first;
        final c = IndoorTrackingController(
          graph: graph,
          map: session.map,
          route: session.map.routeToNode(
            session.startKey,
            target.nodeId,
            target.floorId,
          ),
          provider: fake,
        );
        addTearDown(() async {
          await c.close();
          c.dispose();
        });
        c.manualAnchor(graph.nodes.values.first.id);
        final before = c.position.value!.point;
        changed = true;
        final ticket = await c.beginRelocalization();
        expect(await c.completeRelocalization(f.http.payload, ticket), false);
        expect(c.position.value!.point, before);
        expect(c.corrections, 0);
        final expected = switch (mode) {
          'revoked' => 'published_qrRevoked',
          'offline' => 'published_network',
          'timeout' => 'published_timeout',
          'wrongMap' => 'published_mapMismatch',
          'wrongVersion' => 'published_versionMismatch',
          _ => 'published_anchorMissing',
        };
        expect(c.lastError, expected);
        expect(c.graph.key.version, f.session.version);
        final export = c.sanitizedDiagnostics();
        for (final secret in [
          f.http.token,
          f.session.mapId,
          'SECRET',
          'DO-NOT-EXPORT',
        ]) {
          expect(export, isNot(contains(secret)));
        }
      },
    );
  }

  test('Valid correction retains QR source; late response after route replacement is rejected', () async {
    final f = await PublishedLiveFixture.create(), fake = FakeSensorProvider();
    final c = IndoorTrackingController(
      graph: f.graph,
      map: f.session.map,
      route: f.route,
      provider: fake,
    );
    addTearDown(() async {
      await c.close();
      c.dispose();
    });
    final ticket = await c.beginRelocalization();
    expect(await c.completeRelocalization(f.http.payload, ticket), true);
    expect(c.position.value!.source, PositionSource.qr);
    expect(c.position.value!.confidence, PositionConfidence.confirmedAtScan);
    final pending = Completer<WayMarkMapLocation>();
    f.session.map.resolvePublishedQr = (_) => pending.future;
    final lateTicket = await c.beginRelocalization();
    final resolving = c.completeRelocalization('NOT-LOGGED', lateTicket);
    await c.replaceRoute(f.route);
    pending.complete(
      f.session.map.stableLocation(
        f.session.floorKey,
        f.session.nodeId,
        'NOT-LOGGED',
      ),
    );
    expect(await resolving, false);
    expect(c.corrections, 1);
  });

  test(
    'Missing/corrupt Published floor image has an image-specific read error',
    () async {
      final f = await PublishedLiveFixture.create();
      final api = PublishedMapApiService(
        baseUrl: 'https://fixture.test/api',
        client: MockClient((r) async {
          if (r.url.path.contains('/images/')) {
            return http.Response(
              'not image, DO-NOT-EXPORT',
              200,
              headers: {'content-type': 'image/png'},
            );
          }
          return f.http.client.get(r.url);
        }),
      );
      await expectLater(
        api.loadQr(f.http.payload),
        throwsA(
          isA<PublishedReadException>().having(
            (e) => e.kind,
            'kind',
            PublishedReadCode.imageUnavailable,
          ),
        ),
      );
    },
  );

  test('Published loading provenance survives mutable publication assignment and blocks a mislabeled snapshot', () async {
    final f = await PublishedLiveFixture.create();
    f.session.map.publication = (
      mapId: f.session.mapId,
      version: f.session.version + 1,
    );
    final graph = await TrackingGraph.fromNavigation(f.session.map);
    final input = MapReadinessInput.fromNavigation(f.session.map, f.route);
    final report = MapReadinessValidator.evaluate(
      input,
      graph: graph,
      requireGraph: true,
    );
    expect(input.pin!.version, f.session.version);
    expect(report.canStartLive, false);
    expect(
      report.issues.any((i) => i.reasonCode == 'mapVersionMismatch'),
      true,
    );
    expect(
      () => f.session.map.bindPublishedOrigin(
        f.session.mapId,
        f.session.version + 1,
      ),
      throwsFormatException,
    );
  });

  testWidgets(
    'Published guest QR fixture -> Search -> Preview -> Navigation -> preflight and same guided setup',
    (t) async {
      final f = (await t.runAsync(PublishedLiveFixture.create))!;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await cacheLiveMap(t, f.session.map);
      await t.pumpWidget(
        MaterialApp(
          home: PublicMapEntryPage(
            api: SessionApi(f.session),
            initialPayload: f.http.payload,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Mở bản đồ từ QR'));
      await t.pumpAndSettle();
      expect(find.byType(LocalMapSearchPage), findsOneWidget);
      await t.ensureVisible(find.textContaining('Destination G').first);
      await t.tap(find.textContaining('Destination G').first);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Bắt đầu dẫn đường'));
      await t.tap(find.text('Bắt đầu dẫn đường'));
      await t.pumpAndSettle();
      expect(find.byType(NavigationPage), findsOneWidget);
      await liveTap(t, const Key('enable-live-navigation'));
      await waitLive(t);
      expect(find.byType(PublishedLivePreflight), findsOneWidget);
      expect(find.byKey(const Key('live-guided-setup')), findsOneWidget);
      expect(find.byKey(const Key('preflight-route-count')), findsOneWidget);
      expect(
        f.http.calls.every(
          (r) => r.method == 'GET' && !r.headers.containsKey('Authorization'),
        ),
        true,
      );
      final c = t
          .widget<LiveTrackingPanel>(find.byType(LiveTrackingPanel))
          .controller;
      expect(
        c.position.value,
        isNull,
      ); // Loading a map never fabricates a new verified anchor.
      await liveTap(t, const Key('preflight-manual'));
      expect(find.byType(LiveTrackingPanel), findsNothing);
      await unmountLive(t);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'Blocked data keeps manual Navigation enabled and does not instantiate sensor provider',
    (t) async {
      final f = (await t.runAsync(PublishedLiveFixture.create))!;
      final fake = FakeSensorProvider();
      f.session.map.publication = (mapId: f.session.mapId, version: 0);
      await cacheLiveMap(t, f.session.map);
      await t.pumpWidget(
        MaterialApp(
          home: NavigationPage(
            route: f.route,
            localMap: f.session.map,
            liveSensorProvider: fake,
          ),
        ),
      );
      await t.pumpAndSettle();
      await liveTap(t, const Key('enable-live-navigation'));
      for (
        var i = 0;
        i < 40 && find.byKey(const Key('preflight-blocked')).evaluate().isEmpty;
        i++
      ) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await t.pump();
      }
      expect(find.byKey(const Key('preflight-blocked')), findsOneWidget);
      expect(find.byType(LiveTrackingPanel), findsNothing);
      expect(
        t
            .widget<ElevatedButton>(find.byKey(const Key('navigation-confirm')))
            .onPressed,
        isNotNull,
      );
      expect(fake.probes, 0);
      expect(fake.starts, 0);
      await liveTap(t, const Key('preflight-manual'));
      await unmountLive(t);
      await fake.dispose();
    },
  );

  testWidgets(
    'Published preflight remains useful with unavailable sensors and keeps valid QR provenance',
    (t) async {
      final f = (await t.runAsync(PublishedLiveFixture.create))!,
          fake = FakeSensorProvider();
      fake.available.removeWhere((k) => k.name == 'stepDetector');
      await cacheLiveMap(t, f.session.map);
      await t.pumpWidget(
        MaterialApp(
          home: NavigationPage(
            route: f.route,
            localMap: f.session.map,
            liveSensorProvider: fake,
          ),
        ),
      );
      await t.pumpAndSettle();
      await liveTap(t, const Key('enable-live-navigation'));
      await waitLive(t);
      final c = t
          .widget<LiveTrackingPanel>(find.byType(LiveTrackingPanel))
          .controller;
      final ticket = c.beginRelocalization();
      await t.pump();
      final token = await ticket;
      final accepted = c.completeRelocalization(f.http.payload, token);
      await t.pump();
      expect(await accepted, true);
      expect(c.position.value!.source, PositionSource.qr);
      final starting = c.startSensors();
      await t.pump();
      await starting;
      expect(c.status, TrackingStatus.sensorUnavailable);
      await liveTap(t, const Key('live-manual'));
      expect(fake.disposed, true);
      await unmountLive(t);
    },
  );
  testWidgets(
    'Foreign route replacement disposes Live before applying a route outside the pinned snapshot',
    (t) async {
      final f = (await t.runAsync(PublishedLiveFixture.create))!;
      final other = (await t.runAsync(PublishedLiveFixture.create))!;
      final fake = FakeSensorProvider();
      var route = f.route;
      late StateSetter update;
      await cacheLiveMap(t, f.session.map);
      await t.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) {
              update = set;
              return NavigationPage(
                route: route,
                localMap: f.session.map,
                liveSensorProvider: fake,
              );
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await liveTap(t, const Key('enable-live-navigation'));
      await waitLive(t);
      update(() => route = other.route);
      await t.pumpAndSettle();
      for (var i = 0; i < 6; i++) {
        await t.runAsync(() => Future<void>.delayed(Duration.zero));
        await t.pump();
      }
      expect(find.byType(LiveTrackingPanel), findsNothing);
      expect(
        find.byKey(const Key('preflight-blocked')),
        findsOneWidget,
        reason: t
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join('\n'),
      );
      expect(fake.disposed, true);
      expect(
        t
            .widget<ElevatedButton>(find.byKey(const Key('navigation-confirm')))
            .onPressed,
        isNotNull,
      );
      expect(t.takeException(), isNull);
      await unmountLive(t);
    },
  );
}
