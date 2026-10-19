import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/map_ui_theme.dart';
import '../../models/route_models.dart';
import '../../services/waymark_api_service.dart';
import '../route/floor_route_map.dart';
import '../scanner/scanner_page.dart';
import 'manual_navigation.dart';
import 'reroute_navigation.dart';

class NavigationPage extends StatefulWidget {
  const NavigationPage({
    super.key,
    required this.route,
    this.api,
    this.onRouteChanged,
  });
  final WayMarkRoute route;
  final WayMarkApiService? api;
  final ValueChanged<WayMarkRoute>? onRouteChanged;

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  late ManualNavigation _navigation = ManualNavigation(widget.route);
  late final WayMarkApiService _defaultApi = WayMarkApiService();
  bool _scanningLocation = false;
  String? _qrFeedback;

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
    if (_scanningLocation || !_navigation.isValid) return;
    final state = _navigation;
    setState(() {
      _scanningLocation = true;
      _qrFeedback = null;
    });
    try {
      final location = await Navigator.push<WayMarkMapLocation>(
        context,
        MaterialPageRoute<WayMarkMapLocation>(
          builder: (_) =>
              ScannerPage.verifyLocation(api: widget.api ?? _defaultApi),
        ),
      );
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
          await _offerReroute(state, location);
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
    if (oldWidget.route != widget.route) {
      _navigation = ManualNavigation(widget.route);
      _qrFeedback = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _navigation;
    return mapUiTheme(
      context,
      Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.card,
          foregroundColor: AppColors.primary,
          title: const Text('Dẫn đường từng bước'),
          actions: [
            TextButton(
              onPressed: () => Navigator.maybePop(context),
              child: const Text('Kết thúc'),
            ),
          ],
        ),
        body: SafeArea(
          child: !state.isValid
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
                            Card(
                              color: AppColors.primary,
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Node đang chọn: ${state.currentNode!.name}',
                                      key: const Key('navigation-current-node'),
                                      style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Bước ${state.nodeIndex + 1}/${state.route.nodes.length} • ${state.currentNode!.nodeCode}',
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
                                  ],
                                ),
                              ),
                            ),
                            FloorRouteMap(
                              route: _navigation.route,
                              api: widget.api ?? _defaultApi,
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
                                  : 'Viền cyan: node đang chọn; chưa xác minh QR.',
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Xác nhận thủ công hoặc đối chiếu QR tại một thời điểm. QR không chứng minh vị trí liên tục hoặc việc đã đi đúng đường. Không có định vị GPS trong nhà.',
                              key: Key('manual-navigation-notice'),
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
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
                              key: const Key('navigation-confirmation-source'),
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
                                key: const Key('navigation-unconfirmed-steps'),
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
                    Container(
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
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _scanningLocation
                                  ? null
                                  : _scanLocation,
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Quét QR xác nhận vị trí'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              OutlinedButton(
                                onPressed: state.canGoBack && !_scanningLocation
                                    ? () => setState(() {
                                        state.previous();
                                        _qrFeedback = null;
                                      })
                                    : null,
                                child: const Text('Bước trước'),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  key: const Key('navigation-confirm'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(0, 52),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  onPressed:
                                      state.completed || _scanningLocation
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
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
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
