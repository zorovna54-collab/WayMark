import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/map_ui_theme.dart';
import '../../models/route_models.dart' show formatMeters;
import '../../services/waymark_api_service.dart';
import '../route/floor_plan_canvas.dart';
import 'admin_page_shell.dart';
import 'draft_file_gateway.dart';
import 'draft_map.dart';
import 'floor_plan_asset.dart';

class DraftMapEditor extends StatefulWidget {
  const DraftMapEditor({super.key, this.api, this.files});
  final WayMarkApiService? api;
  final DraftFileGateway? files;
  @override
  State<DraftMapEditor> createState() => _DraftMapEditorState();
}

class _DraftMapEditorState extends State<DraftMapEditor> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final _api = widget.api ?? WayMarkApiService();
  late final _files = widget.files ?? const PlatformDraftFiles();
  final _canvasAnchor = GlobalKey();
  List<Map<String, dynamic>> _sites = [], _buildings = [], _floors = [];
  int? _site, _building, _floor;
  DraftMap? _draft;
  String? _selected, _message;
  DraftEdge? _selectedEdge;
  String? _dragNode, _routeStart, _routeEnd, _operation;
  Offset? _dragPoint;
  bool _preview = false, _messageError = false;
  DraftRoute? _previewRoute;
  bool _busy = false, _dirty = false;
  String _tool = 'Chọn';
  @override
  void initState() {
    super.initState();
    _read(() async {
      _sites = await _api.getSites();
    });
  }

  void _notice(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageError = error;
    });
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Colors.red.shade800 : AppColors.primary,
        ),
      );
  }

  Future<void> _read(Future<void> Function() task, {String? operation}) async {
    setState(() {
      _busy = true;
      _message = null;
      _messageError = false;
      _operation = operation;
    });
    try {
      await task();
    } catch (error) {
      if (mounted) {
        final message =
            error is WayMarkApiException ||
                error is FormatException ||
                error is UnsupportedError
            ? error.toString()
            : 'Không thể xử lý bản nháp. Bản đồ đang giữ nguyên nếu chưa tải xong.';
        _notice(message, error: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _operation = null;
        });
      }
    }
  }

  Future<bool> _discard() async =>
      !_dirty ||
      await showDialog<bool>(
            context: context,
            builder: (dialog) => AlertDialog(
              title: const Text('Rời bản nháp chưa xuất?'),
              content: const Text(
                'Thay đổi chỉ nằm trong bộ nhớ. Hãy xuất file nếu cần giữ lại.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('Giữ lại'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: const Text('Rời bản nháp'),
                ),
              ],
            ),
          ) ==
          true;

  Future<void> _choose(String level, int value) async {
    if (!await _discard() || !mounted) return;
    await _read(() async {
      if (level == 'Site') {
        final buildings = await _api.getBuildings(value);
        if (buildings.any((b) => b['siteId'] != value)) {
          throw const FormatException('Building sai Site.');
        }
        if (!mounted) return;
        _site = value;
        _building = null;
        _floor = null;
        _buildings = buildings;
        _floors = [];
        _draft = null;
      } else if (level == 'Building') {
        final floors = await _api.getFloors(value);
        if (floors.any((f) => f['buildingId'] != value)) {
          throw const FormatException('Floor sai Building.');
        }
        if (!mounted) return;
        _building = value;
        _floor = null;
        _floors = floors;
        _draft = null;
      } else {
        final graph = await _api.getFloorGraph(value);
        if (graph.floor.buildingId != _building) {
          throw const FormatException('Floor không thuộc Building đã chọn.');
        }
        final draft = DraftMap(
          siteId: _site!,
          buildingId: _building!,
          floor: graph.floor,
        );
        for (final node in graph.nodes) {
          draft.putNode(
            DraftNode(
              node.nodeCode,
              node.name,
              node.x,
              node.y,
              node.nodeType,
              sourceNodeId: node.id,
            ),
          );
        }
        for (final edge in graph.edges.where((e) => e.isActive)) {
          final from = graph.nodes.singleWhere((n) => n.id == edge.fromNodeId);
          final to = graph.nodes.singleWhere((n) => n.id == edge.toNodeId);
          draft.addEdge(
            DraftEdge(
              from.nodeCode,
              to.nodeCode,
              edge.distanceMeters,
              edge.edgeType,
            ),
          );
        }
        if (!mounted) return;
        _floor = value;
        _draft = draft;
      }
      _selected = null;
      _selectedEdge = null;
      _preview = false;
      _previewRoute = null;
      _routeStart = _routeEnd = null;
      _dirty = false;
    });
  }

  Future<bool> _beforeNavigate() async {
    final accepted = await _discard();
    if (accepted && mounted) setState(() => _dirty = false);
    return accepted;
  }

  Future<void> _image() => _read(() async {
    final draft = _draft!;
    final file = await _files.pick('.png,.jpg,.jpeg', FloorPlanAsset.maxBytes);
    if (file == null) {
      _notice('Đã hủy chọn ảnh. Ảnh và graph cũ giữ nguyên.');
      return;
    }
    final image = await FloorPlanAsset.validate(
      file.bytes,
      file.name,
      file.mime,
    );
    if (!mounted || !identical(draft, _draft)) return;
    draft.image = image;
    _dirty = true;
    _preview = false;
    _previewRoute = null;
    _notice(
      'Đã tải ${image.name} • ${image.width} × ${image.height} px • ${draft.floor.name}. '
      'Ảnh đã được giải mã. Hãy đối chiếu lại graph với ảnh mới; chưa publish.',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _canvasAnchor.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(target, alignment: .15);
      }
    });
  }, operation: 'Đang đọc và giải mã ảnh PNG/JPG…');

  Future<void> _export() => _read(() async {
    final draft = _draft!;
    final bytes = draft.encode();
    if (bytes.length > DraftMap.maxFileBytes) {
      throw const FormatException(
        'Bản nháp vượt 18 MB. Hãy giảm kích thước ảnh/graph.',
      );
    }
    await _files.save(
      bytes,
      'waymark-floor-${draft.floor.id}-draft.json',
      'application/json',
    );
    _notice(
      'Đã yêu cầu tải bản nháp kèm toàn bộ ảnh (Base64). Kiểm tra file tải xuống; chưa publish.',
    );
  });

  Future<void> _import() async {
    if (!await _discard() || !mounted) return;
    await _read(() async {
      final previous = _draft!;
      final file = await _files.pick('.json', DraftMap.maxFileBytes);
      if (file == null) {
        _notice('Đã hủy mở bản nháp. Dữ liệu hiện tại giữ nguyên.');
        return;
      }
      final restored = await DraftMap.decode(
        file.bytes,
        siteId: _site!,
        buildingId: _building!,
        floor: previous.floor,
      );
      if (!mounted || !identical(previous, _draft)) return;
      _draft = restored;
      _selected = null;
      _selectedEdge = null;
      _preview = false;
      _previewRoute = null;
      _routeStart = _routeEnd = null;
      _dirty = true;
      _notice(
        'Đã khôi phục ảnh, node và cạnh của ${restored.floor.name}. '
        'Hãy đối chiếu lại trước khi preview; đây vẫn là bản nháp chưa publish.',
      );
    }, operation: 'Đang mở bản nháp và giải mã ảnh…');
  }

  void _edited() {
    _dirty = true;
    _previewRoute = null;
  }

  DraftNode? _nearNode(Offset point) {
    final nearby =
        _draft!.nodes
            .where((n) => (Offset(n.x, n.y) - point).distance < .045)
            .toList()
          ..sort(
            (a, b) => (Offset(a.x, a.y) - point).distance.compareTo(
              (Offset(b.x, b.y) - point).distance,
            ),
          );
    return nearby.firstOrNull;
  }

  bool _startDrag(Offset point) {
    if (_busy || _preview || !['Chọn', 'Di chuyển'].contains(_tool)) {
      return false;
    }
    final node = _nearNode(point);
    if (node == null) return false;
    setState(() {
      _selected = node.code;
      _selectedEdge = null;
      _dragNode = node.code;
      _dragPoint = Offset(node.x, node.y);
    });
    return true;
  }

  void _finishDrag() {
    final node = _draft!.nodes.where((n) => n.code == _dragNode).firstOrNull;
    final point = _dragPoint;
    setState(() {
      if (node != null && point != null && point != Offset(node.x, node.y)) {
        _draft!.putNode(node.at(point.dx, point.dy), replace: true);
        _edited();
      }
      _dragNode = null;
      _dragPoint = null;
    });
  }

  Future<void> _deleteNode(DraftNode node) async {
    final draft = _draft!;
    final count = draft.edges
        .where((e) => e.from == node.code || e.to == node.code)
        .length;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Xóa node khỏi bản nháp?'),
        content: Text(
          'Xóa ${node.name} và $count cạnh liên quan trong bản nháp cục bộ. Không xóa dữ liệu server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('confirm-delete-node'),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Xóa node nháp'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted && identical(draft, _draft)) {
      setState(() {
        draft.removeNode(node.code);
        _selected = null;
        _selectedEdge = null;
        _edited();
        _routeStart = _routeEnd = null;
      });
    }
  }

  void _tap(Offset point) {
    if (_preview || _busy) return;
    final draft = _draft!;
    if (_tool == 'Thêm node') {
      _nodeDialog(point);
      return;
    }
    final selected = draft.nodes.where((n) => n.code == _selected).firstOrNull;
    if (_tool == 'Di chuyển' && selected != null) {
      setState(() {
        draft.putNode(
          DraftNode(
            selected.code,
            selected.name,
            point.dx,
            point.dy,
            selected.type,
            wayMarkCode: selected.wayMarkCode,
            sourceNodeId: selected.sourceNodeId,
          ),
          replace: true,
        );
        _edited();
      });
      return;
    }
    final nearby = _nearNode(point);
    DraftEdge? hit;
    if (nearby == null) {
      final nodes = {for (final n in draft.nodes) n.code: n};
      for (final edge in draft.edges.reversed) {
        final a = Offset(nodes[edge.from]!.x, nodes[edge.from]!.y);
        final b = Offset(nodes[edge.to]!.x, nodes[edge.to]!.y);
        final delta = b - a;
        final t = delta.distanceSquared == 0
            ? 0.0
            : (((point - a).dx * delta.dx + (point - a).dy * delta.dy) /
                      delta.distanceSquared)
                  .clamp(0.0, 1.0);
        if ((point - (a + delta * t)).distance < .025) {
          hit = edge;
          break;
        }
      }
    }
    setState(() {
      _selected = nearby?.code;
      _selectedEdge = hit;
    });
  }

  Future<void> _nodeDialog(Offset point, {DraftNode? existing}) async {
    final code = TextEditingController(
      text:
          existing?.code ??
          'DRAFT-${_draft!.siteId}-${_draft!.buildingId}-${_draft!.floor.id}-',
    );
    final name = TextEditingController(text: existing?.name ?? '');
    final waymark = TextEditingController(text: existing?.wayMarkCode ?? '');
    var type = existing?.type ?? 'Junction';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            existing == null ? 'Thêm node bản nháp' : 'Thuộc tính node',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: code,
                  enabled: existing == null,
                  decoration: const InputDecoration(
                    labelText: 'NodeCode (namespace riêng)',
                  ),
                ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Tên node'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  items: [
                    for (final value in [
                      'Entrance',
                      'Junction',
                      'Destination',
                      'Elevator',
                      'Stairs',
                    ])
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: (value) => update(() => type = value!),
                  decoration: const InputDecoration(labelText: 'Loại node'),
                ),
                TextField(
                  controller: waymark,
                  decoration: const InputDecoration(
                    labelText: 'WayMarkCode (tùy chọn; kiểm tra API)',
                  ),
                ),
                Text(
                  'X: ${point.dx.toStringAsFixed(4)} / Y: ${point.dy.toStringAsFixed(4)}',
                ),
                const Text(
                  'Đây chỉ là đề xuất liên kết trong bản nháp, không ghi đè WayMark thật.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Lưu node nháp'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      await _read(() async {
        final draft = _draft!;
        final linkCode = waymark.text.trim();
        if (linkCode.isNotEmpty) {
          final location = await _api.getMapLocation(linkCode);
          if (location.node != null &&
              (location.node!.id != existing?.sourceNodeId ||
                  location.node!.floorId != draft.floor.id)) {
            throw const FormatException(
              'WayMark đã liên kết node khác trên bản đồ thật. Không ghi đè liên kết.',
            );
          }
        }
        if (!mounted) return;
        draft.putNode(
          DraftNode(
            code.text.trim(),
            name.text.trim(),
            point.dx,
            point.dy,
            type,
            wayMarkCode: linkCode.isEmpty ? null : linkCode,
            sourceNodeId: existing?.sourceNodeId,
          ),
          replace: existing != null,
        );
        _selected = code.text.trim();
        _edited();
      });
    }
    // Dialog routes may animate out after showDialog resolves.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    code.dispose();
    name.dispose();
    waymark.dispose();
  }

  Future<void> _edgeDialog({DraftEdge? existing}) async {
    final draft = _draft!;
    String? from = existing?.from ?? _selected, to = existing?.to;
    var type = existing?.type ?? 'Corridor';
    final meters = TextEditingController(
      text: existing?.meters.toString() ?? '',
    );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            existing == null ? 'Cạnh có hướng: từ → đến' : 'Sửa cạnh có hướng',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final field in ['Từ node', 'Đến node'])
                  DropdownButtonFormField<String>(
                    initialValue: field == 'Từ node' ? from : to,
                    decoration: InputDecoration(labelText: field),
                    items: [
                      for (final node in draft.nodes)
                        DropdownMenuItem(
                          value: node.code,
                          child: Text(node.code),
                        ),
                    ],
                    onChanged: (value) => update(() {
                      if (field == 'Từ node') {
                        from = value;
                      } else {
                        to = value;
                      }
                    }),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  items: [
                    for (final value in [
                      'Corridor',
                      'Door',
                      'Elevator',
                      'Stairs',
                      'Ramp',
                    ])
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: (value) => update(() => type = value!),
                  decoration: const InputDecoration(labelText: 'Loại cạnh'),
                ),
                TextField(
                  controller: meters,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Khoảng cách đo thực tế (mét)',
                  ),
                ),
                const Text(
                  'Không suy ra mét từ pixel. Muốn hai chiều: thêm cạnh ngược riêng.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(
                existing == null ? 'Thêm cạnh nháp' : 'Lưu cạnh nháp',
              ),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      await _read(() async {
        final edge = DraftEdge(
          from ?? '',
          to ?? '',
          double.tryParse(meters.text.trim()) ?? double.nan,
          type,
        );
        if (existing == null) {
          draft.addEdge(edge);
        } else {
          draft.updateEdge(existing, edge);
        }
        _selectedEdge = edge;
        _edited();
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    meters.dispose();
  }

  Widget _panel(Widget child) => Card(
    color: AppColors.card,
    elevation: 0,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: AppColors.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );

  Widget _imagePanel(DraftMap draft) => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'MẶT BẰNG TẦNG',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(
          draft.floor.name,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        if (draft.image case final image?) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image(
              image: image.imageProvider,
              key: const Key('draft-image-thumbnail'),
              height: 100,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            image.name,
            key: const Key('draft-image-name'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            '${image.width} × ${image.height} px • ${(image.bytes.length / 1024).toStringAsFixed(1)} KB',
            key: const Key('draft-image-dimensions'),
          ),
          const Text(
            'Ảnh cục bộ • chưa publish',
            style: TextStyle(color: Colors.brown),
          ),
          if (!draft.layoutReviewed)
            const Text(
              'Graph hiện có/demo chưa được căn chỉnh với ảnh mới. '
              'Tọa độ được giữ nguyên; cần kiểm tra từng node và cạnh.',
              key: Key('draft-image-alignment-warning'),
              style: TextStyle(
                color: Colors.brown,
                fontWeight: FontWeight.w600,
              ),
            ),
        ] else ...[
          const Icon(
            Icons.add_photo_alternate_outlined,
            size: 38,
            color: AppColors.accent,
          ),
          const Text(
            'Chưa có ảnh sơ đồ tầng. Chọn PNG/JPG để đặt graph lên đúng không gian.',
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('pick-floor-image'),
          onPressed: _busy || !_files.supported ? null : _image,
          icon: const Icon(Icons.upload_file),
          label: Text(
            draft.image == null ? 'Chọn ảnh PNG/JPG' : 'Thay ảnh PNG/JPG',
          ),
        ),
        const Text(
          'Tối đa 10 MB • 8192 px mỗi chiều • 32 MP',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        if (_operation != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_operation!, key: const Key('draft-image-progress')),
          ),
        const Divider(height: 24),
        const Text('ĐỐI TƯỢNG', style: TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(
          height: 220,
          child: ListView(
            children: [
              for (final node in draft.nodes)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _nodeIcon(node),
                    color: _nodeColor(node),
                    size: 20,
                  ),
                  selected: node.code == _selected,
                  title: Text(node.name),
                  subtitle: Text(node.code),
                  onTap: _busy || _preview
                      ? null
                      : () => setState(() {
                          _selected = node.code;
                          _selectedEdge = null;
                        }),
                ),
            ],
          ),
        ),
        const Text(
          'Tọa độ gắn với ảnh tầng này. Thay ảnh không tự căn lại graph; phải kiểm tra lại.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    ),
  );

  Widget _draftCanvas(DraftMap draft) => SizedBox(
    key: _canvasAnchor,
    height: 480,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.secondary,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FloorPlanCanvas(
          key: ValueKey('draft-canvas-${draft.floor.id}'),
          image: draft.image?.imageProvider,
          painter: DraftMapPainter(
            draft,
            _selected,
            selectedEdge: _selectedEdge,
            preview: _preview,
            route: _previewRoute,
            movingCode: _dragNode,
            movingPoint: _dragPoint,
          ),
          onPoint: _busy || _preview || _tool == 'Pan' ? null : _tap,
          onDragStart: _startDrag,
          onDragUpdate: (point) {
            if (_dragNode != null) setState(() => _dragPoint = point);
          },
          onDragEnd: _finishDrag,
          onDragCancel: () => setState(() {
            _dragNode = null;
            _dragPoint = null;
          }),
        ),
      ),
    ),
  );

  Widget _properties(DraftMap draft) {
    final selected = draft.nodes.where((n) => n.code == _selected).firstOrNull;
    final edge = _selectedEdge;
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'THUỘC TÍNH',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Divider(),
          if (selected != null) ...[
            Text(
              selected.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(selected.code),
            Text('Loại: ${selected.type}'),
            Text(
              'X/Y: ${selected.x.toStringAsFixed(4)} / ${selected.y.toStringAsFixed(4)}',
            ),
            Text('QR đề xuất: ${selected.wayMarkCode ?? 'Chưa liên kết'}'),
            const Text(
              'Điều kiện tiếp cận: chưa xác minh',
              style: TextStyle(color: Colors.brown),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('edit-draft-node'),
              onPressed: _busy
                  ? null
                  : () => _nodeDialog(
                      Offset(selected.x, selected.y),
                      existing: selected,
                    ),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Sửa thuộc tính node'),
            ),
            TextButton.icon(
              key: const Key('delete-draft-node'),
              onPressed: _busy ? null : () => _deleteNode(selected),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Xóa node nháp'),
            ),
            const Divider(),
            const Text('Kết nối có hướng'),
            for (final e in draft.edges.where(
              (e) => e.from == selected.code || e.to == selected.code,
            ))
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _selectedEdge = e;
                        _selected = null;
                      }),
                child: Text('${e.from} → ${e.to} • ${e.meters} m'),
              ),
          ] else if (edge != null) ...[
            Text(
              '${edge.from} → ${edge.to}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('${edge.type} • ${edge.meters} m'),
            const Text('Cạnh một chiều • accessibility chưa xác minh'),
            OutlinedButton(
              key: const Key('edit-draft-edge'),
              onPressed: _busy ? null : () => _edgeDialog(existing: edge),
              child: const Text('Sửa cạnh'),
            ),
            TextButton(
              key: const Key('delete-draft-edge'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      draft.removeEdge(edge);
                      _selectedEdge = null;
                      _edited();
                    }),
              child: const Text('Xóa cạnh nháp'),
            ),
          ] else
            const Text(
              'Chọn node/cạnh trên ảnh hoặc trong danh sách. Kéo node để di chuyển.',
            ),
          const SizedBox(height: 12),
          const Text(
            'Chỉ sửa bản nháp cục bộ. Không cập nhật WayMark hoặc graph trên server.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _previewControls(DraftMap draft) => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'PREVIEW CỤC BỘ — cùng tầng, chưa duyệt cho người đi đường',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown),
        ),
        CheckboxListTile(
          key: const Key('review-draft-layout'),
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Tôi đã đối chiếu node và cạnh với ảnh cho lần xem trước này',
          ),
          subtitle: const Text(
            'Không phải phê duyệt publish hoặc an toàn xe lăn.',
          ),
          value: draft.layoutReviewed,
          onChanged: _busy || draft.image == null
              ? null
              : (value) => setState(() {
                  draft.layoutReviewed = value ?? false;
                  _previewRoute = null;
                }),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final start in [true, false])
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    start ? 'draft-route-start' : 'draft-route-end',
                  ),
                  initialValue: start ? _routeStart : _routeEnd,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: start
                        ? 'Xuất phát (node nháp)'
                        : 'Đích (node nháp)',
                  ),
                  items: [
                    for (final n in draft.nodes)
                      DropdownMenuItem(
                        value: n.code,
                        child: Text(n.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          if (start) {
                            _routeStart = value;
                          } else {
                            _routeEnd = value;
                          }
                          _previewRoute = null;
                        }),
                ),
              ),
            FilledButton(
              key: const Key('preview-draft-route'),
              onPressed:
                  _busy ||
                      !draft.layoutReviewed ||
                      _routeStart == null ||
                      _routeEnd == null
                  ? null
                  : () {
                      try {
                        setState(
                          () => _previewRoute = draft.previewRoute(
                            _routeStart!,
                            _routeEnd!,
                          ),
                        );
                      } on FormatException catch (error) {
                        setState(() => _previewRoute = null);
                        _notice(error.message, error: true);
                      }
                    },
              child: const Text('Xem tuyến nháp'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_previewRoute case final path?)
          Text(
            '${path.edges.length} chặng • ${formatMeters(path.meters)} • ${path.nodeCodes.join(' → ')}',
            key: const Key('draft-route-summary'),
          ),
        const Text(
          'Chỉ hiển thị node/cạnh thuộc tuyến vừa tính. Không định vị, không chuyển sang Navigation production.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    ),
  );

  Widget _workspace(DraftMap draft) => LayoutBuilder(
    builder: (context, bounds) {
      final canvas = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const Key('draft-mode-edit'),
                selectedColor: AppColors.secondary,
                backgroundColor: AppColors.card,
                labelStyle: const TextStyle(color: AppColors.primary),
                label: const Text('Edit Graph'),
                selected: !_preview,
                onSelected: _busy
                    ? null
                    : (_) => setState(() => _preview = false),
              ),
              ChoiceChip(
                key: const Key('draft-mode-preview'),
                selectedColor: AppColors.secondary,
                backgroundColor: AppColors.card,
                labelStyle: const TextStyle(color: AppColors.primary),
                label: const Text('Preview Route'),
                selected: _preview,
                onSelected: _busy
                    ? null
                    : (_) => setState(() {
                        _preview = true;
                        _selected = null;
                        _selectedEdge = null;
                      }),
              ),
              if (!_preview)
                for (final tool in ['Chọn', 'Thêm node', 'Di chuyển', 'Pan'])
                  ChoiceChip(
                    selectedColor: AppColors.secondary,
                    backgroundColor: AppColors.card,
                    labelStyle: const TextStyle(color: AppColors.primary),
                    label: Text(tool),
                    selected: tool == _tool,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _tool = tool),
                  ),
              if (!_preview)
                OutlinedButton(
                  onPressed: _busy || draft.nodes.length < 2
                      ? null
                      : () => _edgeDialog(),
                  child: const Text('Thêm cạnh có hướng'),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _preview
                  ? 'Ảnh tầng + tuyến nháp được chọn. Graph chỉnh sửa được ẩn.'
                  : 'Kéo node để sửa vị trí • Pan để kéo bản đồ • Scroll/pinch để zoom • Chọn cạnh để sửa.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (_preview) _previewControls(draft),
          _draftCanvas(draft),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '${draft.nodes.length} node / ${draft.edges.length} cạnh có hướng (cùng tầng).',
            ),
          ),
          const Text(
            '○ Hành lang / lối vào   ▣ QR đề xuất   ◇ Điểm đến   E Thang máy   T Cầu thang   → Cạnh một chiều',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      );
      if (bounds.maxWidth >= 1100) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 220, child: _imagePanel(draft)),
            const SizedBox(width: 12),
            Expanded(child: canvas),
            if (!_preview) ...[
              const SizedBox(width: 12),
              SizedBox(width: 250, child: _properties(draft)),
            ],
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _imagePanel(draft),
          const SizedBox(height: 12),
          canvas,
          if (!_preview) _properties(draft),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => mapUiTheme(
    context,
    PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && (_scaffoldKey.currentState?.isDrawerOpen ?? false)) {
          _scaffoldKey.currentState!.closeDrawer();
          return;
        }
        if (!didPop && await _discard() && context.mounted) {
          setState(() => _dirty = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.maybePop(context);
          });
        }
      },
      child: AdminPageShell(
        title: 'Map Builder — bản nháp cục bộ',
        scaffoldKey: _scaffoldKey,
        beforeNavigate: _beforeNavigate,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'BẢN NHÁP — chưa duyệt cho bệnh nhân. Chỉ đọc API; không có thao tác xuất bản hoặc ghi SQL.',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (!_files.supported)
              const Text(
                'Chọn ảnh và nhập/xuất file hiện hỗ trợ trên Web. Canvas và sửa bản nháp dùng được trên Android.',
              ),
            if (_busy) ...[
              const LinearProgressIndicator(),
              Text(_operation ?? 'Đang xử lý bản nháp…'),
            ],
            if (_message != null)
              Semantics(
                liveRegion: true,
                child: Container(
                  key: const Key('draft-feedback'),
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _messageError
                        ? Colors.red.shade50
                        : Colors.cyan.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _messageError
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        color: _messageError
                            ? Colors.red.shade800
                            : AppColors.accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_message!, key: const Key('draft-message')),
                      ),
                    ],
                  ),
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final level in ['Site', 'Building', 'Floor'])
                  SizedBox(
                    width: 240,
                    child: InputDecorator(
                      decoration: InputDecoration(labelText: level),
                      child: DropdownButton<int>(
                        key: ValueKey('draft-$level'),
                        isExpanded: true,
                        value: level == 'Site'
                            ? _site
                            : level == 'Building'
                            ? _building
                            : _floor,
                        hint: const Text('Chọn từ API'),
                        items: [
                          for (final item
                              in (level == 'Site'
                                  ? _sites
                                  : level == 'Building'
                                  ? _buildings
                                  : _floors))
                            DropdownMenuItem(
                              value: item['id'] as int,
                              child: Text(
                                item['name'] as String,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) {
                                if (value != null) _choose(level, value);
                              },
                      ),
                    ),
                  ),
                if (_sites.isEmpty && !_busy)
                  TextButton(
                    onPressed: () => _read(() async {
                      _sites = await _api.getSites();
                    }),
                    child: const Text('Tải lại Site'),
                  ),
              ],
            ),
            if (_draft case final draft?) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    key: const Key('export-draft'),
                    onPressed: _busy || !_files.supported ? null : _export,
                    child: const Text('Lưu bản nháp JSON + ảnh'),
                  ),
                  OutlinedButton(
                    key: const Key('import-draft'),
                    onPressed: _busy || !_files.supported ? null : _import,
                    child: const Text('Mở bản nháp JSON'),
                  ),
                ],
              ),
              _workspace(draft),
            ] else
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('Chọn Site, Building và Floor từ dữ liệu API.'),
              ),
          ],
        ),
      ),
    ),
  );
}

IconData _nodeIcon(DraftNode node) => node.wayMarkCode != null
    ? Icons.qr_code
    : switch (node.type) {
        'Destination' => Icons.flag_outlined,
        'Elevator' => Icons.elevator_outlined,
        'Stairs' => Icons.stairs_outlined,
        'Entrance' => Icons.login,
        _ => Icons.circle_outlined,
      };
Color _nodeColor(DraftNode node) => node.wayMarkCode != null
    ? Colors.cyan.shade700
    : switch (node.type) {
        'Destination' => AppColors.accent,
        'Elevator' => Colors.indigo,
        'Stairs' => Colors.orange.shade800,
        _ => AppColors.primary,
      };

class DraftMapPainter extends CustomPainter {
  const DraftMapPainter(
    this.draft,
    this.selected, {
    this.selectedEdge,
    this.preview = false,
    this.route,
    this.movingCode,
    this.movingPoint,
  });
  final DraftMap draft;
  final String? selected, movingCode;
  final DraftEdge? selectedEdge;
  final bool preview;
  final DraftRoute? route;
  final Offset? movingPoint;
  List<String> get visibleNodeCodes => preview
      ? route?.nodeCodes ?? []
      : draft.nodes.map((n) => n.code).toList();
  List<DraftEdge> get visibleEdges =>
      preview ? route?.edges ?? [] : draft.edges;

  @override
  void paint(Canvas canvas, Size size) {
    final nodes = {for (final n in draft.nodes) n.code: n};
    Offset at(DraftNode n) {
      final point = n.code == movingCode && movingPoint != null
          ? movingPoint!
          : Offset(n.x, n.y);
      return Offset(point.dx * size.width, point.dy * size.height);
    }

    for (final edge in visibleEdges) {
      final from = at(nodes[edge.from]!);
      final to = at(nodes[edge.to]!);
      final pen = Paint()
        ..color = preview || identical(edge, selectedEdge)
            ? AppColors.accent
            : Colors.blueGrey
        ..strokeWidth = preview ? 6 : 3;
      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = Colors.white
          ..strokeWidth = preview ? 11 : 6,
      );
      canvas.drawLine(from, to, pen);
      final mid = Offset.lerp(from, to, .60)!;
      final delta = to - from;
      if (delta.distance < 1) continue;
      final angle = math.atan2(delta.dy, delta.dx);
      for (final direction in [-.5, .5]) {
        canvas.drawLine(
          mid,
          mid -
              Offset(math.cos(angle + direction), math.sin(angle + direction)) *
                  9,
          Paint()
            ..color = preview ? Colors.white : pen.color
            ..strokeWidth = 2,
        );
      }
    }
    for (final code in visibleNodeCodes) {
      final n = nodes[code]!;
      final point = at(n);
      final qr = n.wayMarkCode != null;
      final destination = n.type == 'Destination';
      final body = Paint()..color = _nodeColor(n);
      canvas.drawCircle(
        point,
        n.code == selected ? 15 : 12,
        Paint()..color = Colors.white,
      );
      if (qr) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: point, width: 19, height: 19),
            const Radius.circular(3),
          ),
          body,
        );
      } else if (destination) {
        canvas.drawPath(
          Path()
            ..moveTo(point.dx, point.dy - 11)
            ..lineTo(point.dx + 11, point.dy)
            ..lineTo(point.dx, point.dy + 11)
            ..lineTo(point.dx - 11, point.dy)
            ..close(),
          body,
        );
      } else {
        canvas.drawCircle(point, 9, body);
      }
      if (n.code == selected) {
        canvas.drawCircle(
          point,
          16,
          Paint()
            ..color = AppColors.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      final symbol = preview && code == route!.nodeCodes.first
          ? 'S'
          : preview && code == route!.nodeCodes.last
          ? 'Đ'
          : qr
          ? 'Q'
          : n.type == 'Elevator'
          ? 'E'
          : n.type == 'Stairs'
          ? 'T'
          : '';
      final marker = TextPainter(
        text: TextSpan(
          text: symbol,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'Inter',
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      marker.paint(canvas, point - Offset(marker.width / 2, marker.height / 2));
      final label = TextPainter(
        text: TextSpan(
          text: n.name,
          style: const TextStyle(
            color: AppColors.primary,
            fontFamily: 'Inter',
            fontSize: 11,
            backgroundColor: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 160);
      label.paint(canvas, point + const Offset(12, 12));
    }
  }

  @override
  bool shouldRepaint(covariant DraftMapPainter oldDelegate) => true;
}
