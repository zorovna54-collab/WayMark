import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import 'dart:async';

import '../../services/navigation_history_service.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/map_ui_theme.dart';
import '../../models/route_models.dart';
import '../../services/waymark_api_service.dart';
import '../route/floor_route_map.dart';
import '../scanner/scanner_page.dart';
import 'manual_navigation.dart';
import 'reroute_navigation.dart';
import '../route/demo_floor_plan.dart';
import 'local_map_navigation.dart';
import '../../services/map_draft_api_service.dart';
import '../indoor_tracking/indoor_tracking_controller.dart';
import '../indoor_tracking/map_readiness.dart';
import '../indoor_tracking/published_live_preflight.dart';
import '../indoor_tracking/debug/pilot_evidence.dart';
import '../indoor_tracking/debug/pilot_evidence_panel.dart';
import '../indoor_tracking/indoor_position.dart';
import '../indoor_tracking/tracking_graph.dart';
import '../indoor_tracking/live_tracking_panel.dart';
import '../indoor_tracking/sensors/sensor_provider.dart';

class NavigationPage extends StatefulWidget {
  const NavigationPage({
    super.key,
    required this.route,
    this.api,
    this.onRouteChanged,
    this.destinationRoom,
    this.localMap,
    this.historyService,
    this.localLivePilot = false,
    this.liveSensorProvider,
  });
  final WayMarkRoute route;
  final WayMarkApiService? api;
  final ValueChanged<WayMarkRoute>? onRouteChanged;
  final VerifiedDemoRoom? destinationRoom;
  final LocalMapNavigation? localMap;
  final NavigationHistoryService? historyService;
  final bool localLivePilot;
  final SensorProvider? liveSensorProvider;

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  late ManualNavigation _navigation = ManualNavigation(
    widget.route,
    localPreview: widget.localMap?.owns(widget.route) == true,
    allowLocalQr: widget.localMap?.resolvePublishedQr != null,
  );
  late final WayMarkApiService _defaultApi = WayMarkApiService();
  bool _scanningLocation = false;
  String? _qrFeedback;
  late final NavigationHistorySession _history;
  bool _closing = false, _allowPop = false;
  IndoorTrackingController? _live;
  bool _enablingLive = false;
  String? _liveIssue;
  MapReadinessReport? _liveReadiness;
  PilotEvidenceSession? _pilotEvidence;

  MapReadinessReport _checkPublished(
    LocalMapNavigation map,
    WayMarkRoute route,
    TrackingGraph? graph,
  ) => MapReadinessValidator.evaluate(
    MapReadinessInput.fromNavigation(map, route),
    graph: graph,
    requireGraph: true,
  );

  Future<void> _enableLive() async {
    final map = widget.localMap;
    if (map == null || _enablingLive || _live != null) return;
    final route = _navigation.route;
    setState(() {
      _enablingLive = true;
      _liveIssue = null;
    });
    try {
      TrackingGraph? graph;
      try {
        graph = await TrackingGraph.fromNavigation(
          map,
          allowLocalPilot: widget.localLivePilot,
        );
      } on FormatException {
        if (map.publication == null) rethrow;
      }
      if (!mounted ||
          widget.localMap != map ||
          !identical(route, _navigation.route)) {
        return;
      }
      if (map.publication != null) {
        final report = _checkPublished(map, route, graph);
        setState(() => _liveReadiness = report);
        if (!report.canStartLive) return;
      }
      if (graph == null) return;
      late final IndoorTrackingController controller;
      controller = IndoorTrackingController(
        graph: graph,
        map: map,
        route: route,
        provider: widget.liveSensorProvider ?? createSensorProvider(),
        onConfirmedOffRoute: (anchor) async {
          if (!mounted ||
              !identical(_live, controller) ||
              controller.position.value?.nodeId != anchor.nodeId) {
            return;
          }
          final next = map.rerouteFromStable(
            anchor.floorKey,
            anchor.nodeId,
            _navigation.route,
          );
          if (!mounted || !identical(_live, controller)) return;
          setState(() {
            _navigation = ManualNavigation(
              next,
              localPreview: true,
              allowLocalQr: map.resolvePublishedQr != null,
            );
            if (map.publication != null) {
              _liveReadiness = _checkPublished(map, next, controller.graph);
            }
            _qrFeedback = 'Tuyến mới từ mốc đã xác nhận; không tự hoàn tất theo bước chân.';
          });
          await controller.replaceRoute(next);
          widget.onRouteChanged?.call(next);
        },
      );
      setState(() {
        _live = controller;
        if (kDebugMode && const bool.fromEnvironment('WAYMARK_LIVE_TEST')) {
          _pilotEvidence?.dispose();
          _pilotEvidence = PilotEvidenceSession(
            mode: graph!.localPilot ? PilotMode.local : PilotMode.published,
          );
        }
      });
    } on Exception {
      if (mounted) {
        setState(
          () =>
              _liveIssue = 'Chưa mở được Live cho snapshot này. Giữ manual/QR.',
        );
      }
    } finally {
      if (mounted) setState(() => _enablingLive = false);
    }
  }

  Future<void> _disableLive() async {
    final controller = _live;
    final readiness = _liveReadiness;
    setState(() {
      _live = null;
      _liveReadiness = null;
    });
    if (controller == null) return;
    await controller.close();
    if (mounted) _pilotEvidence?.freezeClosedSession(controller, readiness);
    controller.dispose();
  }

  Future<void> _scanLiveLocation() async {
    final controller = _live;
    if (controller == null ||
        !controller.qr.available ||
        _scanningLocation ||
        controller.status == TrackingStatus.finished) {
      return;
    }
    setState(() => _scanningLocation = true);
    final ticket = await controller.beginRelocalization();
    try {
      if (!mounted || !identical(_live, controller)) return;
      final raw = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const ScannerPage.capture()),
      );
      if (!mounted || !identical(_live, controller)) return;
      if (raw == null) {
        controller.cancelRelocalization(ticket);
        return;
      }
      final accepted = await controller.completeRelocalization(raw, ticket);
      if (!mounted || !identical(_live, controller) || !accepted) return;
      final p = controller.position.value;
      final map = widget.localMap!;
      if (p?.nodeId != null) {
        final location = map.stableLocation(p!.floorKey, p.nodeId!, raw);
        final match = _navigation.inspectQr(location);
        // A real validated QR at the destination may confirm arrival. Steps
        // alone never call confirmNext or mark the route completed.
        if (match.indices.contains(_navigation.route.nodes.length - 1)) {
          setState(
            () => _navigation.acceptQr(
              match,
              selectedIndex: _navigation.route.nodes.length - 1,
              confirmedSelection: true,
            ),
          );
          if (_navigation.completed) await controller.finish();
        }
      }
    } finally {
      if (mounted) setState(() => _scanningLocation = false);
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    setState(() => _closing = true);
    try {
      await _live?.pause();
      if (!mounted) return;
      if (!_navigation.completed && _history.eligible) {
        final yes = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Hủy dẫn đường?'),
            content: const Text(
              'Phiên này sẽ được ghi Đã hủy; không coi là đã đến nơi.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Tiếp tục đi'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Hủy dẫn đường'),
              ),
            ],
          ),
        );
        if (yes != true) return;
      }
      await _live?.finish();
      await _history.finish(_navigation.completed ? 'Completed' : 'Cancelled');
      if (!mounted) return;
      if (_history.eligible && !_history.ended) {
        final leave = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Chưa đồng bộ lịch sử'),
            content: const Text(
              'Tuyến vẫn dùng được. Rời màn hình không đồng nghĩa lịch sử đã được lưu.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Ở lại / Thử lại'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Rời màn hình'),
              ),
            ],
          ),
        );
        if (leave != true || !mounted) return;
      }
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.maybePop(context);
      });
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _history =
        widget.localMap?.historySession ??
        NavigationHistorySession(
          widget.historyService ?? NavigationHistoryService(),
          widget.localMap,
          widget.route,
        );
    if (_navigation.isValid) unawaited(_history.start(widget.route));
  }

  @override
  void dispose() {
    _pilotEvidence?.dispose();
    _live?.dispose();
    // Abnormal disposal/background must not claim Completed. Explicit Finish
    // and system Back use the guarded close path below.
    super.dispose();
  }

  Future<void> _offerReroute(
    ManualNavigation state,
    WayMarkMapLocation location,
  ) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tính lại đường từ vị trí này'),
        content: Text(
          'QR không thuộc tuyến hiện tại. Tìm đường từ ${location.name} '
          'đến ${state.route.destination.name}? Bộ lọc tuyến được giữ nguyên.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('confirm-reroute'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Tính lại đường'),
          ),
        ],
      ),
    );
    if (!mounted || !identical(state, _navigation)) return;
    if (accepted != true) {
      setState(
        () =>
            _qrFeedback = 'Đã hủy tính lại đường. Tuyến và tiến độ giữ nguyên.',
      );
      return;
    }
    setState(
      () => _qrFeedback = 'Đang tính lại đường; vẫn giữ tuyến hiện tại...',
    );
    try {
      final replacement = await rerouteNavigation(
        state,
        location,
        widget.api ?? _defaultApi,
      );
      if (!mounted || !identical(state, _navigation)) return;
      setState(() {
        _navigation = replacement;
        _qrFeedback = 'Đã tải tuyến mới từ QR. Tiến độ bắt đầu lại tại node đã đối chiếu; không có định vị liên tục.';
      });
      widget.onRouteChanged?.call(replacement.route);
    } on WayMarkApiException catch (error) {
      if (mounted && identical(state, _navigation)) {
        setState(() => _qrFeedback = '$error Tuyến và tiến độ cũ giữ nguyên.');
      }
    }
  }

  Future<void> _scanLocation() async {
    if (_live != null) return _scanLiveLocation();
    if ((widget.localMap != null &&
            widget.localMap!.resolvePublishedQr == null) ||
        _scanningLocation ||
        !_navigation.isValid) {
      return;
    }
    final state = _navigation;
    setState(() {
      _scanningLocation = true;
      _qrFeedback = null;
    });
    try {
      final WayMarkMapLocation? location;
      final published = widget.localMap?.resolvePublishedQr;
      if (published != null) {
        final raw = await Navigator.push<String>(
          context,
          MaterialPageRoute(builder: (_) => const ScannerPage.capture()),
        );
        if (!mounted) return;
        if (raw == null) {
          setState(() => _qrFeedback = 'Đã hủy quét QR. Tiến độ giữ nguyên.');
          return;
        }
        location = await published(raw);
      } else {
        location = await Navigator.push<WayMarkMapLocation>(
          context,
          MaterialPageRoute<WayMarkMapLocation>(
            builder: (_) =>
                ScannerPage.verifyLocation(api: widget.api ?? _defaultApi),
          ),
        );
      }
      if (!mounted || !identical(state, _navigation)) return;
      if (location == null) {
        setState(
          () =>
              _qrFeedback = 'Chưa có QR hợp lệ được chọn. Tiến độ giữ nguyên.',
        );
        return;
      }
      final match = state.inspectQr(location);
      int? target;
      switch (match.kind) {
        case QrRouteMatchKind.offRoute:
          if (published != null) {
            final yes = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('QR ngoài tuyến • tính lại?'),
                content: Text(
                  'Bắt đầu lại từ ${location!.name} tới đích cũ trong cùng snapshot. Tuyến cũ giữ nguyên nếu hủy hoặc không có đường.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Hủy'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Tính lại tuyến'),
                  ),
                ],
              ),
            );
            if (yes == true && mounted && identical(state, _navigation)) {
              final route = widget.localMap!.rerouteFromLocation(
                location,
                state.route,
              );
              final replacement = ManualNavigation(
                route,
                localPreview: true,
                allowLocalQr: true,
              );
              replacement.acceptQr(replacement.inspectQr(location));
              setState(() {
                _navigation = replacement;
                _qrFeedback = 'Đã tính lại tuyến trên snapshot Published từ QR; không định vị liên tục.';
              });
              widget.onRouteChanged?.call(route);
            }
          } else {
            await _offerReroute(state, location);
          }
          return;
        case QrRouteMatchKind.past:
          setState(
            () => _qrFeedback = 'QR thuộc bước đã qua. Không tự lùi; hãy dùng Bước trước nếu cần.',
          );
          return;
        case QrRouteMatchKind.unmapped:
        case QrRouteMatchKind.invalidRoute:
          setState(
            () => _qrFeedback = 'QR chưa liên kết node/tầng hợp lệ hoặc tuyến không hợp lệ. Tiến độ giữ nguyên.',
          );
          return;
        case QrRouteMatchKind.ambiguous:
          target = await showDialog<int>(
            context: context,
            builder: (dialogContext) => SimpleDialog(
              title: const Text('Node xuất hiện nhiều lần trên tuyến'),
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'QR không xác định được lần xuất hiện. Hãy chọn bước bạn muốn đối chiếu; không có lựa chọn mặc định.',
                  ),
                ),
                for (final index in match.indices)
                  SimpleDialogOption(
                    key: ValueKey('qr-occurrence-$index'),
                    onPressed: index < state.nodeIndex
                        ? null
                        : () => Navigator.pop(dialogContext, index),
                    child: Text(
                      'Bước ${index + 1}: ${state.route.nodes[index].name} • ${state.route.nodes[index].floor.name}'
                      '${index < state.nodeIndex
                          ? ' (đã qua — không chọn)'
                          : index == state.nodeIndex
                          ? ' (giữ bước hiện tại)'
                          : ''}',
                    ),
                  ),
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Hủy'),
                ),
              ],
            ),
          );
        case QrRouteMatchKind.current:
        case QrRouteMatchKind.next:
        case QrRouteMatchKind.later:
          target = match.indices.single;
      }
      if (!mounted || !identical(state, _navigation)) return;
      final targetIndex = target;
      if (targetIndex == null) {
        setState(() => _qrFeedback = 'Đã hủy chọn bước. Tiến độ giữ nguyên.');
        return;
      }
      if (targetIndex > state.nodeIndex + 1) {
        final accepted = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Chuyển tới bước ${targetIndex + 1}?'),
            content: Text(
              'QR liên kết với ${state.route.nodes[targetIndex].name} • ${state.route.nodes[targetIndex].floor.name}. '
              'Các bước ở giữa chưa được xác nhận. QR này không chứng minh bạn đã đi theo các chặng đó.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Xác nhận chuyển bước'),
              ),
            ],
          ),
        );
        if (!mounted || !identical(state, _navigation)) return;
        if (accepted != true) {
          setState(
            () => _qrFeedback = 'Đã hủy chuyển bước. Tiến độ giữ nguyên.',
          );
          return;
        }
      }
      final previousIndex = state.nodeIndex;
      final selected = targetIndex;
      setState(() {
        final applied = state.acceptQr(
          match,
          selectedIndex: selected,
          confirmedSelection: true,
        );
        _qrFeedback = applied
            ? 'QR khớp bước ${state.nodeIndex + 1}: ${state.currentNode!.name} • ${state.currentNode!.floor.name}. '
                  '${previousIndex == state.nodeIndex ? 'Đã ở đúng bước đang chọn; tiến độ giữ nguyên.' : 'Đã cập nhật bước theo QR.'}'
            : 'Không thể áp dụng kết quả QR vào trạng thái hiện tại. Tiến độ giữ nguyên.';
      });
    } on MapDraftApiException catch (e) {
      if (mounted) setState(() => _qrFeedback = '$e Tiến độ giữ nguyên.');
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => _qrFeedback = '${e.message} Tiến độ giữ nguyên.');
      }
    } on Exception {
      if (mounted) {
        setState(
          () => _qrFeedback =
              'Không thể xác minh QR. Tiến độ giữ nguyên; hãy thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _scanningLocation = false);
    }
  }

  @override
  void didUpdateWidget(covariant NavigationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route != widget.route ||
        oldWidget.localMap != widget.localMap) {
      if (oldWidget.localMap != widget.localMap) {
        _liveReadiness = null;
        _live?.dispose();
        _live = null;
      } else {
        if (_live != null && widget.localMap?.publication != null) {
          _liveReadiness = _checkPublished(
            widget.localMap!,
            widget.route,
            _live!.graph,
          );
          if (!_liveReadiness!.canStartLive) {
            _live?.dispose();
            _live = null;
            if (!widget.localMap!.owns(widget.route)) {
              _liveIssue = 'Tuyến mới không thuộc snapshot đang dùng. Giữ tuyến thủ công trước đó; mở lại hành trình từ QR phù hợp.';
              return;
            }
          }
        }
        unawaited(_live?.replaceRoute(widget.route) ?? Future<void>.value());
      }
      _navigation = ManualNavigation(
        widget.route,
        localPreview: widget.localMap?.owns(widget.route) == true,
        allowLocalQr: widget.localMap?.resolvePublishedQr != null,
      );
      _qrFeedback = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _navigation;
    final currentNode = state.currentNode;
    final currentLandmarkNote = currentNode == null
        ? null
        : widget.localMap?.landmarkNoteForNode(
            currentNode.id,
            currentNode.floor.id,
          );
    final currentEdge = state.currentEdge;
    final nextNode = currentEdge == null
        ? null
        : state.route.nodes[currentEdge.sequence];
    final nextLandmarkNote = nextNode == null
        ? null
        : widget.localMap?.landmarkNoteForNode(nextNode.id, nextNode.floor.id);
    return mapUiTheme(
      context,
      PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_close());
        },
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.card,
            foregroundColor: AppColors.primary,
            title: Text(
              widget.localMap == null
                  ? 'Dẫn đường từng bước'
                  : widget.localMap!.publication == null
                  ? 'Xem trước bản đồ'
                  : 'Dẫn đường • Published',
            ),
            actions: [
              TextButton(
                onPressed: _closing ? null : _close,
                child: Text(_closing ? 'Đang lưu...' : 'Kết thúc'),
              ),
            ],
          ),
          body: SafeArea(
            child:
                widget.localMap != null && !widget.localMap!.owns(state.route)
                ? const Center(
                    child: Text('Tuyến không thuộc bản đồ cục bộ này.'),
                  )
                : !state.isValid
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        state.issue!,
                        textAlign: TextAlign.center,
                        key: const Key('navigation-error'),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Xuất phát: ${state.route.start.name} • ${state.route.nodes.first.floor.name}\nĐích: ${state.route.destination.name} • ${state.route.nodes.last.floor.name}',
                                key: const Key('navigation-route-endpoints'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              Card(
                                color: AppColors.primary,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (state.completed)
                                        Text(
                                          state.skippedUnconfirmedSteps > 0
                                              ? 'Đã chọn điểm cuối • còn chặng chưa xác nhận'
                                              : 'Đã xác nhận điểm đến',
                                          key: const Key(
                                            'mobile-arrival-summary',
                                          ),
                                          style: const TextStyle(
                                            color: AppColors.accent,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      Text(
                                        'Node đang chọn: ${state.currentNode!.name}',
                                        key: const Key(
                                          'navigation-current-node',
                                        ),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Bước ${state.nodeIndex + 1}/${state.route.nodes.length}',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                      Text(
                                        'Tầng của bước hiện tại: ${state.currentNode!.floor.name}',
                                        key: const Key(
                                          'navigation-current-floor',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                      if (currentLandmarkNote != null)
                                        Text(
                                          'Mốc nhận biết: $currentLandmarkNote',
                                          key: const Key(
                                            'navigation-current-landmark-note',
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      if (currentLandmarkNote != null)
                                        Text(
                                          'Mốc tại: ${currentNode!.floor.name}',
                                          key: const Key(
                                            'navigation-current-landmark-floor',
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                      if (state.currentEdge case final edge?)
                                        Text(
                                          '${navigationEdgeLabel(edge.edgeType)} → ${state.route.nodes[edge.sequence].name} • ${state.route.nodes[edge.sequence].floor.name} • ${formatMeters(edge.distanceMeters)}',
                                          key: const Key(
                                            'mobile-next-instruction',
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      if (nextLandmarkNote != null)
                                        Text(
                                          'Mốc nhận biết điểm kế tiếp: $nextLandmarkNote',
                                          key: const Key(
                                            'navigation-next-landmark-note',
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      if (nextLandmarkNote != null)
                                        Text(
                                          'Mốc kế tiếp tại: ${nextNode!.floor.name}',
                                          key: const Key(
                                            'navigation-next-landmark-floor',
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              if (widget.localMap != null &&
                                  (widget.localMap!.publication != null ||
                                      widget.localLivePilot) &&
                                  _live == null) ...[
                                OutlinedButton.icon(
                                  key: const Key('enable-live-navigation'),
                                  onPressed: _enablingLive ? null : _enableLive,
                                  icon: const Icon(Icons.directions_walk),
                                  label: Text(
                                    _enablingLive ? 'Đang mở Live…' : 'Live Navigation • thử nghiệm (opt-in)',
                                  ),
                                ),
                                if (_liveIssue != null) Text(_liveIssue!),
                                if (_liveReadiness != null)
                                  PublishedLivePreflight(
                                    report: _liveReadiness!,
                                    onManual: _disableLive,
                                  ),
                              ],
                              FloorRouteMap(
                                tracking: _live,
                                localMap: widget.localMap,
                                route: _navigation.route,
                                api: widget.api ?? _defaultApi,
                                compact: true,
                                activeNodeIndex: state.nodeIndex,
                                verifiedNodeIndex: state.lastVerifiedNodeIndex,
                                activeIsManual:
                                    state.currentConfirmation ==
                                    NavigationConfirmation.manual,
                                activeNodeStatus:
                                    state.currentConfirmation ==
                                        NavigationConfirmation.qr
                                    ? 'Vòng nét đứt: node đã đối chiếu QR tại thời điểm quét.'
                                    : state.currentConfirmation ==
                                          NavigationConfirmation.manual
                                    ? 'Ô vàng: node đang chọn theo xác nhận thủ công.'
                                    : widget.localMap != null
                                    ? 'Viền cyan: node đang chọn; chưa xác minh vị trí thực.'
                                    : 'Viền cyan: node đang chọn; chưa xác minh QR.',
                              ),
                              if (_live != null)
                                LiveTrackingPanel(
                                  controller: _live!,
                                  readiness: _liveReadiness,
                                  pilotEvidence: _pilotEvidence,
                                  onScan: _scanLiveLocation,
                                  onManual: _disableLive,
                                ),
                              if (_live == null &&
                                  _pilotEvidence != null &&
                                  kDebugMode &&
                                  const bool.fromEnvironment(
                                    'WAYMARK_LIVE_TEST',
                                  ))
                                ExpansionTile(
                                  title: const Text(
                                    'Pilot report • phiên Live vừa đóng',
                                  ),
                                  children: [
                                    PilotEvidencePanel(
                                      mode: _pilotEvidence!.mode,
                                      session: _pilotEvidence,
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 12),
                              Text(
                                widget.localMap != null &&
                                        widget.localMap!.publication == null
                                    ? 'Bản đồ cục bộ: chỉ tiến bước khi bạn xác nhận. Chưa xác minh vị trí thực hoặc lối đi. Không có định vị GPS trong nhà.'
                                    : 'Xác nhận thủ công hoặc đối chiếu QR tại một thời điểm. QR không chứng minh vị trí liên tục hoặc việc đã đi đúng đường. Không có định vị GPS trong nhà.',
                                key: const Key('manual-navigation-notice'),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                widget.destinationRoom?.room.name ??
                                    _navigation.route.destination.name,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                              Text(
                                'Tổng khoảng cách tuyến: ${formatMeters(_navigation.route.totalDistanceMeters)}',
                              ),
                              ValueListenableBuilder<String>(
                                valueListenable: _history.message,
                                builder: (_, message, _) => Text(
                                  message,
                                  key: const Key('navigation-history-status'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (state.completed)
                                Card(
                                  color: AppColors.secondary,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      children: [
                                        const Icon(
                                          Icons.check_circle_outline,
                                          color: AppColors.accent,
                                          size: 48,
                                        ),
                                        Text(
                                          state.skippedUnconfirmedSteps > 0
                                              ? 'Đã chọn điểm cuối tuyến'
                                              : 'Đã xác nhận hoàn tất tuyến',
                                          key: const Key('navigation-complete'),
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'Điểm cuối: ${state.currentNode!.name}',
                                        ),
                                        const Text(
                                          'Đây là xác nhận của bạn, chưa phải kết quả định vị.',
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              Text(
                                state.currentConfirmation ==
                                        NavigationConfirmation.qr
                                    ? 'Nguồn xác nhận tại bước này: QR ${state.currentQr!.wayMarkCode} (node ID và tầng đã khớp).'
                                    : state.currentConfirmation ==
                                          NavigationConfirmation.manual
                                    ? 'Nguồn xác nhận tại bước này: thủ công — chưa xác minh bằng QR.'
                                    : 'Chưa có xác minh QR cho bước đang chọn.',
                                key: const Key(
                                  'navigation-confirmation-source',
                                ),
                              ),
                              if (_qrFeedback != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    _qrFeedback!,
                                    key: const Key('navigation-qr-feedback'),
                                  ),
                                ),
                              if (state.skippedUnconfirmedSteps > 0)
                                Text(
                                  '${state.skippedUnconfirmedSteps} bước trung gian chưa được xác nhận; không coi là đã đi qua.',
                                  key: const Key(
                                    'navigation-unconfirmed-steps',
                                  ),
                                ),
                              if (state.currentEdge case final edge?)
                                _leg('Chặng hiện tại', edge),
                              if (state.followingEdge case final edge?)
                                _leg('Chặng tiếp theo', edge),
                              if (!state.completed &&
                                  _navigation.route.edges.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'Tuyến chỉ có một node. Hãy tự kiểm tra điểm này rồi xác nhận hoàn tất.',
                                  ),
                                ),
                              const SizedBox(height: 12),
                              LinearProgressIndicator(
                                value: state.progress,
                                key: const Key('navigation-progress'),
                                color: AppColors.accent,
                                backgroundColor: AppColors.secondary,
                                minHeight: 8,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _progressLabel(state),
                                key: const Key('navigation-progress-label'),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * .35,
                        ),
                        child: SingleChildScrollView(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(
                              color: AppColors.card,
                              border: Border(
                                top: BorderSide(color: AppColors.border),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.localMap == null ||
                                    widget.localMap!.resolvePublishedQr != null)
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: _scanningLocation
                                          ? null
                                          : _scanLocation,
                                      icon: const Icon(Icons.qr_code_scanner),
                                      label: const Text(
                                        'Quét QR xác nhận vị trí',
                                      ),
                                    ),
                                  ),
                                if (widget.localMap != null)
                                  Text(
                                    widget.localMap!.publication == null
                                        ? 'Xem trước bản đồ • xác nhận thủ công, chưa có QR local / định vị. Không xác nhận an toàn xe lăn.'
                                        : '${widget.localMap!.personalPublication ? 'Cá nhân/demo — không đại diện cơ sở • ' : ''}Snapshot Published v${widget.localMap!.publication!.version} • QR chỉ xác nhận tại thời điểm quét; lối đi/xe lăn chưa xác minh.',
                                    key: const Key('local-navigation-banner'),
                                  ),
                                const SizedBox(height: 8),
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    OutlinedButton(
                                      onPressed:
                                          state.canGoBack &&
                                              !_scanningLocation &&
                                              _live == null
                                          ? () => setState(() {
                                              state.previous();
                                              _qrFeedback = null;
                                            })
                                          : null,
                                      child: const Text('Bước trước'),
                                    ),
                                    const SizedBox(height: 8),
                                    ElevatedButton(
                                      key: const Key('navigation-confirm'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(0, 52),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                        ),
                                      ),
                                      onPressed:
                                          state.completed ||
                                              _scanningLocation ||
                                              _live != null
                                          ? null
                                          : () => setState(() {
                                              state.confirmNext();
                                              _qrFeedback = null;
                                            }),
                                      child: Text(
                                        _navigation.route.edges.isEmpty
                                            ? 'Xác nhận hoàn tất tại điểm này'
                                            : 'Đã đến điểm tiếp theo',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  String _progressLabel(ManualNavigation state) {
    if (state.route.edges.isEmpty) {
      if (state.completed) return 'Đã xác nhận điểm duy nhất (thủ công)';
      return state.currentConfirmation == NavigationConfirmation.qr
          ? 'Điểm duy nhất đã đối chiếu QR; chưa xác nhận hoàn tất.'
          : 'Chưa xác nhận điểm duy nhất';
    }
    if (state.skippedUnconfirmedSteps > 0) {
      return 'Tiến độ chọn bước: ${state.nodeIndex}/${state.route.edges.length} chặng (còn bước chưa xác nhận)';
    }
    return state.hasQrConfirmations
        ? 'Tiến độ chọn bước: ${state.nodeIndex}/${state.route.edges.length} chặng (có xác minh QR)'
        : 'Đã xác nhận ${state.nodeIndex}/${state.route.edges.length} chặng (thủ công)';
  }

  Widget _leg(String title, RouteEdge edge) {
    final from = _navigation.route.nodes[edge.sequence - 1];
    final to = _navigation.route.nodes[edge.sequence];
    final changesFloor = from.floor.id != to.floor.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text('${from.name} → ${to.name}'),
            Text(
              '${navigationEdgeLabel(edge.edgeType)} • ${formatMeters(edge.distanceMeters)}',
            ),
            Text(
              changesFloor
                  ? 'Chuyển tầng: ${from.floor.name} → ${to.floor.name}'
                  : 'Tầng: ${from.floor.name}',
            ),
            if (changesFloor)
              Text('Điểm chuyển tầng: ${from.name} → ${to.name}'),
          ],
        ),
      ),
    );
  }
}
