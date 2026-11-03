import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../indoor_tracking_controller.dart';
import '../map_readiness.dart';
import '../tracking_graph.dart';
import '../tracking_guidance.dart';
import '../../../services/published_read_failure.dart';
import 'field_trial_measurement.dart';
import '../sensors/sensor_models.dart';
import '../indoor_position.dart';

enum PilotCheckStatus { notTested, pass, fail }

enum PilotCheck {
  apkInstalled,
  apiReachable,
  qrResolver,
  snapshotVersion,
  floorImages,
  preflight,
  guidedSetup,
  realDetector,
  blueDot,
  qrCorrection,
  manualFallback,
}

enum PilotPhase {
  preparation,
  straightWalk,
  stationary,
  rotateInPlace,
  reverseWalk,
  qrCorrection,
  lifecycle,
  fallback,
}

enum PilotMode { local, published }

enum PilotNote {
  falseSteps,
  missedSteps,
  headingStale,
  changedPhoneHold,
  junctionHeld,
  budgetHeld,
  imageUnavailable,
  qrRejected,
  networkUnavailable,
  lifecycleInterrupted,
}

String pilotCheckLabel(PilotCheck c) => const {
  PilotCheck.apkInstalled: 'APK cài / cập nhật thành công',
  PilotCheck.apiReachable: 'API reachable từ điện thoại',
  PilotCheck.qrResolver: 'QR resolver thật hoạt động',
  PilotCheck.snapshotVersion: 'Map/version tải đúng',
  PilotCheck.floorImages: 'Ảnh tầng hiển thị',
  PilotCheck.preflight: 'Published preflight đạt',
  PilotCheck.guidedSetup: 'Hoàn tất guided setup',
  PilotCheck.realDetector: 'Detector nhận bước chân thật',
  PilotCheck.blueDot: 'Blue dot cập nhật khi đi thật',
  PilotCheck.qrCorrection: 'QR correction thật hoạt động',
  PilotCheck.manualFallback: 'Manual fallback hoạt động',
}[c]!;
String pilotStatusLabel(PilotCheckStatus s) => switch (s) {
  PilotCheckStatus.notTested => 'NOT TESTED',
  PilotCheckStatus.pass => 'PASS',
  PilotCheckStatus.fail => 'FAIL',
};

// Export allowlists, not regex-based trust of arbitrary diagnostic strings.
const _reasons = {
  'none',
  'needsAnchor',
  'selectEdgeAndAlign',
  'alignAfterStart',
  'estimated',
  'manualDirectionExperiment',
  'reverse',
  'againstOneWay',
  'candidateNodeConfirm',
  'junctionConfirmation',
  'unsupportedGeometry',
  'headingConflict',
  'anchorAged',
  'staleOrientation',
  'headingRequired',
  'strideRequired',
  'activityPermissionDenied',
  'stepDetectorUnavailable',
  'sensorOverflow',
  'pausedNeedsConfirmation',
  'scanQr',
  'qrCorrectionRejected',
  'qrCancelledResumeExplicitly',
  'confirmNewFloor',
  'finished',
  'sensorFailure',
  'mapVersionChanged',
  'mapVersionMismatch',
  'nodeMissing',
  'publishedResolverRequired',
  'resolveRejectedOrOffline',
  'accepted',
  'userPaused',
  'routeReplaced',
  'routeOrAppHidden',
  'setupOpened',
  'relativeOrientation',
  'rerouteFailed',
  'invalidMapIdentity',
  'floorIdentity',
  'floorImageMissing',
  'floorsMissing',
  'nodeIdentity',
  'nodeFloorMissing',
  'nodeCoordinates',
  'edgeIdentity',
  'edgeEndpointMissing',
  'duplicateDirection',
  'edgeDistance',
  'edgeInactive',
  'transitionType',
  'floorTransition',
  'unsupportedEdgeType',
  'degenerateGeometry',
  'physicalSurveyRequired',
  'routeStartOrIdentity',
  'routeDisconnected',
  'disconnectedGraph',
  'trackingGraphUnavailable',
  'snapshotGraphMismatch',
  'noEligibleRouteEdges',
  'readyByData',
};
const _events = {
  'trackingStarted',
  'stateChanged',
  'trackingHeld',
  'sensorStart',
  'resumed',
  'strideCalibrated',
  'qrAnchor',
  'manualAnchor',
  'headingAligned',
  'edgeSelectedManually',
  'stepAccepted',
  'movementRejected',
  'edgeCandidateChanged',
  'edgeContinuedEstimated',
  'junctionAmbiguous',
  'overflow',
  'paused',
  'qrCorrectionAccepted',
  'qrCorrectionRejected',
  'rerouteConfirmedAnchor',
  'rerouteFailed',
  'stopped',
  'disposed',
};
String safePilotCode(String? raw) {
  if (raw == null || raw.isEmpty) return 'none';
  return _reasons.contains(raw) ||
          PublishedReadCode.values.any((k) => 'published_${k.name}' == raw)
      ? raw
      : 'unrecognized';
}

String _device(String? value) {
  if (value == null) return 'notProbed';
  final sensitive = RegExp(
    r'https?://|WMQR1:|Bearer\s|[a-fA-F0-9]{32,}|eyJ[\w-]+\.|[\w.+-]+@[\w.-]+|[0-9a-fA-F]{8}-[0-9a-fA-F-]{27}',
    caseSensitive: false,
  );
  if (sensitive.hasMatch(value)) return 'REDACTED';
  final safe = value.replaceAll(RegExp(r'[^a-zA-Z0-9À-ỹ _()./+:-]'), '');
  return safe.substring(0, safe.length.clamp(0, 80));
}

class _PilotSnapshot {
  _PilotSnapshot(
    this.owner,
    this.key,
    this.pinMatches,
    this.detector,
    this.accepted,
    this.rejected,
    this.meters,
    this.data,
  );
  final Object owner;
  final bool pinMatches;
  final TrackingMapKey key;
  final int detector, accepted, rejected;
  final double meters;
  final Map<String, Object?> data;
  factory _PilotSnapshot.capture(
    IndoorTrackingController c,
    MapReadinessReport? readiness,
  ) {
    final caps = c.sensors.capabilities;
    final error = safePilotCode(c.lastError);
    final reason = safePilotCode(c.reason);
    final recovery = c.reason == 'qrCorrectionRejected'
        ? qrTrackingGuidance(error)
        : trackingGuidance(reason);
    final pinMatches = c.graph.localPilot
        ? c.map.publication == null
        : c.map.publication?.mapId == c.graph.key.mapId &&
              c.map.publication?.version == c.graph.key.version;
    return _PilotSnapshot(
      c,
      c.graph.key,
      pinMatches,
      c.sensors.detectorEvents,
      c.acceptedMovements,
      c.rejectedMovements,
      c.integratedDistance,
      {
        'device': _device(caps?.device),
        'androidApi': caps?.androidApi,
        'mode': c.graph.localPilot ? 'local' : 'published',
        'publishedVersion': c.graph.localPilot ? null : c.graph.key.version,
        'trackingState': c.isClosed ? 'disposed' : c.status.name,
        'lastStateTransition': c.lastTransition
            .split('->')
            .take(2)
            .map(
              (s) => TrackingStatus.values.any((v) => v.name == s)
                  ? s
                  : 'unrecognized',
            )
            .toList(),
        'holdReason': safePilotCode(c.holdReason),
        'reason': reason,
        'errorCode': error,
        'recoveryAction': recovery.action.name,
        'confidence': c.isClosed
            ? 'sessionClosed'
            : c.position.value?.confidence.name,
        'permission': c.sensors.permission?.name,
        'strideMeters': c.pdr.stride?.meters,
        'pinnedContextMatches': pinMatches,
        'sensorCapabilities': [
          for (final kind in caps?.sensors ?? const <SensorCapability>[])
            {
              'kind': kind.kind.name,
              'available': kind.available,
              'registration':
                  c.sensors.result?.registrations
                      .where((r) => r.kind == kind.kind)
                      .firstOrNull
                      ?.state
                      .name ??
                  'notRequested',
            },
        ],
        'detectorAcceptedEventsTotal': c.sensors.detectorEvents,
        'acceptedDisplacementObservationsTotal': c.acceptedMovements,
        'rejectedMovementObservationsTotal': c.rejectedMovements,
        'estimatedIntegratedMetersTotal': c.integratedDistance,
        'orientationFresh': c.orientationFresh,
        'budgetUsed': c.stepsSinceAnchor,
        'budgetLimit': IndoorTrackingController.movementBudget,
        'overflowEvents': c.sensors.overflowEvents,
        'rejectedSensorEvents': c.sensors.rejectedEvents,
        'qrCorrectionCount': c.corrections,
        'qrCorrectionResult': safePilotCode(c.lastCorrection),
        'pauseReason': safePilotCode(c.pauseReason),
        'generation': c.pdr.generation,
        'readiness': readiness == null
            ? null
            : {
                'level': readiness.level.name,
                'readyByData': readiness.readyByData,
                'eligibleRouteSegments': readiness.eligibleRouteEdges,
                'routeSegments': readiness.routeEdges,
                'blockingIssueCount': readiness.issues
                    .where((i) => i.blocksSession)
                    .length,
                'reasonCodes':
                    (readiness.issues
                            .map((i) => safePilotCode(i.reasonCode))
                            .toSet()
                            .toList()
                          ..sort())
                        .take(24)
                        .toList(),
                'physicallySurveyedByDataAlone': false,
              },
        'transitionsFromExistingTimeline': [
          for (final e in c.timeline.events.skip(
            (c.timeline.events.length - 32).clamp(0, 96),
          ))
            {
              'timeUtc': e.timeUtc.toUtc().toIso8601String(),
              'generation': e.generation,
              'event': _events.contains(e.event) ? e.event : 'unrecognized',
              'reason': safePilotCode(e.reason),
            },
        ],
      },
    );
  }
}

class PilotEvidenceSession extends ChangeNotifier {
  PilotEvidenceSession({required this.mode, DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final PilotMode mode;
  final DateTime Function() _now;
  PilotPhase phase = PilotPhase.preparation;
  final _checks = {
    for (final c in PilotCheck.values) c: PilotCheckStatus.notTested,
  };
  Map<PilotCheck, PilotCheckStatus> get checks => Map.unmodifiable(_checks);
  final _notes = <PilotNote>{};
  Set<PilotNote> get notes => Set.unmodifiable(_notes);
  DateTime? startedAt, endedAt;
  _PilotSnapshot? _start, _end;
  FieldTrialMeasurement? measurement;
  void mark(PilotCheck check, PilotCheckStatus status) {
    _checks[check] = status;
    notifyListeners();
  }

  void setPhase(PilotPhase next) {
    phase = next;
    notifyListeners();
  }

  void note(PilotNote note, bool value) {
    if (value) {
      _notes.add(note);
    } else {
      _notes.remove(note);
    }
    notifyListeners();
  }

  void begin({
    IndoorTrackingController? controller,
    MapReadinessReport? readiness,
  }) {
    startedAt = _now().toUtc();
    endedAt = null;
    _start = controller == null
        ? null
        : _PilotSnapshot.capture(controller, readiness);
    _end = null;
    measurement = null;
    notifyListeners();
  }

  void end({
    IndoorTrackingController? controller,
    MapReadinessReport? readiness,
  }) {
    if (startedAt == null) {
      throw const FormatException('Bắt đầu ghi nhận trước khi chốt số liệu.');
    }
    endedAt = _now().toUtc();
    _end = controller == null
        ? null
        : _PilotSnapshot.capture(controller, readiness);
    notifyListeners();
  }

  void setMeasurement(FieldTrialMeasurement value) {
    measurement = value;
    notifyListeners();
  }

  void freezeClosedSession(
    IndoorTrackingController controller,
    MapReadinessReport? readiness,
  ) {
    _end = _PilotSnapshot.capture(controller, readiness);
    if (startedAt != null) endedAt = _now().toUtc();
    notifyListeners();
  }

  String export({
    IndoorTrackingController? controller,
    MapReadinessReport? readiness,
  }) {
    final current =
        _end ??
        (controller == null
            ? null
            : _PilotSnapshot.capture(controller, readiness));
    final start = _start;
    final valid =
        start != null &&
        current != null &&
        identical(start.owner, current.owner) &&
        start.pinMatches &&
        current.pinMatches &&
        start.key == current.key &&
        current.detector >= start.detector &&
        current.accepted >= start.accepted &&
        current.rejected >= start.rejected &&
        current.meters >= start.meters;
    final window = {
      'consistency': startedAt == null
          ? 'notStarted'
          : start == null
          ? 'noLinkedTrackingSession'
          : valid
          ? 'samePinnedSession'
          : 'sessionOrVersionChanged',
      'detectorAcceptedEvents': valid
          ? current.detector - start.detector
          : null,
      'acceptedDisplacementObservations': valid
          ? current.accepted - start.accepted
          : null,
      'rejectedMovementObservations': valid
          ? current.rejected - start.rejected
          : null,
      'estimatedIntegratedMeters': valid ? current.meters - start.meters : null,
    };
    return const JsonEncoder.withIndent('  ').convert({
      'schema': 'WayMarkPilotEvidence1',
      'app': {
        'applicationId': const bool.fromEnvironment('WAYMARK_LIVE_TEST')
            ? 'com.example.waymark.livetest'
            : 'com.example.waymark',
        'version': '1.0.0+1',
        'toolkitSprint': 7,
        'buildMode': kDebugMode ? 'debug' : 'release',
        'liveTestDefine': const bool.fromEnvironment('WAYMARK_LIVE_TEST'),
      },
      'mode': current?.data['mode'] ?? mode.name,
      'phase': phase.name,
      'startedAtUtc': startedAt?.toIso8601String(),
      'endedAtUtc': endedAt?.toIso8601String(),
      'checklistEvidenceSource': 'USER_REPORTED_NOT_INDEPENDENTLY_VERIFIED',
      'checklist': {
        for (final c in PilotCheck.values)
          c.name: pilotStatusLabel(_checks[c]!),
      },
      'notesFixedTagsOnly': _notes.map((n) => n.name).toList(),
      'tracking': current?.data,
      'observationWindow': window,
      'userMeasuredTrial': measurement?.toJson(),
      'physicalAccuracy': 'NOT_VERIFIED',
      'publishedServerCameraE2e': 'NOT_INDEPENDENTLY_VERIFIED',
      'privacy': 'No tokens, endpoint, identities, names or coordinate trace; no automatic upload.',
    });
  }
}
