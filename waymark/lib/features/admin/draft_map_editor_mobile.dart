part of 'draft_map_editor.dart';

extension _MobileDraftEditor on _DraftMapEditorState {
  Future<void> _validateLocal({bool navigate = false}) async {
    final draft = _draft;
    if (draft == null || _busy) return;
    final project = _project;
    final multi = project != null && project.floors.length > 1;
    final report = multi
        ? LocalMapNavigation.validateProject(project)
        : LocalMapValidation.check(draft);
    final accepted = await showWorkflowDialog<bool>(
      context: context,
      workflow: _owner,
      builder: (dialog) => AlertDialog(
        title: Text(
          report.canRoute
              ? 'Dữ liệu có thể tính tuyến cục bộ'
              : 'Cần sửa bản đồ trước khi tính tuyến',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in report.errors)
                Text('Lỗi: $e', style: const TextStyle(color: Colors.red)),
              for (final w in report.warnings) Text('Cảnh báo: $w'),
              const Text(
                'Validation không phải phê duyệt an toàn ngoài đời thực. Chỉ dùng liên kết tầng đã khai báo; chưa xác minh khả năng tiếp cận.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Đóng'),
          ),
          if (navigate && report.canRoute)
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Chọn điểm đến'),
            ),
        ],
      ),
    );
    if (accepted != true ||
        (!mounted || !_owner.current) ||
        !identical(draft, _draft)) {
      return;
    }
    LocalMapNavigation? map;
    await _read(() async {
      map = multi
          ? await _wait(LocalMapNavigation.fromProject(project))
          : await _wait(LocalMapNavigation.fromDraft(draft));
    }, operation: 'Đang chuẩn bị bản sao bản đồ cục bộ…');
    if (map == null ||
        (!mounted || !_owner.current) ||
        !identical(draft, _draft)) {
      return;
    }
    final destinationFloors = project?.floors ?? [draft];
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            LocalMapSearchPage(map: map!, destinationFloors: destinationFloors),
      ),
    );
  }

  String _nextLocalNodeCode() {
    final prefix = 'LOCAL-${_draft!.localWorkspaceId}';
    var index = 1;
    while (_draft!.nodes.any((n) => n.code == '$prefix-$index')) {
      index++;
    }
    return '$prefix-$index';
  }

  Future<void> _newLocal() async {
    if (!await _discard() || (!mounted || !_owner.current)) return;
    final fields = [
      TextEditingController(text: 'Khu vực của tôi'),
      TextEditingController(text: 'Tòa nhà'),
      TextEditingController(text: 'Tầng mới'),
      TextEditingController(text: 'F1'),
    ];
    String? error;
    final accepted = await showWorkflowDialog<bool>(
      context: context,
      workflow: _owner,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Bản đồ mới từ đầu'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Chỉ lưu cục bộ. Không cần Site từ API; không dùng graph demo.',
                ),
                for (var i = 0; i < fields.length; i++)
                  TextField(
                    controller: fields[i],
                    maxLength: i == 3 ? 30 : 100,
                    decoration: InputDecoration(
                      labelText: [
                        'Tên khu vực',
                        'Tên tòa nhà',
                        'Tên tầng',
                        'Mã tầng',
                      ][i],
                    ),
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
              key: const Key('create-local-map'),
              onPressed: () {
                if (fields.any((f) => f.text.trim().isEmpty)) {
                  update(() => error = 'Điền đủ tên và mã tầng.');
                  return;
                }
                Navigator.pop(dialog, true);
              },
              child: const Text('Tạo bản đồ trống'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted && _owner.current) {
      _update(() {
        _draft = DraftMap.local(
          fields[0].text.trim(),
          fields[1].text.trim(),
          fields[2].text.trim(),
          fields[3].text.trim(),
        );
        _server = null;
        _project = LocalMapProject(_draft!);
        _site = _building = _floor = null;
        _selected = _dragNode = _routeStart = _routeEnd = null;
        _selectedEdge = null;
        _dragPoint = null;
        _preview = false;
        _previewRoute = null;
        _tool = 'Chọn';
        _dirty = true;
        _localSaved = false;
        _message = null;
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final f in fields) {
      f.dispose();
    }
  }

  Future<void> _openLocal() async {
    if (!await _discard() || (!mounted || !_owner.current)) return;
    await _read(() async {
      final file = await _files.pick('.json', LocalMapProject.maxBytes);
      if (file == null) {
        _notice('Đã hủy mở JSON. Bản đồ đang chỉnh giữ nguyên.');
        return;
      }
      var project = await LocalMapProject.decode(file.bytes);
      for (final floor in project.floors) {
        DraftServerMapper.content(floor, null);
      }
      final current = _project;
      if (current != null &&
          _projectCloudLinks.containsKey(current.id) &&
          (jsonDecode(utf8.decode(file.bytes)) as Map)['version'] == 2 &&
          current.floors.length == 1 &&
          current.links.isEmpty &&
          project.floors.single.localWorkspaceId?.toLowerCase() ==
              current.floors.single.localWorkspaceId?.toLowerCase()) {
        if ((!mounted || !_owner.current)) return;
        final keepMap = await showWorkflowDialog<bool>(
          context: context,
          workflow: _owner,
          builder: (c) => AlertDialog(
            title: const Text('Khôi phục JSON v2 vào bản đồ đang mở?'),
            content: const Text(
              'GUID tầng đã khớp. Giữ project ID của personal map hiện tại cùng GUID node/cạnh trong backup. Chỉ thay bản local sau xác nhận; chưa ghi server.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Khôi phục vào bản đồ này'),
              ),
            ],
          ),
        );
        if (keepMap != true || (!mounted || !_owner.current)) return;
        project = LocalMapProject.recoverSingleFloor(
          project.floors.single,
          current,
        );
      }
      final draft = project.floors.first;
      if ((!mounted || !_owner.current)) return;
      _draft = draft;
      _project = project;
      _server = null;
      _site = _building = _floor = null;
      _selected = _dragNode = _routeStart = _routeEnd = null;
      _selectedEdge = null;
      _dragPoint = null;
      _preview = false;
      _previewRoute = null;
      _tool = 'Chọn';
      _dirty = false;
      _localSaved = true;
      _notice(
        'Đã mở ${project.floors.length} tầng từ ${project.floors.length > 1 ? 'JSON v3' : 'JSON v2'}. Ảnh và dữ liệu chỉ ở bản nháp, chưa xuất bản.',
      );
      _scheduleRecovery();
    });
  }

  Future<void> _roomDialog(
    Offset point, {
    Map<String, dynamic>? existing,
  }) async {
    final draft = _draft!;
    final code = TextEditingController(
      text: existing?['placeCode'] as String? ?? '',
    );
    final name = TextEditingController(
      text: existing?['name'] as String? ?? '',
    );
    final oldLabel = existing?['label'] as Map?;
    final x = TextEditingController(
      text: (oldLabel?['x'] ?? point.dx).toStringAsFixed(4),
    );
    final y = TextEditingController(
      text: (oldLabel?['y'] ?? point.dy).toStringAsFixed(4),
    );
    final entrances = <String>{
      ...?((existing?['entranceNodeIds'] as List?)?.cast<String>()),
    };
    String? error;
    Map<String, dynamic>? result;
    final accepted = await showWorkflowDialog<bool>(
      context: context,
      workflow: _owner,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(existing == null ? 'Thêm Room/Place' : 'Sửa Room/Place'),
          content: SizedBox(
            width: 350,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: code,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Mã phòng / số phòng',
                    ),
                  ),
                  TextField(
                    controller: name,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Tên Room/Place',
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: x,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Nhãn X (0–1)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: y,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Nhãn Y (0–1)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'Chọn ít nhất một cửa Entrance. Tuyến sẽ đến cửa, không đến nhãn/tâm phòng. Tiếp cận: Unknown.',
                  ),
                  if (!draft.nodes.any((n) => n.type == 'Entrance'))
                    const Text(
                      'Hãy tạo node loại Entrance trước.',
                      style: TextStyle(color: Colors.brown),
                    ),
                  for (final node in draft.nodes.where(
                    (n) => n.type == 'Entrance',
                  ))
                    CheckboxListTile(
                      title: Text(node.name),
                      subtitle: Text(node.code),
                      value: entrances.contains(draft.nodeId(node.code)),
                      onChanged: (value) => update(() {
                        if (value == true) {
                          entrances.add(draft.nodeId(node.code));
                        } else {
                          entrances.remove(draft.nodeId(node.code));
                        }
                      }),
                    ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
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
                  result = {
                    'id': existing?['id'] ?? newDraftGuid(),
                    'placeCode': code.text.trim(),
                    'name': name.text.trim(),
                    'label': {
                      'x': double.tryParse(x.text) ?? -1,
                      'y': double.tryParse(y.text) ?? -1,
                    },
                    'polygon': existing?['polygon'] ?? [],
                    'entranceNodeIds': entrances.toList(),
                    'accessibility': 'Unknown',
                  };
                  final content = DraftServerMapper.content(draft, null);
                  final places = (content['places'] as List)
                    ..removeWhere((p) => p['id'] == existing?['id']);
                  places.add(result);
                  DraftServerMapper.validate(content);
                  Navigator.pop(dialog, true);
                } on FormatException catch (e) {
                  update(() => error = e.message);
                }
              },
              child: const Text('Lưu phòng nháp'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true &&
        result != null &&
        mounted &&
        identical(draft, _draft)) {
      _update(() {
        draft.places.removeWhere((p) => p['id'] == existing?['id']);
        draft.places.add(result!);
        _edited();
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final f in [code, name, x, y]) {
      f.dispose();
    }
  }

  Widget _roomPanel(DraftMap draft) => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('ROOM / PLACE • cửa vào dùng Entrance'),
        for (final place in draft.places)
          ListTile(
            title: Text('${place['name']} (${place['placeCode']})'),
            subtitle: Text(
              '${(place['entranceNodeIds'] as List).length} cửa • tiếp cận Unknown',
            ),
            onTap: _busy
                ? null
                : () => _roomDialog(Offset.zero, existing: place),
            trailing: IconButton(
              tooltip: 'Xóa phòng nháp',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy
                  ? null
                  : () async {
                      final accepted = await showWorkflowDialog<bool>(
                        context: context,
                        workflow: _owner,
                        builder: (dialog) => AlertDialog(
                          title: const Text('Xóa Room/Place?'),
                          content: const Text(
                            'Chỉ bỏ phòng khỏi bản nháp. Giữ node cửa và cạnh.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialog, false),
                              child: const Text('Hủy'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(dialog, true),
                              child: const Text('Xóa phòng'),
                            ),
                          ],
                        ),
                      );
                      if (accepted == true && mounted && _owner.current) {
                        _update(() {
                          draft.places.remove(place);
                          _edited();
                        });
                      }
                    },
            ),
          ),
        OutlinedButton(
          onPressed: _busy || _preview
              ? null
              : () => _roomDialog(const Offset(.5, .5)),
          child: const Text('Thêm Room/Place'),
        ),
      ],
    ),
  );

  Future<void> _mobileSheet(Widget Function() body) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ListenableBuilder(
        listenable: _owner,
        builder: (context, _) => !_owner.current
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Phiên đã thay đổi • đóng bảng để khôi phục bản nháp',
                    ),
                  ),
                ),
              )
            : StatefulBuilder(
                builder: (context, update) {
                  _refreshSheet = () => update(() {});
                  return SizedBox(
                    height: MediaQuery.sizeOf(context).height * .8,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Đóng bảng'),
                            ),
                          ),
                          body(),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
    _refreshSheet = null;
  }

  Widget _mobileBody() {
    final draft = _draft;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            draft?.isLocal == true
                ? 'BẢN NHÁP CỤC BỘ • chưa publish'
                : 'MAP BUILDER • chưa publish',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('new-local-map'),
                onPressed: _busy ? null : _newLocal,
                icon: const Icon(Icons.add),
                label: const Text('Bản đồ mới'),
              ),
              OutlinedButton.icon(
                onPressed: _busy || !_files.supported ? null : _openLocal,
                icon: const Icon(Icons.folder_open),
                label: const Text('Mở JSON'),
              ),
              OutlinedButton.icon(
                key: const Key('map-project-cloud'),
                onPressed: _busy ? null : _projectCloud,
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('Server / Publish / QR'),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null)
            Text(
              _message!,
              key: const Key('draft-message'),
              style: TextStyle(
                color: _messageError ? Colors.red : AppColors.primary,
              ),
            ),
          if (draft == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Tạo bản đồ mới hoặc mở bản đã lưu. Thêm ảnh từng tầng, đặt điểm đến và nối đường đi trên sơ đồ.',
              ),
            ),
          if (draft != null) ...[
            if (draft.isLocal) _projectControls(showActions: false),
            Text(
              '${draft.localSiteName ?? 'Site ${draft.siteId}'} / ${draft.localBuildingName ?? 'Building ${draft.buildingId}'} / ${draft.floor.name}',
            ),
            Text(
              _dirty
                  ? 'Có thay đổi chưa lưu ra file'
                  : _localSaved
                  ? 'Đã lưu/mở file cục bộ • chưa lưu server'
                  : 'Chưa xác nhận lưu server',
              key: const Key('draft-save-state'),
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('pick-floor-image'),
                  onPressed: _busy || !_files.supported ? null : _image,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('Ảnh PNG/JPG'),
                ),
                if (draft.isLocal)
                  OutlinedButton.icon(
                    key: const Key('cleanup-floor-image'),
                    onPressed: _busy ? null : _cleanupImage,
                    icon: const Icon(Icons.crop),
                    label: const Text('Chỉnh ảnh sơ đồ'),
                  ),
                OutlinedButton(
                  key: const Key('export-draft'),
                  onPressed: _busy || !_files.supported ? null : _export,
                  child: const Text('Lưu JSON + ảnh'),
                ),
                OutlinedButton.icon(
                  key: const Key('ai-map-assistant'),
                  onPressed: _busy || draft.image == null ? null : _aiAssistant,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('AI đề xuất Node / Edge'),
                ),
              ],
            ),
            if (draft.image case final image?)
              Text('${image.name} • ${image.width} × ${image.height} px'),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final tool in ['Chọn', 'Thêm node', 'Di chuyển', 'Pan'])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(tool),
                        selected: !_preview && _tool == tool,
                        onSelected: _busy
                            ? null
                            : (_) => _update(() {
                                _tool = tool;
                                _preview = false;
                              }),
                      ),
                    ),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy || draft.nodes.length < 2
                      ? null
                      : () => _edgeDialog(),
                  child: const Text('Thêm cạnh có hướng'),
                ),
                OutlinedButton(
                  key: const Key('mark-selected-node-destination'),
                  onPressed: _busy || _selected == null
                      ? null
                      : _editSelectedDestinationNode,
                  child: const Text('Đánh dấu điểm đến'),
                ),
                ChoiceChip(
                  label: const Text('Preview Route'),
                  selected: _preview,
                  onSelected: _busy ? null : (v) => _update(() => _preview = v),
                ),

                OutlinedButton(
                  key: const Key('validate-local-map'),
                  onPressed: _busy ? null : () => _validateLocal(),
                  child: const Text('Validate Map'),
                ),
                FilledButton(
                  key: const Key('try-local-navigation'),
                  onPressed: _busy
                      ? null
                      : () => _validateLocal(navigate: true),
                  child: const Text('Thử dẫn đường'),
                ),
              ],
            ),
            Text(
              _preview
                  ? 'Tuyến cục bộ • không dùng cho bệnh nhân'
                  : 'Chạm để đặt/chọn • kéo node • dùng Pan để zoom/kéo ảnh',
            ),
            if (_preview) _previewControls(draft),
            _draftCanvas(draft),
            const SizedBox(height: 12),
            if (draft.nodes.isEmpty)
              const Text(
                'Bước tiếp theo: chọn “Thêm node”, rồi chạm lên sơ đồ để đặt một điểm. Đặt tên và bật điểm đến để tìm kiếm được.',
              ),
            FilterChip(
              key: const Key('show-map-labels'),
              label: const Text('Tên node / Room cũ'),
              selected: _showMapLabels,
              onSelected: (v) => _update(() => _showMapLabels = v),
            ),
            if (_selected != null &&
                draft.nodes.any((n) => n.code == _selected))
              Text(
                'Đang chọn: ${draft.nodes.singleWhere((n) => n.code == _selected).listLabel(draft.nodes.indexWhere((n) => n.code == _selected))}',
              ),
            Text(draft.graphSummary, key: const Key('draft-graph-summary')),
            if (draft.isLocal) ...[
              const SizedBox(height: 12),
              const Text(
                'QUẢN LÝ TẦNG',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              _projectFloorActions(),
            ],
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: const Key('legacy-room-tools'),
                  onPressed: _busy
                      ? null
                      : () => _mobileSheet(() => _roomPanel(draft)),
                  child: const Text('Nâng cao / Tương thích cũ'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _mobileSheet(
                          () => Column(
                            children: [_imagePanel(draft), _properties(draft)],
                          ),
                        ),
                  child: const Text('Đối tượng / Sửa'),
                ),
              ],
            ),
            if (_recoveryMessage != null)
              Text(_recoveryMessage!, key: const Key('draft-recovery-status')),
            if (_selected != null || _selectedEdge != null)
              OutlinedButton(
                onPressed: () => _mobileSheet(() => _properties(draft)),
                child: const Text('Sửa đối tượng đang chọn'),
              ),
            const Text(
              'Mét phải đo/nhập thủ công; không suy ra từ pixel. Lối đi và tiếp cận: chưa xác minh.',
            ),
          ],
        ],
      ),
    );
  }
}
