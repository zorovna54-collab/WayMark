part of 'draft_map_editor.dart';

extension _ProjectDraftEditor on _DraftMapEditorState {
  LocalMapProject get _localProject {
    final current = _draft!;
    final project = _project ??= LocalMapProject(current);
    final index = project.floors.indexWhere(
      (f) =>
          f.localWorkspaceId?.toLowerCase() ==
          current.localWorkspaceId?.toLowerCase(),
    );
    if (index < 0) {
      throw const FormatException(
        'Tầng đang chỉnh không thuộc project hiện tại. Giữ bản local; không đồng bộ sai project.',
      );
    }
    // The canvas is authoritative for its selected floor, including replacement
    // after import/restore. Retain project/floor GUIDs, never allocate new IDs.
    project.floors[index] = current;
    return project;
  }

  void _selectProjectFloor(DraftMap floor) {
    _draft = floor;
    _selected = _dragNode = _routeStart = _routeEnd = null;
    _selectedEdge = null;
    _dragPoint = null;
    _preview = false;
    _previewRoute = null;
    _tool = 'Chọn';
  }

  Future<void> _floorDialog({bool rename = false}) async {
    final project = _localProject, current = _draft!;
    final name = TextEditingController(text: rename ? current.floor.name : ''),
        code = TextEditingController(
          text: rename ? current.floor.floorCode : '',
        );
    String? error;
    final ok = await showWorkflowDialog<bool>(
      context: context,
      workflow: _owner,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(rename ? 'Đổi tên tầng' : 'Thêm tầng'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Tên tầng'),
                  maxLength: 100,
                ),
                TextField(
                  controller: code,
                  decoration: const InputDecoration(labelText: 'Mã tầng'),
                  maxLength: 30,
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty ||
                    code.text.trim().isEmpty ||
                    project.floors.any(
                      (f) =>
                          (!rename || f != current) &&
                          f.floor.floorCode.toLowerCase() ==
                              code.text.trim().toLowerCase(),
                    )) {
                  update(() => error = 'Tên/mã tầng thiếu hoặc trùng.');
                  return;
                }
                if (!rename &&
                    project.floors.length >= LocalMapProject.maxFloors) {
                  update(() => error = 'Tối đa 12 tầng.');
                  return;
                }
                Navigator.pop(dialog, true);
              },
              child: const Text('Lưu tầng'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted && _owner.current) {
      await _read(() async {
        final next = rename
            ? await _wait(project.renameFloor(current, name.text, code.text))
            : DraftMap.local(
                current.localSiteName!,
                current.localBuildingName!,
                name.text.trim(),
                code.text.trim(),
              );
        if (!rename) project.floors.add(next);
        if (mounted) {
          _update(() {
            _selectProjectFloor(next);
            _dirty = true;
            _localSaved = false;
          });
        }
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    code.dispose();
  }

  Future<void> _deleteProjectFloor() async {
    final project = _localProject, current = _draft!;
    final ok = await showWorkflowDialog<bool>(
      context: context,
      workflow: _owner,
      builder: (dialog) => AlertDialog(
        title: Text('Xóa tầng ${current.floor.name}?'),
        content: Text(
          'Xóa ảnh, ${current.nodes.length} node, ${current.edges.length} cạnh, ${current.places.length} phòng và mọi liên kết tới tầng này trong bản nháp. Không tác động server. Có thể mở lại file đã lưu trước đó.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Giữ tầng'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Xóa tầng'),
          ),
        ],
      ),
    );
    if (ok == true && mounted && _owner.current) {
      _update(() {
        project.removeFloor(current);
        _selectProjectFloor(project.floors.first);
        _dirty = true;
        _localSaved = false;
      });
    }
  }

  Future<void> _linkDialog({LocalFloorLink? existing}) async {
    final project = _localProject;
    final choices = <({DraftMap floor, DraftNode node, String id})>[
      for (final f in project.floors)
        for (final n in f.nodes)
          if (['Stairs', 'Elevator'].contains(n.type))
            (floor: f, node: n, id: f.nodeId(n.code)),
    ];
    if (choices.length < 2) {
      _notice('Hãy tạo node Stairs/Elevator ở ít nhất hai tầng.', error: true);
      return;
    }
    String? from = existing?.fromNode, to = existing?.toNode, error;
    var active = existing?.active ?? true, reverse = false;
    final meters = TextEditingController(
      text: existing?.meters.toString() ?? '',
    );
    final ok = await showWorkflowDialog<bool>(
      context: context,
      workflow: _owner,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            existing == null ? 'Nối tầng có hướng' : 'Sửa liên kết tầng',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Chỉ nối Stairs ↔ Stairs hoặc Elevator ↔ Elevator khác tầng. Mét nhập thủ công. Tiếp cận: Unknown.',
                ),
                for (final source in [true, false])
                  DropdownButtonFormField<String>(
                    initialValue: source ? from : to,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: source ? 'Từ node / tầng' : 'Đến node / tầng',
                    ),
                    items: [
                      for (final c in choices)
                        DropdownMenuItem(
                          value: c.id,
                          child: Text(
                            '${c.floor.floor.name}: ${c.node.name} (${c.node.code})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => update(() {
                      if (source) {
                        from = v;
                      } else {
                        to = v;
                      }
                    }),
                  ),
                TextField(
                  controller: meters,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Khoảng cách liên tầng (m)',
                  ),
                ),
                SwitchListTile(
                  title: const Text('Cạnh active'),
                  value: active,
                  onChanged: (v) => update(() => active = v),
                ),
                if (existing == null)
                  CheckboxListTile(
                    title: const Text('Tạo thêm cạnh ngược chiều'),
                    value: reverse,
                    onChanged: (v) => update(() => reverse = v ?? false),
                  ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  if (from == null || to == null) {
                    throw const FormatException('Chọn đủ hai node.');
                  }
                  final a = choices.singleWhere((c) => c.id == from),
                      b = choices.singleWhere((c) => c.id == to);
                  final m = double.tryParse(meters.text.replaceAll(',', '.'));
                  if (m == null || !m.isFinite || m <= 0) {
                    throw const FormatException('Nhập mét > 0.');
                  }
                  final link = LocalFloorLink(
                    id: existing?.id,
                    fromFloor: a.floor.localWorkspaceId!,
                    fromNode: a.id,
                    toFloor: b.floor.localWorkspaceId!,
                    toNode: b.id,
                    meters: m,
                    type: a.node.type,
                    active: active,
                  );
                  final old = List<LocalFloorLink>.of(project.links);
                  try {
                    if (existing != null) project.links.remove(existing);
                    project.links.add(link);
                    if (reverse) {
                      project.links.add(
                        LocalFloorLink(
                          fromFloor: link.toFloor,
                          fromNode: link.toNode,
                          toFloor: link.fromFloor,
                          toNode: link.fromNode,
                          meters: m,
                          type: link.type,
                          active: active,
                        ),
                      );
                    }
                    project.checkReferences();
                  } catch (_) {
                    project.links = old;
                    rethrow;
                  }
                  Navigator.pop(dialog, true);
                } on FormatException catch (e) {
                  update(() => error = e.message);
                }
              },
              child: const Text('Lưu liên kết'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted && _owner.current) {
      _update(() {
        _dirty = true;
        _localSaved = false;
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    meters.dispose();
  }

  Future<void> _showFloorLinks() async {
    final project = _localProject;
    await _mobileSheet(
      () => Column(
        children: [
          const Text('Liên kết tầng có hướng • Unknown'),
          for (final l in project.links)
            ListTile(
              title: Text(
                '${l.type} • ${l.meters} m ${l.active ? '' : '• inactive'}',
              ),
              subtitle: Text(
                '${project.floors.firstWhere((f) => f.localWorkspaceId == l.fromFloor).floor.name} → ${project.floors.firstWhere((f) => f.localWorkspaceId == l.toFloor).floor.name}',
              ),
              onTap: () async {
                await _linkDialog(existing: l);
                _refreshSheet?.call();
              },
              trailing: IconButton(
                tooltip: 'Xóa liên kết',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final ok = await showWorkflowDialog<bool>(
                    context: context,
                    workflow: _owner,
                    builder: (d) => AlertDialog(
                      title: const Text('Xóa liên kết có hướng này?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(d, false),
                          child: const Text('Hủy'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(d, true),
                          child: const Text('Xóa liên kết'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true && mounted && _owner.current) {
                    _update(() {
                      project.links.remove(l);
                      _dirty = true;
                      _localSaved = false;
                    });
                    _refreshSheet?.call();
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _projectControls({bool showActions = true}) {
    final project = _localProject;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('project-floor-${_draft!.localWorkspaceId}'),
          initialValue: _draft!.localWorkspaceId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Tầng đang chỉnh • ${project.floors.length} tầng',
          ),
          items: [
            for (final f in project.floors)
              DropdownMenuItem(
                value: f.localWorkspaceId,
                child: Text('${f.floor.name} (${f.floor.floorCode})'),
              ),
          ],
          onChanged: _busy
              ? null
              : (id) => _update(
                  () => _selectProjectFloor(
                    project.floors.singleWhere((f) => f.localWorkspaceId == id),
                  ),
                ),
        ),
        if (showActions) _projectFloorActions(),
      ],
    );
  }

  Widget _projectFloorActions() {
    final project = _localProject;
    return Wrap(
      spacing: 8,
      children: [
        TextButton(
          key: const Key('add-project-floor'),
          onPressed: _busy ? null : () => _floorDialog(),
          child: const Text('Thêm tầng'),
        ),
        TextButton(
          onPressed: _busy ? null : () => _floorDialog(rename: true),
          child: const Text('Đổi tên tầng'),
        ),
        TextButton(
          onPressed: _busy || project.floors.length < 2
              ? null
              : _deleteProjectFloor,
          child: const Text('Xóa tầng'),
        ),
        TextButton(
          onPressed: _busy ? null : _linkDialog,
          child: const Text('Nối tầng'),
        ),
        TextButton(
          onPressed: _busy ? null : _showFloorLinks,
          child: Text('${project.links.length} liên kết tầng'),
        ),
      ],
    );
  }
}
