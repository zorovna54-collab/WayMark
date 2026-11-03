import 'package:flutter/material.dart';

import 'dart:async';

import '../../core/theme/app_colors.dart';
import '../admin/draft_map.dart';
import '../navigation/local_map_navigation.dart';
import '../route/route_preview_page.dart';

sealed class LocalDestinationSelection {
  const LocalDestinationSelection();
}

final class LocalRoomSelection extends LocalDestinationSelection {
  const LocalRoomSelection({required this.placeId, required this.floorId});

  final String placeId;
  final int floorId;
}

final class LocalNodeSelection extends LocalDestinationSelection {
  const LocalNodeSelection({
    required this.nodeId,
    required this.floorId,
    required this.nodeCode,
  });

  final int nodeId;
  final int floorId;
  final String nodeCode;
}

class LocalNodeDestination {
  const LocalNodeDestination({
    required this.selection,
    required this.name,
    required this.displayName,
    required this.floorName,
    this.badge = '',
  });

  final LocalNodeSelection selection;
  final String name;
  final String displayName;
  final String floorName;
  final String badge;
  String get title =>
      RegExp(
        r'^(LOCAL-|DRAFT-)|^[0-9a-f]{8}-[0-9a-f-]{27}$',
        caseSensitive: false,
      ).hasMatch(selection.nodeCode)
      ? displayName
      : '$displayName (${selection.nodeCode})';

  bool matches(String query) =>
      '$name $displayName ${selection.nodeCode} $badge'.toLowerCase().contains(
        query.trim().toLowerCase(),
      );
}

class LocalMapSearchPage extends StatefulWidget {
  const LocalMapSearchPage({
    super.key,
    required this.map,
    required this.destinationFloors,
    this.initialStart,
  });
  final LocalMapNavigation map;
  // Kept for existing callers; destination metadata comes only from map's
  // detached snapshot, never mutable/reordered editor floors.
  final List<DraftMap> destinationFloors;
  final String? initialStart;

  List<LocalNodeDestination> get searchableNodeDestinations {
    final destinations = [
      for (final n in map.destinationNodes)
        LocalNodeDestination(
          selection: LocalNodeSelection(
            nodeId: n.nodeId,
            floorId: n.floorId,
            nodeCode: n.nodeCode,
          ),
          name: n.name,
          displayName: n.displayName,
          floorName: n.floorName,
          badge: n.badge,
        ),
    ];
    return List.unmodifiable(destinations);
  }

  @override
  State<LocalMapSearchPage> createState() => _LocalMapSearchPageState();
}

class _LocalMapSearchPageState extends State<LocalMapSearchPage> {
  bool _allowPop = false, _closing = false;
  Future<void> _leave() async {
    if (_closing) return;
    _closing = true;
    try {
      final history = widget.map.historySession;
      await history?.finish('Cancelled');
      if (!mounted) return;
      if (history != null && history.eligible && !history.ended) {
        final leave = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Chưa đồng bộ lịch sử'),
            content: const Text(
              'Chưa lưu được trạng thái hủy. Bạn có thể ở lại để thử lại; rời màn hình không đồng nghĩa đã lưu.',
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
      _closing = false;
    }
  }

  String? _start;
  String _query = '';
  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_leave());
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.map.publication == null
              ? 'Xem trước bản đồ'
              : 'Chọn điểm đến • Published',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.map.publication == null
                  ? '${widget.map.multi ? 'Project nhiều tầng' : widget.map.floor.name} • bản sao cục bộ'
                  : '${widget.map.personalPublication ? 'Bản đồ cá nhân/demo — không đại diện cơ sở được ủy quyền • ' : ''}Snapshot công khai v${widget.map.publication!.version} • chưa xác minh lối đi thực tế',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              widget.initialStart == null
                  ? 'Chọn node xuất phát, rồi tìm Phòng hoặc Điểm đến đã được đánh dấu. Chưa xác minh vị trí thực, lối đi hoặc an toàn xe lăn.'
                  : 'Điểm xuất phát đã được đối chiếu QR. Chọn điểm đến bên dưới. Chưa xác minh lối đi hoặc an toàn xe lăn.',
            ),
            const SizedBox(height: 16),
            if (widget.map.historySession case final history?) ...[
              ValueListenableBuilder<String>(
                valueListenable: history.message,
                builder: (_, message, _) =>
                    Text(message, key: const Key('search-history-status')),
              ),
              TextButton(
                onPressed: history.scanned,
                child: const Text('Thử lại lưu lần quét'),
              ),
            ],
            DropdownButtonFormField<String>(
              key: const Key('local-start-node'),
              initialValue: _start,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Điểm bắt đầu'),
              items: [
                for (final n in widget.map.startChoices)
                  DropdownMenuItem(
                    value: n.key,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(n.label, overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        Text(n.badge),
                      ],
                    ),
                  ),
              ],
              onChanged: widget.initialStart != null
                  ? null
                  : (value) => setState(() => _start = value),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Tìm phòng / điểm đến',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            if (_start == null)
              const Text('Chọn điểm bắt đầu để xem tuyến tới đích.'),
            if (!widget.map.searchableRooms.any((r) => r.matches(_query)) &&
                !widget.searchableNodeDestinations.any(
                  (n) => n.matches(_query),
                ))
              const Text('Không tìm thấy phòng hoặc điểm đến phù hợp.'),
            for (final room in widget.map.searchableRooms.where(
              (r) => r.matches(_query),
            ))
              Card(
                child: ListTile(
                  key: ValueKey('local-room-${room.id}'),
                  leading: const Icon(
                    Icons.meeting_room_outlined,
                    color: AppColors.accent,
                  ),
                  title: Text('${room.name} (${room.code})'),
                  subtitle: Text(
                    'Phòng • ${widget.map.graphFor(room.floorId).floor.name} • ${room.entrances.length} cửa hợp lệ • chọn cửa có tuyến ngắn nhất',
                  ),
                  enabled: _start != null,
                  onTap: _start == null
                      ? null
                      : () {
                          final destination = LocalRoomSelection(
                            placeId: room.id,
                            floorId: room.floorId,
                          );
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => RoutePreviewPage.local(
                                map: widget.map,
                                startNodeCode: _start!,
                                placeId: destination.placeId,
                              ),
                            ),
                          );
                        },
                ),
              ),
            for (final destination in widget.searchableNodeDestinations.where(
              (node) => node.matches(_query),
            ))
              Card(
                child: ListTile(
                  key: ValueKey(
                    'local-node-destination-${destination.selection.floorId}-${destination.selection.nodeId}',
                  ),
                  leading: const Icon(
                    Icons.place_outlined,
                    color: AppColors.accent,
                  ),
                  title: Text(destination.title),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Điểm đến • ${destination.floorName}'),
                      Text(destination.badge),
                    ],
                  ),
                  enabled: _start != null,
                  onTap: _start == null
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => RoutePreviewPage.localNode(
                                map: widget.map,
                                startNodeCode: _start!,
                                destinationNodeId: destination.selection.nodeId,
                                destinationFloorId:
                                    destination.selection.floorId,
                                destinationName: destination.displayName,
                              ),
                            ),
                          );
                        },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
