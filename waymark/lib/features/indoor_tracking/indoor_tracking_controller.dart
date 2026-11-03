import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../models/route_models.dart';
import '../navigation/local_map_navigation.dart';
import 'indoor_position.dart';
import 'tracking_graph.dart';
import 'map_matching_engine.dart';
import 'pdr_engine.dart';
import 'qr_relocalization.dart';
import 'sensors/sensor_models.dart';
import 'sensors/sensor_provider.dart';
import 'sensors/sensor_session_controller.dart';
import 'tracking_diagnostics.dart';

class IndoorTrackingController extends ChangeNotifier {
  IndoorTrackingController({
    required this.graph,
    required this.map,
    required WayMarkRoute route,
    required SensorProvider provider,
    DateTime Function()? now,
    this.onConfirmedOffRoute,
  }) : sensors = SensorSessionController(provider),
       matcher = MapMatchingEngine(graph),
       qr = QrRelocalization(map, graph),
       _now = now ?? DateTime.now {
    _routeNodes = graph.routeNodes(map, route);
    _setRouteEdges();
    sensors.addListener(_sensorStateChanged);
    _observationSubscription = sensors.observations.listen(_onSample);
    _freshnessTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _checkFreshness(),
    );
    _event('trackingStarted');
  }
  final TrackingGraph graph;
  final LocalMapNavigation map;
  final SensorSessionController sensors;
  final MapMatchingEngine matcher;
  final QrRelocalization qr;
  final pdr = PdrEngine();
  final position = ValueNotifier<IndoorPosition?>(null);
  final Future<void> Function(VerifiedTrackingAnchor anchor)?
  onConfirmedOffRoute;
  final DateTime Function() _now;
  late final StreamSubscription<SensorSample> _observationSubscription;
  late List<String> _routeNodes;
  final _routeEdges = <String>{};
  final timeline = TrackingTimeline();
  List<String> get diagnosticEvents =>
      timeline.events.map((e) => e.sanitized).toList(growable: false);
  late final Timer _freshnessTimer;
  DateTime? _lastOrientationReceipt;
  int _orientationReceiptAgeNs = 0;
  int? lastAcceptedStepNs;
  int acceptedMovements = 0, rejectedMovements = 0, reanchors = 0;
  String lastTransition = 'none', pauseReason = 'none', holdReason = 'none';
  static const movementBudget = 40, budgetWarningAt = 32;
  bool _requiresAnchor = false;
  TrackingStatus status = TrackingStatus.needsAnchor;
  String reason = 'needsAnchor', lastCorrection = 'none';
  IndoorPosition? beforeLastCorrection;
  String? lastError;
  double integratedDistance = 0, overshootMeters = 0;
  int corrections = 0, reroutes = 0, stepsSinceAnchor = 0;
  bool strideConfirmed = false, _allowMotion = false, _visible = true;
  bool _alive = true, _rerouting = false;
  int _revision = 0, _seenOverflow = 0, _seenSensorRejects = 0;
  DateTime? _lastReroute;
  Future<void>? _shutdown;

  bool get isClosed => !_alive;
  bool get _mapContextValid => graph.localPilot
      ? map.publication == null
      : map.publication?.mapId == graph.key.mapId &&
            map.publication?.version == graph.key.version;
  bool get requiresAnchor => _requiresAnchor;
  String? get destinationNodeId => _routeNodes.lastOrNull;
  bool get budgetNearLimit => stepsSinceAnchor >= budgetWarningAt;
  int get remainingBudget =>
      (movementBudget - stepsSinceAnchor).clamp(0, movementBudget);
  bool get orientationFresh {
    final receipt = _lastOrientationReceipt;
    final age = receipt == null ? null : _now().difference(receipt);
    return sensorRunning &&
        receipt != null &&
        age != null &&
        !age.isNegative &&
        age.inMicroseconds * 1000 + _orientationReceiptAgeNs <=
            PdrEngine.staleOrientationNs &&
        pdr.latestHeading?.generation == pdr.generation &&
        pdr.latestHeading?.reliable == true;
  }

  bool get showTravelArrow =>
      canIntegrate &&
      orientationFresh &&
      pdr.heading != null &&
      position.value?.confidence == PositionConfidence.estimated;
  TrackingEdge? recommendedEdgeAt(String? node) {
    final i = _routeNodes.indexOf(node ?? '');
    return i < 0 || i + 1 >= _routeNodes.length
        ? null
        : graph.edgeBetween(_routeNodes[i], _routeNodes[i + 1]);
  }

  double? get estimatedRouteRemaining {
    final p = position.value;
    if (p == null || offRoute) return null;
    final edge = graph.edges[p.edgeId];
    final index = _routeNodes.indexOf(edge?.to ?? p.nodeId ?? '');
    if (index < 0) return null;
    var meters = edge == null ? 0.0 : edge.meters - p.progressMeters;
    for (var i = index; i + 1 < _routeNodes.length; i++) {
      final e = graph.edgeBetween(_routeNodes[i], _routeNodes[i + 1]);
      if (e == null) return null;
      meters += e.meters;
    }
    return meters;
  }

  void confirmGeometry(String edgeId, bool confirmed) {
    final edge = graph.edges[edgeId];
    if (!_alive || edge == null || !edge.geometryEligible || !edge.active) {
      return;
    }
    if (confirmed) {
      matcher.confirmedStraightEdges.add(edgeId);
    } else {
      matcher.confirmedStraightEdges.remove(edgeId);
    }
    if (!confirmed && position.value?.edgeId == edgeId && canIntegrate) {
      _hold('unsupportedGeometry');
    }
    notifyListeners();
  }

  void _checkFreshness() {
    if (!_alive || !sensorRunning || pdr.manualBearing != null) return;
    if (canIntegrate &&
        !orientationFresh &&
        position.value?.confidence == PositionConfidence.estimated) {
      position.value = position.value!.withConfidence(
        PositionConfidence.uncertain,
        'staleOrientation',
      );
      _state(TrackingStatus.uncertain, 'staleOrientation');
    }
  }

  bool get sensorRunning => sensors.state == SensorSessionState.running;
  bool get canIntegrate => _alive && _allowMotion && sensorRunning && _visible;
  String? get currentNodeId => position.value?.nodeId;
  List<TrackingEdge> get candidates =>
      position.value == null ? const [] : matcher.candidates(position.value!);
  bool get offRoute {
    final p = position.value;
    return p?.edgeId != null
        ? !_routeEdges.contains(p!.edgeId)
        : p?.nodeId != null && !_routeNodes.contains(p!.nodeId);
  }

  void _setRouteEdges() {
    _routeEdges.clear();
    for (var i = 0; i + 1 < _routeNodes.length; i++) {
      final e = graph.edgeBetween(_routeNodes[i], _routeNodes[i + 1]);
      if (e != null) _routeEdges.add(e.id);
    }
  }

  void _event(String code, [String detail = '']) {
    timeline.add(_now(), pdr.generation, code, detail);
  }

  void _state(TrackingStatus next, String code) {
    if (!_alive) return;
    if (status != next || reason != code) {
      lastTransition = '${status.name}->${next.name}';
      _event('stateChanged', code);
    }
    status = next;
    reason = code;
    notifyListeners();
  }

  void _hold(String code, {bool invalidateHeading = false}) {
    _allowMotion = false;
    holdReason = code;
    if (code == 'anchorAged' || code == 'sensorOverflow') {
      _requiresAnchor = true;
    }
    _event('trackingHeld', code);
    if (invalidateHeading) pdr.invalidateHeading();
    final p = position.value;
    if (p != null) {
      position.value = p.withConfidence(PositionConfidence.uncertain, code);
    }
    _state(TrackingStatus.uncertain, code);
  }

  Future<void> requestPermission() async {
    if (!_alive || !_visible) return;
    await sensors.requestPermission();
    if (!_alive) return;
    if (sensors.permission == MotionPermission.denied) {
      _state(TrackingStatus.permissionDenied, 'activityPermissionDenied');
    }
  }

  Future<void> startSensors() async {
    if (!_alive || !_visible || status == TrackingStatus.finished) return;
    if (!_mapContextValid) {
      _hold('mapVersionChanged', invalidateHeading: true);
      return;
    }
    final ticket = ++_revision;
    _allowMotion = false;
    pdr.invalidateHeading();
    _lastOrientationReceipt = null;
    _state(
      _requiresAnchor ? TrackingStatus.uncertain : TrackingStatus.calibrating,
      _requiresAnchor ? holdReason : 'alignAfterStart',
    );
    await sensors.refresh();
    if (!_alive || ticket != _revision || !_visible) return;
    final caps = sensors.capabilities;
    final orientation =
        caps?.forKind(SensorKind.rotationVector).available == true
        ? SensorKind.rotationVector
        : SensorKind.gameRotationVector;
    await sensors.start(
      SensorConfig(
        kinds: {SensorKind.stepDetector, SensorKind.stepCounter, orientation},
      ),
    );
    if (!_alive || ticket != _revision || !_visible) {
      await sensors.pause();
      return;
    }
    final result = sensors.result;
    if (sensors.state != SensorSessionState.running ||
        result == null ||
        !result.registeredKinds.contains(SensorKind.stepDetector)) {
      final denied = sensors.permission == MotionPermission.denied;
      await sensors.pause();
      if (!_alive || ticket != _revision) return;
      _state(
        denied
            ? TrackingStatus.permissionDenied
            : TrackingStatus.sensorUnavailable,
        denied ? 'activityPermissionDenied' : 'stepDetectorUnavailable',
      );
      return;
    }
    if (pdr.generation != result.generation) {
      pdr.beginGeneration(result.generation);
    }
    _event('sensorStart');
    if (pauseReason != 'none') _event('resumed', pauseReason);
    _state(
      _requiresAnchor ? TrackingStatus.uncertain : TrackingStatus.calibrating,
      _requiresAnchor
          ? holdReason
          : position.value == null
          ? 'needsAnchor'
          : 'alignAfterStart',
    );
  }

  void setStride(StrideCalibration calibration) {
    if (!_alive) return;
    pdr.stride = calibration;
    strideConfirmed = true;
    pdr.fenceBaseline();
    _event('strideCalibrated');
    notifyListeners();
  }

  void manualAnchor(String nodeId) {
    _applyAnchor(
      VerifiedTrackingAnchor(
        graph.key,
        nodeId,
        graph.nodes[nodeId]?.floorKey ?? '',
        PositionSource.manualExperiment,
      ),
    );
  }

  void _applyAnchor(VerifiedTrackingAnchor anchor) {
    if (!_mapContextValid) {
      throw const FormatException(
        'Map hoặc phiên bản đã đổi. Hãy mở lại điều hướng với snapshot mới.',
      );
    }
    final next = anchor.position(graph, generation: pdr.generation);
    if (!_alive || status == TrackingStatus.finished) return;
    _revision++;
    _allowMotion = false;
    pdr.invalidateHeading();
    stepsSinceAnchor = 0;
    _requiresAnchor = false;
    reanchors++;
    holdReason = 'none';
    lastError = null;
    position.value = next;
    _event(anchor.source == PositionSource.qr ? 'qrAnchor' : 'manualAnchor');
    _state(TrackingStatus.anchored, 'selectEdgeAndAlign');
    unawaited(_maybeReroute(anchor));
  }

  /// Explicit confirmation; no route-derived bearing is ever calibrated
  /// silently. Reconfirming a paused mid-edge position requires stayedStill.
  void confirmEdge(
    String edgeId, {
    required bool straightGeometry,
    bool manualDirection = false,
    bool stayedStill = false,
    bool reverse = false,
  }) {
    if (!_alive || !sensorRunning || !strideConfirmed) {
      throw const FormatException(
        'Cần cảm biến bước đang chạy và xác nhận chiều dài bước.',
      );
    }
    if (_requiresAnchor) {
      throw const FormatException(
        'Cần xác nhận lại vị trí bằng QR hoặc mốc thủ công trước khi tiếp tục.',
      );
    }
    if (!_mapContextValid) {
      throw const FormatException(
        'Phiên bản bản đồ đã đổi. Hãy mở lại điều hướng.',
      );
    }
    final p = position.value, edge = graph.edges[edgeId];
    if (p == null ||
        edge == null ||
        !edge.active ||
        (p.nodeId != edge.from && !(p.edgeId == edge.id && stayedStill))) {
      throw const FormatException('Cạnh không nối từ vị trí được xác nhận.');
    }
    if (graph.isTransition(edge)) {
      _allowMotion = false;
      position.value = IndoorPosition(
        map: graph.key,
        kind: PositionKind.floorTransition,
        floorKey: graph.nodes[edge.from]!.floorKey,
        nodeId: edge.from,
        targetFloorKey: graph.nodes[edge.to]!.floorKey,
        point: graph.nodes[edge.from]!.point,
        source: PositionSource.manualExperiment,
        confidence: PositionConfidence.uncertain,
        reason: 'confirmNewFloor',
        generation: pdr.generation,
      );
      unawaited(sensors.pause());
      _state(TrackingStatus.uncertain, 'confirmNewFloor');
      return;
    }
    if (!straightGeometry || !edge.geometryEligible) {
      _hold('unsupportedGeometry');
      throw const FormatException(
        'Chỉ hỗ trợ đoạn thẳng đã đối chiếu thực tế. Dùng manual/QR.',
      );
    }
    final direction = wrapAngle(edge.bearing! + (reverse ? math.pi : 0));
    if (manualDirection) {
      pdr.heading = null;
      pdr.manualBearing = direction;
    } else {
      final observation = pdr.latestHeading;
      if (observation == null ||
          !orientationFresh ||
          observation.generation != pdr.generation ||
          pdr.lastTimestampNs - observation.timestampNs >
              PdrEngine.staleOrientationNs) {
        throw const FormatException(
          'Chờ orientation mới hoặc xác nhận chiều thủ công.',
        );
      }
      pdr.heading = HeadingCalibration.align(observation, direction);
      pdr.manualBearing = null;
    }
    matcher.confirmedStraightEdges.add(edge.id);
    _event(
      'headingAligned',
      manualDirection ? 'manualDirectionExperiment' : 'relativeOrientation',
    );
    _event('edgeSelectedManually');
    holdReason = 'none';
    pdr.fenceBaseline();
    if (p.edgeId != edge.id) {
      position.value = matcher.onEdge(
        edge,
        generation: pdr.generation,
        source: p.source == PositionSource.pdr
            ? PositionSource.pdr
            : PositionSource.manualExperiment,
        confidence: p.source == PositionSource.pdr
            ? PositionConfidence.uncertain
            : PositionConfidence.manualConfirmation,
      );
    }
    _allowMotion = true;
    _state(
      TrackingStatus.tracking,
      manualDirection ? 'manualDirectionExperiment' : 'estimated',
    );
  }

  void _onSample(SensorSample sample) {
    if (!_alive ||
        !_visible ||
        status == TrackingStatus.finished ||
        status == TrackingStatus.relocalizing ||
        !sensorRunning) {
      return;
    }
    final generation = sensors.result?.generation;
    if (generation == null || sample.generation != generation) return;
    if (!_mapContextValid) {
      if (reason != 'mapVersionChanged') {
        _hold('mapVersionChanged', invalidateHeading: true);
        unawaited(sensors.pause());
      }
      return;
    }
    if (pdr.generation != generation) pdr.beginGeneration(generation);
    final update = pdr.ingest(sample);
    if ((sample.kind == SensorKind.rotationVector ||
            sample.kind == SensorKind.gameRotationVector) &&
        pdr.latestHeading?.timestampNs == sample.sensorTimestampNs) {
      _lastOrientationReceipt = _now();
      _orientationReceiptAgeNs = math.max(
        0,
        sample.nativeReceiveTimestampNs - sample.sensorTimestampNs,
      );
    }
    if (sample.kind == SensorKind.stepDetector) {
      lastAcceptedStepNs = sample.sensorTimestampNs;
      _event('stepAccepted');
    }
    if (!canIntegrate || position.value == null) return;
    if (update.reason != null && sample.kind == SensorKind.stepDetector) {
      rejectedMovements++;
      holdReason = update.reason!;
      _event('movementRejected', update.reason!);
      position.value = position.value!.withConfidence(
        PositionConfidence.uncertain,
        update.reason!,
      );
      _state(TrackingStatus.uncertain, update.reason!);
      return; // May recover with fresh orientation on a later REAL step.
    }
    final motion = update.motion;
    if (motion == null) return;
    stepsSinceAnchor++;
    if (stepsSinceAnchor > movementBudget) {
      rejectedMovements++;
      _hold('anchorAged');
      return;
    }
    final before = position.value!;
    // An estimated junction never becomes an anchor. Manual bearing cannot
    // prove a unique next corridor; only a fresh calibrated observation can.
    if (before.kind == PositionKind.nodeAnchor &&
        before.source == PositionSource.pdr &&
        (motion.manualDirection ||
            !orientationFresh ||
            pdr.heading == null ||
            _requiresAnchor)) {
      rejectedMovements++;
      _hold('junctionConfirmation');
      return;
    }
    final result = matcher.advance(before, motion);
    if (result.movedMeters > 0) {
      acceptedMovements++;
    } else {
      rejectedMovements++;
      _event('movementRejected', result.reason);
    }
    if (result.position.edgeId != before.edgeId ||
        result.position.nodeId != before.nodeId) {
      _event('edgeCandidateChanged', result.reason);
    }
    if (before.kind == PositionKind.nodeAnchor &&
        before.source == PositionSource.pdr &&
        result.position.edgeId != null) {
      _event('edgeContinuedEstimated');
    }
    if (result.reason == 'junctionConfirmation') {
      _event('junctionAmbiguous');
      _allowMotion = false;
    }
    holdReason = result.position.confidence == PositionConfidence.uncertain
        ? result.reason
        : 'none';
    integratedDistance += result.movedMeters;
    overshootMeters +=
        result.overshoot; // Never silently carried across a branch.
    position.value = result.position;
    final nextStatus =
        result.position.confidence == PositionConfidence.uncertain
        ? TrackingStatus.uncertain
        : TrackingStatus.tracking;
    if (status != nextStatus || reason != result.reason) {
      _state(nextStatus, result.reason);
    } else if (budgetNearLimit) {
      notifyListeners();
    }
  }

  void _sensorStateChanged() {
    if (!_alive) return;
    if (sensors.overflowEvents > _seenOverflow) {
      _seenOverflow = sensors.overflowEvents;
      _event('overflow');
      _hold('sensorOverflow', invalidateHeading: true);
    }
    if (sensors.rejectedEvents > _seenSensorRejects) {
      _seenSensorRejects = sensors.rejectedEvents;
    }
    if (status != TrackingStatus.relocalizing &&
        status != TrackingStatus.finished) {
      if (sensors.state == SensorSessionState.error) {
        _allowMotion = false;
        lastError = 'sensorFailure';
        _state(TrackingStatus.failed, 'sensorFailure');
      } else if (sensors.state == SensorSessionState.permissionDenied) {
        _allowMotion = false;
        _state(TrackingStatus.permissionDenied, 'activityPermissionDenied');
      } else if (sensors.state == SensorSessionState.paused &&
          (status == TrackingStatus.tracking ||
              status == TrackingStatus.calibrating)) {
        _allowMotion = false;
        pdr.invalidateHeading();
        _state(TrackingStatus.paused, 'pausedNeedsConfirmation');
      }
    }
    notifyListeners(); // SensorSessionController already throttles raw sample updates.
  }

  Future<void> pause({String cause = 'userPaused'}) async {
    if (!_alive || status == TrackingStatus.finished) return;
    _revision++;
    _allowMotion = false;
    pdr.invalidateHeading();
    pauseReason = cause;
    _event('paused', pauseReason);
    final p = position.value;
    if (p != null) {
      position.value = p.withConfidence(
        PositionConfidence.uncertain,
        'pausedNeedsConfirmation',
      );
    }
    _state(TrackingStatus.paused, 'pausedNeedsConfirmation');
    await sensors.pause();
  }

  Future<void> setVisible(bool visible) async {
    _visible = visible;
    if (!visible &&
        status != TrackingStatus.finished &&
        status != TrackingStatus.relocalizing) {
      await pause(cause: 'routeOrAppHidden');
    }
    await sensors.setVisible(visible);
  }

  Future<int> beginRelocalization() async {
    if (!_alive || status == TrackingStatus.finished) return -1;
    final ticket = ++_revision;
    _allowMotion = false;
    pdr.invalidateHeading();
    beforeLastCorrection = position.value;
    _state(TrackingStatus.relocalizing, 'scanQr');
    await sensors.pause();
    return ticket;
  }

  Future<bool> completeRelocalization(String payload, int ticket) async {
    if (!_alive || ticket < 0 || ticket != _revision) return false;
    try {
      final anchor = await qr.resolve(payload);
      if (!_alive ||
          ticket != _revision ||
          status != TrackingStatus.relocalizing) {
        return false;
      }
      _applyAnchor(anchor);
      corrections++;
      lastCorrection = 'accepted';
      _event('qrCorrectionAccepted');
      notifyListeners();
      return true;
    } on QrLocalizationFailure catch (error) {
      if (!_alive || ticket != _revision) return false;
      lastCorrection = error.code;
      lastError = error.code;
      _event('qrCorrectionRejected');
      _hold('qrCorrectionRejected', invalidateHeading: true);
      return false;
    }
  }

  void cancelRelocalization(int ticket) {
    if (!_alive || ticket != _revision) return;
    _revision++;
    _allowMotion = false;
    _state(TrackingStatus.paused, 'qrCancelledResumeExplicitly');
  }

  Future<void> _maybeReroute(VerifiedTrackingAnchor anchor) async {
    if (!_alive ||
        onConfirmedOffRoute == null ||
        _rerouting ||
        _routeNodes.contains(anchor.nodeId)) {
      return;
    }
    final now = _now();
    if (_lastReroute != null && now.difference(_lastReroute!).inSeconds < 8) {
      return;
    }
    _lastReroute = now;
    _rerouting = true;
    final ticket = _revision;
    try {
      await onConfirmedOffRoute!(anchor);
      if (_alive) {
        reroutes++;
        _event('rerouteConfirmedAnchor');
      }
    } catch (_) {
      if (_alive && ticket == _revision) {
        lastError = 'rerouteFailed';
        _event('rerouteFailed');
        notifyListeners();
      }
    } finally {
      _rerouting = false;
    }
  }

  Future<void> replaceRoute(WayMarkRoute route) async {
    if (!_alive) return;
    _routeNodes = graph.routeNodes(map, route);
    _setRouteEdges();
    await pause(
      cause: 'routeReplaced',
    ); // Invalidates pending QR and sensor callbacks; position retained.
  }

  Future<void> finish() async {
    if (!_alive) return;
    _revision++;
    _allowMotion = false;
    _event('stopped');
    _state(TrackingStatus.finished, 'finished');
    await sensors.stop();
  }

  /// Default export intentionally omits map/node/edge IDs, names, coordinates,
  /// QR/JWT/URLs, free-form exception text and movement history.
  String sanitizedDiagnostics() => [
    'WayMark Live Test diagnostics v1',
    'mode=${graph.localPilot ? 'localPilot' : 'published'} version=${graph.key.version}',
    'status=${status.name} reason=$reason',
    'permission=${sensors.permission?.name ?? 'unknown'} sensors=${sensors.result?.registeredKinds.map((k) => k.name).join(',') ?? 'none'}',
    'steps=${sensors.detectorEvents} counterRaw=${sensors.counterRaw ?? 'none'}',
    'estimatedIntegratedMeters=${integratedDistance.toStringAsFixed(2)} stride=${pdr.stride?.meters ?? 'unset'}',
    'phoneOrientation=${pdr.latestHeading == null
        ? 'missing'
        : pdr.latestHeading!.reliable
        ? 'reliableObservation'
        : 'unreliable'}',
    'positionKind=${position.value?.kind.name ?? 'none'} confidence=${position.value?.confidence.name ?? 'none'}',
    'progressMeters=${position.value?.progressMeters.toStringAsFixed(2) ?? 'none'}',
    'generation=${pdr.generation} overflowEvents=${sensors.overflowEvents} rejected=${sensors.rejectedEvents + pdr.rejectedSteps}',
    'corrections=$corrections correctionResult=$lastCorrection reroutes=$reroutes',
    'acceptedMovements=$acceptedMovements rejectedMovements=$rejectedMovements reanchors=$reanchors budget=$stepsSinceAnchor/$movementBudget',
    'orientationFresh=$orientationFresh headingAligned=${pdr.heading != null} lastStepNs=${lastAcceptedStepNs ?? 'none'}',
    'candidateCount=${candidates.length} holdReason=$holdReason pauseReason=$pauseReason lastTransition=$lastTransition',
    'timeline (bounded, internal codes only):',
    ...diagnosticEvents,
    'physicalAccuracy=NOT_VERIFIED',
  ].join('\n');

  Future<void> close() {
    if (_shutdown case final pending?) return pending;
    _alive = false;
    _event('disposed');
    _freshnessTimer.cancel();
    _revision++;
    _allowMotion = false;
    sensors.removeListener(_sensorStateChanged);
    return _shutdown = () async {
      await _observationSubscription.cancel();
      await sensors.close();
      sensors.dispose();
      position.dispose();
    }();
  }

  @override
  void dispose() {
    unawaited(close().catchError((Object _) {}));
    super.dispose();
  }
}
