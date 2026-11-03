import 'package:flutter/material.dart';

import '../auth/workflow_recovery.dart';

import '../../services/auth_session.dart';
import '../../services/navigation_history_service.dart';
import '../route/route_preview_page.dart';
import '../search/local_map_search_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, this.service, this.compact = false});
  final NavigationHistoryService? service;
  final bool compact;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late final _service = widget.service ?? NavigationHistoryService();
  List<Map<String, dynamic>> _items = [];
  bool _busy = false;
  String? _error, _loadedToken;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    NavigationHistoryService.changes.addListener(_refresh);
    AuthSession.changes.addListener(_refresh);
    _load();
  }

  void _refresh() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    NavigationHistoryService.changes.removeListener(_refresh);
    AuthSession.changes.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _items = [];
      _loadedToken = AuthSession.accessToken;
    });
    try {
      if (AuthSession.accessToken == null) return;
      final items = await _service.list();
      if (mounted &&
          generation == _generation &&
          _loadedToken == AuthSession.accessToken) {
        setState(() => _items = items);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = 'Không tải được lịch sử riêng tư. Kiểm tra đăng nhập, mạng hoặc schema History chưa triển khai.',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final revision = AuthSession.revision;
    final token = AuthSession.accessToken;
    final yes = await showSessionDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xóa hành trình này?'),
        content: const Text(
          'Xóa lịch sử của bạn trên server; không xóa bản đồ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || !AuthSession.isCurrent(token, revision)) {
      return;
    }
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      await _service.delete(item['id'] as String);
      if (mounted && generation == _generation) await _load();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Chưa xóa được lịch sử. Vui lòng thử lại.');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _resume(Map<String, dynamic> item) async {
    final revision = AuthSession.revision;
    final token = AuthSession.accessToken;
    final yes = await showSessionDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Tính tuyến mới từ QR cũ?'),
        content: Text(
          'Lịch sử không xác định vị trí hiện tại. Chỉ tiếp tục nếu bạn đang ở ${item['startName']}; nếu không, quay lại quét QR tại chỗ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Đúng vị trí bắt đầu'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || !AuthSession.isCurrent(token, revision)) {
      return;
    }
    final generation = ++_generation;
    bool current() =>
        mounted &&
        generation == _generation &&
        AuthSession.isCurrent(token, revision);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _service.request(
        '/${item['id']}/resume',
      ) as Map<String, dynamic>;
      if (!current()) return;
      final session = await _service.maps.loadQr(r['payload'] as String);
      if (!current()) return;
      if (r['destinationNodeId'] == null || r['destinationFloorKey'] == null) {
        if (!mounted || !current()) return;
        recordPublishedScan(session, service: _service);
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => LocalMapSearchPage(
              map: session.map,
              destinationFloors: session.project.floors,
              initialStart: session.startKey,
            ),
          ),
        );
        return;
      }
      final target = session.map.routeIdentity(
        r['destinationFloorKey'] as String,
        r['destinationNodeId'] as String,
      );
      final rooms = session.map.rooms
          .where(
            (room) =>
                room.floorId == target.floorId &&
                room.entrances.contains(r['destinationNodeId']),
          )
          .toList();
      final directNode = session.map.destinationNodes.any(
        (node) =>
            node.nodeId == target.nodeId && node.floorId == target.floorId,
      );
      if (!directNode && rooms.length != 1) {
        throw const FormatException(
          'Không xác định duy nhất phòng từ cửa trong lịch sử. Hãy chọn lại đích từ Search.',
        );
      }
      if (!mounted || !current()) return;
      recordPublishedScan(session, service: _service);
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => !directNode
              ? RoutePreviewPage.local(
                  map: session.map,
                  startNodeCode: session.startKey,
                  placeId: rooms.single.id,
                )
              : RoutePreviewPage.localNode(
                  map: session.map,
                  startNodeCode: session.startKey,
                  destinationNodeId: target.nodeId,
                  destinationFloorId: target.floorId,
                  destinationName: item['destinationName'] as String,
                ),
        ),
      );
      if (current()) await _load();
    } catch (_) {
      if (current()) {
        setState(
          () => _error = 'Không thể dẫn đường lại: QR đã thu hồi, map/node không còn hợp lệ hoặc mất kết nối.',
        );
      }
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sameSession =
        _loadedToken != null && _loadedToken == AuthSession.accessToken;
    final content = ListView(
      shrinkWrap: widget.compact,
      physics: widget.compact ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(16),
      children: [
        if (!widget.compact)
          const Text(
            '100 phiên gần nhất • riêng tư theo tài khoản • ghi từ lần resolve QR thành công.',
          ),
        if (_busy) const LinearProgressIndicator(),
        if (!sameSession)
          const Text(
            'Guest không lưu lịch sử tài khoản. Đăng nhập để xem lịch sử riêng của bạn.',
          ),
        if (_error != null) ...[
          Text(_error!, key: const Key('history-error')),
          TextButton(
            onPressed: _busy ? null : _load,
            child: const Text('Thử lại lịch sử'),
          ),
        ],
        if (sameSession && !_busy && _error == null && _items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Chưa có phiên nào. Quét QR Published hợp lệ để bắt đầu lịch sử.',
            ),
          ),
        if (sameSession)
          for (final item in _items.take(widget.compact ? 3 : 100))
            Card(
              child: InkWell(
                onTap: () => _detail(item),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['mapName'] as String,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${item['startName']} → ${(item['destinationName'] as String?)?.isNotEmpty == true ? item['destinationName'] : 'Chưa chọn điểm đến'}',
                      ),
                      Text(
                        '${DateTime.parse((item['scannedAtUtc'] ?? item['startedAtUtc']) as String).toLocal()} • ${historyStatusLabel(item['status'])}',
                      ),
                      if (item['distanceMeters'] != null)
                        Text('${item['distanceMeters']} m • theo graph'),
                      if (!widget.compact)
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: _busy ? null : () => _resume(item),
                              icon: const Icon(Icons.navigation_outlined),
                              label: const Text('Tính tuyến mới'),
                            ),
                            TextButton.icon(
                              onPressed: _busy ? null : () => _delete(item),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Xóa mục'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
    if (widget.compact) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử di chuyển'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: content,
    );
  }

  Future<void> _detail(Map<String, dynamic> item) => showSessionDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(item['mapName'] as String),
      content: SingleChildScrollView(
        child: Text(
          'Xuất phát: ${item['startName']}\nĐích: ${item['destinationName'] ?? ''}\n${historyStatusLabel(item['status'])}\nPhiên bản: ${item['publishedVersion']}\nQuét: ${item['scannedAtUtc'] ?? item['startedAtUtc']}\nBắt đầu: ${item['navigationStartedAtUtc'] ?? 'Chưa bắt đầu'}\nKết thúc: ${item['endedAtUtc'] ?? 'Chưa kết thúc'}\nKhoảng cách: ${item['distanceMeters'] ?? 'Chưa có'}',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Đóng'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(c);
            _resume(item);
          },
          child: const Text('Tính tuyến mới'),
        ),
      ],
    ),
  );
}

String historyStatusLabel(dynamic status) => switch (status) {
  'Scanned' => 'Mới quét / chờ dẫn đường',
  'Completed' => 'Hoàn tất (xác nhận)',
  'Cancelled' => 'Đã hủy',
  _ => 'Đang đi / chưa cập nhật kết thúc',
};
