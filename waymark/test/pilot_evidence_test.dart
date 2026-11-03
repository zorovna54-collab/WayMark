import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/indoor_tracking/debug/pilot_evidence.dart';
import 'package:waymark/features/indoor_tracking/debug/field_trial_measurement.dart';
import 'package:waymark/features/indoor_tracking/indoor_tracking_controller.dart';
import 'package:waymark/features/indoor_tracking/sensors/sensor_models.dart';
import 'package:waymark/features/indoor_tracking/map_readiness.dart';

import 'support/live_tracking_replay.dart';
import 'support/fake_sensor_provider.dart';
import 'fixtures/published_live_fixture.dart';

class MaliciousDeviceProvider extends FakeSensorProvider {
  @override
  Future<SensorCapabilities> probe() async {
    final c = await super.probe();
    return SensorCapabilities(
      permission: c.permission,
      sensors: c.sensors,
      device: 'https://private.example/api?jwt=SECRET',
      androidApi: c.androidApi,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Checklist starts NOT TESTED; explicit PASS/FAIL never becomes accuracy or automatic E2E evidence', () {
    final s = PilotEvidenceSession(mode: PilotMode.published);
    addTearDown(s.dispose);
    expect(s.checks.values.every((x) => x == PilotCheckStatus.notTested), true);
    s.mark(PilotCheck.apkInstalled, PilotCheckStatus.pass);
    s.mark(PilotCheck.apiReachable, PilotCheckStatus.fail);
    var report = jsonDecode(s.export()) as Map;
    expect(report['checklist']['apkInstalled'], 'PASS');
    expect(report['checklist']['apiReachable'], 'FAIL');
    expect(report['checklist']['realDetector'], 'NOT TESTED');
    for (final c in PilotCheck.values) {
      s.mark(c, PilotCheckStatus.pass);
    }
    report = jsonDecode(s.export()) as Map;
    expect(report['physicalAccuracy'], 'NOT_VERIFIED');
    expect(report['publishedServerCameraE2e'], 'NOT_INDEPENDENTLY_VERIFIED');
    expect(report['tracking'], isNull);
    expect(report['startedAtUtc'], isNull);
  });
  test('Observation window separates detector events from accepted displacement and freezes at end', () async {
    final r = await LiveTrackingReplay.create();
    addTearDown(r.close);
    await r.begin(stride: .5);
    final s = PilotEvidenceSession(mode: PilotMode.local, now: () => r.now);
    addTearDown(s.dispose);
    s.begin(controller: r.controller);
    r.walk(3);
    r.elapse(const Duration(seconds: 2));
    r.step(withOrientation: false);
    s.end(controller: r.controller);
    final frozen = s.export(controller: r.controller);
    final report = jsonDecode(frozen) as Map,
        window = report['observationWindow'];
    expect(window['detectorAcceptedEvents'], 4);
    expect(window['acceptedDisplacementObservations'], 3);
    expect(window['rejectedMovementObservations'], 1);
    expect(window['estimatedIntegratedMeters'], 1.5);
    expect(report['tracking']['recoveryAction'], 'direction');
    expect(report['tracking']['transitionsFromExistingTimeline'], isNotEmpty);
    r.step();
    expect(s.export(controller: r.controller), frozen);
    expect(
      r.fake.running,
      true,
    ); // Closing report does not secretly pause sensors.
  });
  test('Sanitized export allowlists timeline/codes and never serializes QR/JWT/endpoint or GUIDs', () async {
    final fake = MaliciousDeviceProvider(),
        r = await LiveTrackingReplay.create(fake: fake);
    addTearDown(r.close);
    await r.begin();
    r.map.publicationQrPayload = 'WMQR1:${List.filled(64, 'a').join()}';
    r.controller.lastError = 'Bearer SECRET.JWT.TOKEN';
    r.controller.reason = 'https://private.example/api';
    r.controller.pauseReason = 'password=DO_NOT_EXPORT';
    r.controller.lastTransition = 'tracking->https://private.example/api';
    for (var i = 0; i < 150; i++) {
      r.controller.timeline.add(
        r.now,
        1,
        'WMQR1:SECRET',
        'https://private.example/api',
      );
    }
    final s = PilotEvidenceSession(mode: PilotMode.local);
    addTearDown(s.dispose);
    final text = s.export(controller: r.controller),
        data = jsonDecode(text) as Map;
    for (final value in [
      r.map.publicationQrPayload!,
      r.graph.key.mapId,
      ...r.graph.nodes.keys,
      ...r.graph.edges.keys,
      'SECRET',
      'DO_NOT_EXPORT',
      'private.example',
      'Bearer',
      'https://',
    ]) {
      expect(text, isNot(contains(value)));
    }
    expect(data['tracking']['device'], 'REDACTED');
    expect(
      (data['tracking']['transitionsFromExistingTimeline'] as List).length,
      32,
    );
    expect(text.length, lessThan(24000));
  });
  test('Readiness summary is data-only and mismatched Published version invalidates window', () async {
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
    final readiness = MapReadinessValidator.evaluate(
      f.input,
      graph: f.graph,
      requireGraph: true,
    );
    final s = PilotEvidenceSession(mode: PilotMode.published);
    addTearDown(s.dispose);
    s.begin(controller: c, readiness: readiness);
    var data = jsonDecode(s.export(controller: c, readiness: readiness)) as Map;
    expect(
      data['tracking']['readiness']['eligibleRouteSegments'],
      readiness.eligibleRouteEdges,
    );
    expect(
      data['tracking']['readiness']['physicallySurveyedByDataAlone'],
      false,
    );
    f.session.map.publication = (
      mapId: f.session.mapId,
      version: f.session.version + 1,
    );
    data = jsonDecode(s.export(controller: c, readiness: readiness)) as Map;
    expect(data['observationWindow']['consistency'], 'sessionOrVersionChanged');
    expect(data['observationWindow']['detectorAcceptedEvents'], isNull);
    expect(data['tracking']['pinnedContextMatches'], false);
  });
  test('A different controller on the same map cannot be mixed into a measurement window', () async {
    final f = await PublishedLiveFixture.create();
    IndoorTrackingController make() => IndoorTrackingController(
      graph: f.graph,
      map: f.session.map,
      route: f.route,
      provider: FakeSensorProvider(),
    );
    final first = make(), second = make();
    addTearDown(() async {
      await first.close();
      first.dispose();
      await second.close();
      second.dispose();
    });
    final s = PilotEvidenceSession(mode: PilotMode.published);
    addTearDown(s.dispose);
    s.begin(controller: first);
    expect(
      jsonDecode(
        s.export(controller: second),
      )['observationWindow']['consistency'],
      'sessionOrVersionChanged',
    );
    await first.close();
    expect(
      jsonDecode(s.export(controller: first))['tracking']['trackingState'],
      'disposed',
    );
  });
  test('User field measurement arithmetic is deterministic, distinct from endpoint error and zero-safe', () {
    final m = FieldTrialMeasurement(
      groundTruthMeters: 10,
      manualSteps: 20,
      detectorEvents: 22,
      strideMeters: .5,
      estimatedMeters: 11,
      endpointErrorBeforeQrMeters: 2.0,
    );
    expect(m.distanceBiasMeters, 1);
    expect(m.relativeDistanceError, .1);
    expect(m.relativeStepError, .1);
    expect(m.endpointErrorBeforeQrMeters, 2);
    expect(m.endpointErrorAfterQrMeters, isNull);
    final zero = FieldTrialMeasurement(
      groundTruthMeters: 0,
      manualSteps: 0,
      detectorEvents: 3,
      strideMeters: .7,
      estimatedMeters: 2.1,
      falseStepsStill: 3,
    );
    expect(zero.relativeDistanceError, isNull);
    expect(zero.relativeStepError, isNull);
    final tiny = FieldTrialMeasurement(
      groundTruthMeters: 1e-320,
      manualSteps: 1,
      detectorEvents: 1,
      strideMeters: .7,
      estimatedMeters: 10000,
    );
    expect(tiny.relativeDistanceError, isNull);
    expect(() => jsonEncode(tiny.toJson()), returnsNormally);
    expect(zero.toJson()['endpointErrorAfterQrUserMeasured'], isNull);
    for (final invalid in [-1.0, double.nan, double.infinity, 10001.0]) {
      expect(
        () => FieldTrialMeasurement(
          groundTruthMeters: invalid,
          manualSteps: 0,
          detectorEvents: 0,
          strideMeters: .7,
          estimatedMeters: 0,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => FieldTrialMeasurement(
        groundTruthMeters: 10,
        manualSteps: -1,
        detectorEvents: 0,
        strideMeters: .7,
        estimatedMeters: 0,
      ),
      throwsFormatException,
    );
    expect(
      () => FieldTrialMeasurement(
        groundTruthMeters: 10,
        manualSteps: 10,
        detectorEvents: 10,
        strideMeters: 0,
        estimatedMeters: 0,
      ),
      throwsFormatException,
    );
  });
}
