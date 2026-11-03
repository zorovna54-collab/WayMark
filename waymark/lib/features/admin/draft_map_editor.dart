import 'dart:math' as math;
import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

import 'package:flutter/material.dart';

import '../../services/auth_session.dart';
import '../../services/auth_api_service.dart';
import '../auth/workflow_recovery.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/map_ui_theme.dart';
import '../../models/route_models.dart' show formatMeters;
import '../../services/waymark_api_service.dart';
import '../../services/map_draft_api_service.dart';
import '../route/floor_plan_canvas.dart';
import '../route/map_paint_scale.dart';
import 'admin_page_shell.dart';
import 'draft_file_gateway.dart';
import 'draft_map.dart';
import 'local_map_project.dart';
import 'draft_exit_guard.dart';
import 'draft_recovery.dart';
import 'draft_server_session.dart';
import 'floor_plan_asset.dart';
import 'floor_image_cleanup.dart';
import 'floor_image_cleanup_page.dart';
import 'ai_map_assistant_page.dart';
import 'ai_graph_review.dart';
import 'map_project_cloud_page.dart';
import '../navigation/local_map_navigation.dart';
import '../search/local_map_search_page.dart';

part 'draft_map_editor_mobile.dart';
part 'draft_map_editor_project.dart';

class DraftMapEditor extends StatefulWidget {
  const DraftMapEditor({
    super.key,
    this.api,
    this.files,
    this.draftsApi,
    this.initialProject,
    this.initialCloudLink,
    this.recovery,
    this.aiProviderFactory,
  });
  final WayMarkApiService? api;
  final DraftFileGateway? files;
  final MapDraftApiService? draftsApi;
  final LocalMapProject? initialProject;
  final ProjectCloudLink? initialCloudLink;
  final DraftRecovery? recovery;
  final AiMapProviderFactory? aiProviderFactory;
  @override
  State<DraftMapEditor> createState() => _DraftMapEditorState();
}

class _DraftMapEditorState extends State<DraftMapEditor> {
  final _owner = OwnerWorkflow();
  void _ownerChanged() {
    if (mounted) setState(() {});
  }

  Future<T> _wait<T>(Future<T> future) => _owner.wait(future);
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final _api = widget.api ?? WayMarkApiService();
  late final _files = widget.files ?? const PlatformDraftFiles();
  late final _draftsApi =
      widget.draftsApi ?? MapDraftApiService(client: _api.client);
  DraftServerSession? _server;
  final _exitGuard = DraftExitGuard();
  final _canvasAnchor = GlobalKey();
  List<Map<String, dynamic>> _sites = [], _buildings = [], _floors = [];
  int? _site, _building, _floor;
  DraftMap? _draft;
  LocalMapProject? _project;
  final _projectCloudLinks = <String, ProjectCloudLink>{};
  late final _recovery = widget.recovery ?? const DraftRecovery();
  late final _recoveryOwner = DraftRecovery.ownerScope(
    WayMarkApiService.baseUrl,
  );
  Timer? _recoveryTimer;
  String? _recoveryMessage;
  Future<void> _persistRecovery() async {
    final p = _project;
    if (!_recovery.supported ||
        _recoveryOwner == null ||
        p == null ||
        _draft?.isLocal != true) {
      return;
    }
    try {
      await _recovery.write(_recoveryOwner, p.id, _localProject.encode());
      if (mounted) {
        setState(
          () => _recoveryMessage =
              'Đã lưu bản khôi phục trên thiết bị • chưa đồng bộ server',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _recoveryMessage = 'Chưa lưu được bản khôi phục trên thiết bị. Hãy xuất JSON; graph trong Builder còn nguyên.',
        );
      }
    }
  }

  void _scheduleRecovery() {
    if (!_recovery.supported || _recoveryOwner == null) return;
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(const Duration(milliseconds: 350), _persistRecovery);
  }

  Future<void> _offerRecovery(LocalMapProject original) async {
    if (!_recovery.supported) return;
    try {
      if (_recoveryOwner == null) return;
      final bytes = await _recovery.read(_recoveryOwner, original.id);
      if (bytes == null ||
          !mounted ||
          _dirty ||
          !identical(original, _project)) {
        return;
      }
      final restored = await _wait(LocalMapProject.decode(bytes));
      if (!mounted ||
          _dirty ||
          !identical(original, _project) ||
          restored.id != original.id ||
          jsonEncode(jsonDecode(utf8.decode(restored.encode()))) ==
              jsonEncode(jsonDecode(utf8.decode(original.encode())))) {
        return;
      }
      final use = await showWorkflowDialog<bool>(
        context: context,
        workflow: _owner,
        builder: (c) => AlertDialog(
          title: const Text('Có bản chỉnh sửa trên thiết bị'),
          content: Text(
            'Bản khôi phục: ${restored.floors.fold<int>(0, (n, f) => n + f.nodes.length)} node. Bản tải server: ${original.floors.fold<int>(0, (n, f) => n + f.nodes.length)} node. Khôi phục giữ nguyên project/GUID; chưa ghi server.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Giữ bản server'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Khôi phục chỉnh sửa local'),
            ),
          ],
        ),
      );
      if (use == true && mounted && identical(original, _project)) {
        setState(() {
          _project = restored;
          _selectProjectFloor(restored.floors.first);
          _dirty = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _recoveryMessage = 'Không mở được bản khôi phục. Bản server đang giữ nguyên; có thể mở JSON backup.',
        );
      }
    }
  }

  String? _selected, _message;
  DraftEdge? _selectedEdge;
  String? _dragNode, _routeStart, _routeEnd, _operation;
  Offset? _dragPoint;
  Size _sceneSize = const Size(1, 1);
  double _viewScale = 1;
  Offset _screenVector(Offset normalized) => Offset(
    normalized.dx * _sceneSize.width * _viewScale,
    normalized.dy * _sceneSize.height * _viewScale,
  );
  bool _preview = false, _messageError = false;
  DraftRoute? _previewRoute;
  bool _busy = false, _dirty = false;
  String _tool = 'Chọn';
  bool _localSaved = false;
  bool _showMapLabels = false;
  VoidCallback? _refreshSheet;
  void _update(VoidCallback change) => setState(change);
  @override
  void initState() {
    super.initState();
    _owner.addListener(_ownerChanged);
    if (widget.initialProject case final project?) {
      _project = project;
      _draft = project.floors.first;
      _localSaved = true;
      if (widget.initialCloudLink case final link?) {
        _projectCloudLinks[project.id] = link;
      }
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _offerRecovery(project),
      );
      return;
    }
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        widget.api == null) {
      return;
    }
    _read(() async {
      _sites = await _wait(_api.getSites());
    });
  }

  @override
  void dispose() {
    _owner.removeListener(_ownerChanged);
    _owner.dispose();
    _recoveryTimer?.cancel();
    _exitGuard.dispose();
    super.dispose();
  }

  bool _allowRecoveryExit = false;
  Widget _recoveryScreen() => PopScope(
    canPop: _allowRecoveryExit,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      final leave = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          scrollable: true,
          title: const Text('Rời bản nháp đang giữ?'),
          content: const Text(
            'Nội dung chưa lưu trong RAM có thể mất khi rời. Đăng nhập đúng chủ phiên để tiếp tục hoặc xác nhận bỏ phiên soạn này.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Giữ bản nháp'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Rời và bỏ bản trong RAM'),
            ),
          ],
        ),
      );
      if (leave == true && mounted) {
        setState(() => _allowRecoveryExit = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.maybePop(context);
        });
      }
    },
    child: WorkflowRecovery(
      workflow: _owner,
      api: AuthApiService(client: _api.client),
      onRecovered: () {
        setState(() {
          _sites = [];
          _buildings = [];
          _floors = [];
          _message = 'Đã khôi phục chủ phiên. Bản nháp giữ nguyên; đọc lại server để đối chiếu trước khi ghi. Không tự Save/Publish.';
        });
      },
    ),
  );
  void _notice(String message, {bool error = false, SnackBarAction? action}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageError = error;
    });
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          action: action,
          content: Text(message),
          backgroundColor: error ? Colors.red.shade800 : AppColors.primary,
        ),
      );
  }

  Future<void> _read(Future<void> Function() task, {String? operation}) async {
    if (_busy || !_owner.current) return;
    setState(() {
      _busy = true;
      _message = null;
      _messageError = false;
      _operation = operation;
    });
    _refreshSheet?.call();
    try {
      await _owner.run(task);
    } catch (error) {
      if (mounted) {
        final message =
            error is WayMarkApiException ||
                error is MapDraftApiException ||
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
        _refreshSheet?.call();
        if (_dirty) _scheduleRecovery();
      }
    }
  }

  Future<bool> _discard() async {
    if (_busy) return false;
    if (!_dirty) return true;
    final choice = await showWorkflowDialog<String>(
      context: context,
      workflow: _owner,
      builder: (c) => AlertDialog(
        title: const Text('Rời bản nháp chưa xuất?'),
        content: const Text(
          'Có thay đổi chưa lưu. Lưu trước khi rời, xác nhận rời bản đang chỉnh, hoặc Hủy để tiếp tục. Không tự ghi đè server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 'cancel'),
            child: const Text('Giữ lại'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'leave'),
            child: const Text('Rời bản nháp'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'save'),
            child: const Text('Lưu trước khi rời'),
          ),
        ],
      ),
    );
    if (choice == 'leave') return true;
    if (choice != 'save' || !mounted) return false;
    if (_draft?.isLocal == true) {
      if (_project != null && _projectCloudLinks.containsKey(_project!.id)) {
        await _projectCloud(saveBeforeLeave: true);
      } else {
        await _export();
      }
    } else if (_server != null) {
      await _saveServer();
    }
    return mounted && !_dirty;
  }

  Future<void> _choose(String level, int value) async {
    if (!await _discard() || !mounted) return;
    await _read(() async {
      if (level == 'Site') {
        final buildings = await _wait(_api.getBuildings(value));
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
        final floors = await _wait(_api.getFloors(value));
        if (floors.any((f) => f['buildingId'] != value)) {
          throw const FormatException('Floor sai Building.');
        }
        if (!mounted) return;
        _building = value;
        _floor = null;
        _floors = floors;
        _draft = null;
      } else {
        final graph = await _wait(_api.getFloorGraph(value));
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
      _server = _draft == null
          ? null
          : DraftServerSession(
              _draftsApi,
              siteId: _site!,
              buildingId: _building!,
              floor: _draft!.floor,
            );
    });
  }

  Future<bool> _beforeNavigate() async {
    final accepted = await _discard();
    if (accepted) await _persistRecovery();
    if (accepted && mounted) setState(() => _dirty = false);
    return accepted;
  }

  Future<void> _image() => _read(() async {
    final draft = _draft!;
    final file = await _wait(
      _files.pick('.png,.jpg,.jpeg', FloorPlanAsset.maxBytes),
    );
    if (file == null) {
      _notice('Đã hủy chọn ảnh. Ảnh và graph cũ giữ nguyên.');
      return;
    }
    final image = await _wait(
      FloorPlanAsset.validate(file.bytes, file.name, file.mime),
    );
    if (!mounted || !identical(draft, _draft)) return;
    if (draft.isLocal && draft.image != null && draft.nodes.isNotEmpty) {
      final accepted = await showWorkflowDialog<bool>(
        context: context,
        workflow: _owner,
        builder: (dialog) => AlertDialog(
          title: const Text('Thay ảnh của tầng này?'),
          content: const Text(
            'Graph giữ nguyên tọa độ, không tự căn chỉnh sang ảnh mới. Ảnh crop/sửa phối cảnh cần đối chiếu hoặc biến đổi tọa độ có kiểm soát trước khi dùng tuyến.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Giữ ảnh cũ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Thay ảnh, giữ tọa độ'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
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

  Future<void> _projectCloud({bool saveBeforeLeave = false}) async {
    if (_busy) return;
    _recoveryTimer?.cancel();
    LocalMapProject? copy;
    var prepared = false;
    await _read(() async {
      await _persistRecovery();
      copy = _draft?.isLocal == true
          ? await _wait(LocalMapProject.decode(_localProject.encode()))
          : null;
      prepared = true;
    }, operation: 'Đang giữ nguyên graph/ảnh để mở Server Draft…');
    if (!mounted || !_owner.current || !prepared) return;
    final snapshot = copy;
    final loaded = await Navigator.push<LocalMapProject>(
      context,
      MaterialPageRoute(
        builder: (_) => MapProjectCloudPage(
          project: snapshot,
          link: snapshot == null ? null : _projectCloudLinks[snapshot.id],
          onLinked: (link) {
            if (!_owner.current || !mounted) return;
            _projectCloudLinks[(link.document['content'] as Map)['id']
                    as String] =
                link;
          },
          onSaved: saveBeforeLeave
              ? () {
                  if (mounted && _owner.current) setState(() => _dirty = false);
                }
              : null,
          selectedNodeId: _selected == null ? null : _draft?.nodeIds[_selected],
          files: _files,
          api: _api,
        ),
      ),
    );
    if (loaded == null ||
        !mounted ||
        !_owner.current ||
        !await _discard() ||
        !mounted ||
        !_owner.current) {
      return;
    }
    setState(() {
      _project = loaded;
      _selectProjectFloor(loaded.floors.first);
      _server = null;
      _dirty = true;
      _localSaved = false;
    });
    _notice(
      'Đã mở bản sao draft server. Hãy xuất JSON để giữ backup local; chỉnh sửa không tự đổi snapshot Published.',
    );
  }

  Future<void> _aiAssistant() async {
    final draft = _draft;
    final image = draft?.image;
    if (_busy || draft == null || image == null) return;
    final projectId = draft.isLocal
        ? _localProject.id
        : 'server:${aiFloorKey(draft)}';
    late final AiGraphInput input;
    try {
      input = AiGraphInput.capture(draft, projectId: projectId);
    } on FormatException catch (e) {
      _notice(e.message, error: true);
      return;
    }
    final reviewed = await Navigator.push<AiGraphBatch>(
      context,
      MaterialPageRoute(
        builder: (_) => AiMapAssistantPage(
          image: image,
          floorName: draft.floor.name,
          graphInput: input,
          providerFactory: widget.aiProviderFactory,
        ),
      ),
    );
    if (!mounted || reviewed == null) return;
    if (!identical(draft, _draft)) {
      _notice('Tầng đã đổi. Không thêm đề xuất AI cũ.', error: true);
      return;
    }
    try {
      final currentProject = draft.isLocal
          ? _localProject.id
          : 'server:${aiFloorKey(draft)}';
      final applied = applyAiGraphBatch(
        draft,
        reviewed,
        projectId: currentProject,
      );
      setState(() {
        _edited();
        _localSaved = false;
        _preview = false;
        _previewRoute = null;
      });
      _notice(
        'Đã thêm ${applied.nodes.length} Node / ${applied.edges.length} Edge đã duyệt vào Draft. Chưa Save/Publish; lối đi/accessibility chưa xác minh.',
        action: SnackBarAction(
          label: 'Hoàn tác AI',
          onPressed: () {
            if (!mounted || !identical(draft, _draft)) return;
            try {
              final current = draft.isLocal
                  ? _localProject.id
                  : 'server:${aiFloorKey(draft)}';
              applied.undo(draft, projectId: current);
              setState(() {
                _edited();
                _localSaved = false;
              });
              _notice('Đã hoàn tác batch AI; graph trước đó được giữ nguyên.');
            } on FormatException catch (e) {
              _notice(e.message, error: true);
            }
          },
        ),
      );
    } on FormatException catch (e) {
      _notice(e.message, error: true);
    }
  }

  Future<void> _cleanupImage() async {
    final draft = _draft;
    if (_busy || draft == null || !draft.isLocal) return;
    if (draft.image == null) await _image();
    if (!mounted || !identical(draft, _draft) || draft.image == null) return;
    final before = draft.image;
    final source =
        draft.imageEdit?.transform.inverse() ?? ImageTransform.identity;
    final points = <CleanupPoint>[
      for (final n in draft.nodes)
        CleanupPoint(n.name, source.map(Offset(n.x, n.y))),
      for (final room in draft.places)
        for (final p in [room['label'], ...room['polygon'] as List])
          CleanupPoint(
            room['name'] as String,
            source.map(
              Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()),
            ),
          ),
    ];
    final result = await Navigator.push<CleanedFloorImage>(
      context,
      MaterialPageRoute(
        builder: (_) => FloorImageCleanupPage(
          original: draft.imageEdit?.original ?? draft.image!,
          floorName: draft.floor.name,
          files: _files,
          initial: draft.imageEdit?.settings,
          points: points,
        ),
      ),
    );
    if (result == null ||
        !mounted ||
        !identical(draft, _draft) ||
        !identical(before, draft.image)) {
      return;
    }
    try {
      draft.applyImageCleanup(result);
      setState(() {
        _dirty = true;
        _localSaved = false;
        _preview = false;
        _previewRoute = null;
      });
      _notice(
        'Đã áp dụng PNG và tọa độ trên ${draft.floor.name}. Ảnh gốc được giữ trong JSON; mét và Entrance không đổi.',
      );
    } on FormatException catch (e) {
      _notice(e.message, error: true);
    }
  }

  Future<void> _export() => _read(() async {
    final draft = _draft!;
    final project = _project;
    final useProject =
        draft.isLocal &&
        project != null &&
        (project.floors.length > 1 ||
            project.links.isNotEmpty ||
            _projectCloudLinks.containsKey(project.id));
    final bytes = useProject ? project.encode() : draft.encode();
    if (bytes.length >
        (useProject ? LocalMapProject.maxBytes : DraftMap.maxFileBytes)) {
      throw const FormatException(
        'Bản nháp vượt 18 MB. Hãy giảm kích thước ảnh/graph.',
      );
    }
    await _wait(
      _files.save(
        bytes,
        useProject
            ? 'waymark-project-v3.json'
            : 'waymark-floor-${draft.floor.id}-draft.json',
        'application/json',
      ),
    );
    if (draft.isLocal && mounted && identical(draft, _draft)) {
      setState(() {
        _dirty = false;
        _localSaved = true;
      });
    }
    _notice(
      !kIsWeb &&
              defaultTargetPlatform == TargetPlatform.android &&
              _files is PlatformDraftFiles
          ? 'Đã lưu ${useProject ? 'project v3' : 'JSON v2'} kèm ảnh vào vị trí bạn đã chọn. Chưa lưu server, chưa publish.'
          : 'Đã yêu cầu tải bản nháp kèm toàn bộ ảnh (Base64). Kiểm tra file tải xuống; chưa publish.',
    );
  });

  Future<void> _import() async {
    if (_draft?.isLocal ?? false) return _openLocal();
    if (!await _discard() || !mounted) return;
    await _read(() async {
      final previous = _draft!;
      final file = await _wait(_files.pick('.json', DraftMap.maxFileBytes));
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
      DraftServerMapper.content(restored, null);
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
    _draft?.layoutReviewed = false;
    _previewRoute = null;
    _refreshSheet?.call();
    _scheduleRecovery();
  }

  void _acceptServer(DraftMap draft) {
    _draft = draft;
    _selected = _dragNode = _routeStart = _routeEnd = null;
    _selectedEdge = null;
    _dragPoint = null;
    _preview = false;
    _previewRoute = null;
    _dirty = false;
  }

  Future<void> _loadServer() async {
    if (!await _discard() || !mounted) return;
    await _read(() async {
      final server = _server!;
      final loaded = await _wait(server.load());
      if (!mounted || !identical(server, _server)) return;
      _acceptServer(loaded);
      _notice(
        'Đã tải revision ${server.metadata!.version}, ảnh và graph. Bản nháp chưa publish.',
      );
    }, operation: 'Đang tải bản nháp và ảnh bằng JWT…');
  }

  Future<void> _saveServer() async {
    MapDraftApiException? conflict;
    await _read(() async {
      final server = _server!, draft = _draft!;
      try {
        await _wait(server.save(draft));
      } on MapDraftApiException catch (e) {
        if (e.versionConflict) conflict = e;
        rethrow;
      }
      if (!mounted || !identical(server, _server)) return;
      _dirty = false;
      _notice(
        'Server xác nhận lưu revision ${server.metadata!.version}. Chưa publish.',
      );
    }, operation: 'Đang lưu bản nháp và tham chiếu ảnh…');
    if (conflict == null || !mounted) return;
    await _offerConflict();
  }

  Future<void> _offerConflict() async {
    final action = await showWorkflowDialog<String>(
      context: context,
      workflow: _owner,
      builder: (dialog) => AlertDialog(
        title: const Text('Xung đột phiên bản'),
        content: const Text(
          'Bản local còn nguyên. Không tự ghi đè server. Có thể xuất backup trước khi tải bản mới.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, 'keep'),
            child: const Text('Giữ local'),
          ),
          TextButton(
            onPressed: !_files.supported
                ? null
                : () => Navigator.pop(dialog, 'export'),
            child: const Text('Xuất backup JSON'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, 'reload'),
            child: const Text('Tải bản mới'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'export') await _export();
    if (action == 'reload') await _loadServer();
  }

  Future<void> _history() async {
    final server = _server!;
    List<DraftRevision> revisions = [];
    var fetched = false;
    await _read(() async {
      revisions = await _wait(server.revisions());
      fetched = true;
    });
    if (!mounted || !fetched || !identical(server, _server)) return;
    var more = revisions.length == 50, loading = false;
    String? error;
    final version = await showWorkflowDialog<int>(
      context: context,
      workflow: _owner,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Lịch sử bản nháp'),
          content: SizedBox(
            width: 480,
            height: 330,
            child: ListView(
              children: [
                const Text(
                  'Khôi phục tạo revision mới. Không sửa lịch sử; chỉ trong tầng này.',
                ),
                if (server.metadata == null)
                  const Text(
                    'Tải draft trước để khôi phục an toàn với expectedVersion.',
                  ),
                for (final r in revisions)
                  ListTile(
                    title: Text('Revision ${r.version}'),
                    subtitle: Text(r.createdAt.toLocal().toString()),
                    trailing: TextButton(
                      onPressed: server.metadata == null || loading
                          ? null
                          : () => Navigator.pop(dialog, r.version),
                      child: const Text('Khôi phục'),
                    ),
                  ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
                if (more)
                  TextButton(
                    onPressed: loading
                        ? null
                        : () async {
                            update(() {
                              loading = true;
                              error = null;
                            });
                            try {
                              final page = await _wait(
                                server.revisions(
                                  beforeVersion: revisions.last.version,
                                ),
                              );
                              if (!context.mounted) return;
                              update(() {
                                revisions.addAll(page);
                                more = page.length == 50;
                              });
                            } catch (e) {
                              if (context.mounted) {
                                update(() => error = e.toString());
                              }
                            } finally {
                              if (context.mounted) {
                                update(() => loading = false);
                              }
                            }
                          },
                    child: const Text('Tải thêm'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(dialog),
              child: const Text('Đóng'),
            ),
          ],
        ),
      ),
    );
    if (version == null || !mounted || !await _discard() || !mounted) return;
    final confirmed = await showWorkflowDialog<bool>(
      context: context,
      workflow: _owner,
      builder: (dialog) => AlertDialog(
        title: Text('Khôi phục revision $version?'),
        content: const Text(
          'Server sẽ tạo revision mới. Bản local chỉ được thay khi tải graph và ảnh thành công.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Xác nhận khôi phục'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    var conflict = false;
    await _read(
      () async {
        late final DraftMap restored;
        try {
          restored = await _wait(server.restore(version));
        } on MapDraftApiException catch (e) {
          conflict = e.versionConflict;
          rethrow;
        }
        if (!mounted || !identical(server, _server)) return;
        _acceptServer(restored);
        _notice('Đã khôi phục thành revision ${server.metadata!.version}.');
      },
      operation: 'Đang khôi phục và tải ảnh; nếu tải lỗi, hãy Reload để đối chiếu server…',
    );
    if (conflict && mounted) await _offerConflict();
  }

  Future<void> _recoverImage() async {
    final server = _server!;
    List<DraftImageMetadata> images = [];
    var fetched = false;
    await _read(() async {
      images = await _wait(_draftsApi.images(server.floor.id));
      fetched = true;
    });
    if (!mounted || !fetched || !identical(server, _server)) return;
    var page = 1, more = images.length == 100, loading = false;
    String? error;
    final selected = await showWorkflowDialog<DraftImageMetadata>(
      context: context,
      workflow: _owner,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Ảnh đã upload — đúng tầng đang chọn'),
          content: SizedBox(
            width: 500,
            height: 320,
            child: ListView(
              children: [
                const Text(
                  'Dùng để đối chiếu upload chưa rõ kết quả. Chọn ảnh để xem trước; chưa gắn vào revision.',
                ),
                for (final image in images)
                  ListTile(
                    title: Text(
                      '${image.width} × ${image.height} • ${image.mime}',
                    ),
                    subtitle: Text(image.id),
                    onTap: loading ? null : () => Navigator.pop(dialog, image),
                  ),
                if (images.isEmpty)
                  const Text(
                    'Chưa có asset được xác nhận trong metadata. Nếu upload chưa rõ kết quả, chờ và tải lại danh sách.',
                  ),
                if (error != null) Text(error!),
                if (more)
                  TextButton(
                    onPressed: loading
                        ? null
                        : () async {
                            update(() {
                              loading = true;
                              error = null;
                            });
                            try {
                              final next = await _wait(
                                _draftsApi.images(
                                  server.floor.id,
                                  page: page + 1,
                                ),
                              );
                              if (!context.mounted) return;
                              update(() {
                                page++;
                                images.addAll(next);
                                more = next.length == 100;
                              });
                            } catch (e) {
                              if (context.mounted) {
                                update(() => error = e.toString());
                              }
                            } finally {
                              if (context.mounted) {
                                update(() => loading = false);
                              }
                            }
                          },
                    child: const Text('Tải thêm'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(dialog),
              child: const Text('Đóng'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    // Download for preview first; do not change the session binding on cancel.
    await _read(() async {
      final (bytes, mime) = await _wait(
        _draftsApi.download(server.floor.id, selected.id),
      );
      final preview = await _wait(
        FloorPlanAsset.validate(
          bytes,
          mime == 'image/png' ? 'preview.png' : 'preview.jpg',
          mime,
        ),
      );
      if (!mounted) return;
      final accepted = await showWorkflowDialog<bool>(
        context: context,
        workflow: _owner,
        builder: (dialog) => AlertDialog(
          title: const Text('Dùng ảnh này cho bản local?'),
          content: SizedBox(
            width: 500,
            height: 320,
            child: Image(image: preview.imageProvider, fit: BoxFit.contain),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Dùng ảnh này'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      final asset = await _wait(server.recoverImage(selected));
      if (!mounted || !identical(server, _server)) return;
      _draft!.image = asset;
      _edited();
      _preview = false;
      _notice(
        'Đã chọn asset đã có; cần Save Draft để gắn vào revision. Kiểm tra lại căn chỉnh graph.',
      );
    });
  }

  DraftNode? _nearNode(Offset point) {
    final nearby =
        _draft!.nodes
            .where((n) => _screenVector(Offset(n.x, n.y) - point).distance < 24)
            .toList()
          ..sort(
            (a, b) => _screenVector(Offset(a.x, a.y) - point).distance
                .compareTo(_screenVector(Offset(b.x, b.y) - point).distance),
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
    final accepted = await showWorkflowDialog<bool>(
      context: context,
      workflow: _owner,
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
      try {
        final id = draft.nodeIds[node.code];
        if (_project?.links.any((l) => l.fromNode == id || l.toNode == id) ==
            true) {
          throw const FormatException(
            'Node còn liên kết tầng. Hãy xóa liên kết đó trước.',
          );
        }
        draft.removeNode(node.code);
      } on FormatException catch (e) {
        _notice(e.message, error: true);
        return;
      }
      setState(() {
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
    if (_tool == 'Thêm phòng') {
      _roomDialog(point);
      return;
    }
    if (_tool == 'Thêm node') {
      _nodeDialog(point);
      return;
    }
    final selected = draft.nodes.where((n) => n.code == _selected).firstOrNull;
    if (_tool == 'Di chuyển' && selected != null) {
      setState(() {
        draft.putNode(selected.at(point.dx, point.dy), replace: true);
        _edited();
      });
      return;
    }
    final nearby = _nearNode(point);
    DraftEdge? hit;
    if (nearby == null) {
      final nodes = {for (final n in draft.nodes) n.code: n};
      for (final edge in draft.edges.reversed) {
        final a = _screenVector(
          Offset(nodes[edge.from]!.x, nodes[edge.from]!.y),
        );
        final b = _screenVector(Offset(nodes[edge.to]!.x, nodes[edge.to]!.y));
        final screenPoint = _screenVector(point);
        final delta = b - a;
        final t = delta.distanceSquared == 0
            ? 0.0
            : (((screenPoint - a).dx * delta.dx +
                          (screenPoint - a).dy * delta.dy) /
                      delta.distanceSquared)
                  .clamp(0.0, 1.0);
        if ((screenPoint - (a + delta * t)).distance < 16) {
          hit = edge;
          break;
        }
      }
    }
    setState(() {
      _selected = nearby?.code;
      _selectedEdge = hit;
    });
    if (nearby == null && hit == null) {
      for (final place in draft.places.reversed) {
        final label = place['label'] as Map;
        if ((Offset(
                      (label['x'] as num).toDouble(),
                      (label['y'] as num).toDouble(),
                    ) -
                    point)
                .distance <
            .08) {
          _roomDialog(point, existing: place);
          break;
        }
      }
    }
  }

  Future<void> _nodeDialog(Offset point, {DraftNode? existing}) async {
    final code = TextEditingController(
      text:
          existing?.code ??
          (_draft!.isLocal
              ? _nextLocalNodeCode()
              : 'DRAFT-${_draft!.siteId}-${_draft!.buildingId}-${_draft!.floor.id}-'),
    );
    final name = TextEditingController(text: existing?.name ?? '');
    final displayName = TextEditingController(
      text: existing?.displayName ?? '',
    );
    final waymark = TextEditingController(text: existing?.wayMarkCode ?? '');
    final landmarkNote = TextEditingController(
      text: existing?.landmarkNote ?? '',
    );
    var searchableAsDestination = existing?.searchableAsDestination ?? false;
    var type = existing?.type ?? 'Junction';
    final accepted = await showWorkflowDialog<bool>(
      context: context,
      workflow: _owner,
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
                  key: const Key('draft-node-name'),
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Tên node'),
                ),
                TextField(
                  key: const Key('draft-node-display-name'),
                  controller: displayName,
                  decoration: const InputDecoration(
                    labelText: 'Tên hiển thị (tùy chọn)',
                  ),
                ),
                SwitchListTile(
                  key: const Key('draft-node-searchable-destination'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Đánh dấu điểm đến trong tìm kiếm'),
                  subtitle: Text(
                    searchableAsDestination
                        ? 'Node này sẽ xuất hiện trong Search sau khi lưu và xuất bản.'
                        : 'Chưa xuất hiện trong Search, kể cả khi loại node là Destination.',
                  ),
                  value: searchableAsDestination,
                  onChanged: (value) =>
                      update(() => searchableAsDestination = value),
                ),
                TextField(
                  key: const Key('draft-node-landmark-note'),
                  controller: landmarkNote,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú mốc nhận biết (tùy chọn)',
                  ),
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
        if (linkCode.isNotEmpty && !draft.isLocal) {
          final location = await _wait(_api.getMapLocation(linkCode));
          if (location.node == null ||
              existing?.sourceNodeId == null ||
              (location.node!.id != existing?.sourceNodeId ||
                  location.node!.floorId != draft.floor.id)) {
            throw const FormatException(
              'QR phải liên kết đúng node nguồn có sẵn trên tầng này. Bản nháp không tạo hoặc thay đổi liên kết QR production.',
            );
          }
        }
        if (!mounted) return;
        final id = existing == null ? null : draft.nodeIds[existing.code];
        if (existing != null &&
            type != existing.type &&
            _project?.links.any((l) => l.fromNode == id || l.toNode == id) ==
                true) {
          throw const FormatException(
            'Hãy xóa liên kết tầng trước khi đổi loại node.',
          );
        }
        draft.putNode(
          DraftNode(
            code.text.trim(),
            name.text.trim(),
            point.dx,
            point.dy,
            type,
            displayName: displayName.text.trim().isEmpty
                ? null
                : displayName.text.trim(),
            searchableAsDestination: searchableAsDestination,
            landmarkNote: landmarkNote.text.trim().isEmpty
                ? null
                : landmarkNote.text.trim(),
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
    displayName.dispose();
    waymark.dispose();
    landmarkNote.dispose();
  }

  Future<void> _editSelectedDestinationNode() async {
    final selected = _draft?.nodes
        .where((node) => node.code == _selected)
        .firstOrNull;
    if (selected == null) {
      _notice('Chọn một Node trước khi đánh dấu điểm đến.', error: true);
      return;
    }
    await _nodeDialog(Offset(selected.x, selected.y), existing: selected);
  }

  String _edgeNodeLabel(DraftNode node, int index) {
    return node.listLabel(index);
  }

  Future<void> _edgeDialog({DraftEdge? existing}) async {
    final draft = _draft!;
    String? from = existing?.from ?? _selected, to = existing?.to;
    var type = existing?.type ?? 'Corridor';
    var twoWay = false;
    String? error;
    final meters = TextEditingController(
      text: existing == null || !existing.isMeasured
          ? ''
          : existing.meters.toString(),
    );
    DraftEdge candidate() => DraftEdge(
      from ?? '',
      to ?? '',
      meters.text.trim().isEmpty
          ? 0
          : double.tryParse(meters.text.trim().replaceAll(',', '.')) ??
                double.nan,
      type,
      isActive: existing?.isActive ?? true,
      isMeasured: meters.text.trim().isNotEmpty,
    );
    DraftEdge reverse(DraftEdge edge) => DraftEdge(
      edge.to,
      edge.from,
      edge.meters,
      edge.type,
      isActive: edge.isActive,
      isMeasured: edge.isMeasured,
    );
    void validate(DraftEdge edge) {
      if (from == null || to == null) {
        throw const FormatException('Chọn điểm đầu và điểm cuối.');
      }
      if (from == to) {
        throw const FormatException('Điểm đầu và điểm cuối phải khác nhau.');
      }
      if (existing == null && draft.edges.length + (twoWay ? 2 : 1) > 10000) {
        throw const FormatException('Bản nháp tối đa 10000 cạnh.');
      }
      draft.checkEdge(edge, replacing: existing);
      if (twoWay) draft.checkEdge(reverse(edge));
    }

    final accepted = await showWorkflowDialog<bool>(
      context: context,
      workflow: _owner,
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
                    key: ValueKey(
                      'draft-edge-${field == 'Từ node' ? 'from' : 'to'}',
                    ),
                    isExpanded: true,
                    initialValue: field == 'Từ node' ? from : to,
                    decoration: InputDecoration(labelText: field),
                    items: [
                      for (final (index, node) in draft.nodes.indexed)
                        DropdownMenuItem(
                          value: node.code,
                          child: SizedBox(
                            width: double.infinity,
                            child: Text(
                              _edgeNodeLabel(node, index),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
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
                  key: const Key('draft-edge-meters'),
                  controller: meters,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Khoảng cách mét (để trống nếu chưa đo)',
                  ),
                ),
                const Text(
                  'Khoảng cách phải đo thực tế, không tính từ ảnh. Chưa đo: chỉ lưu nháp, chưa dùng dẫn đường.',
                ),
                if (existing == null)
                  CheckboxListTile(
                    key: const Key('draft-edge-bidirectional'),
                    contentPadding: EdgeInsets.zero,
                    value: twoWay,
                    title: const Text('Đi được cả hai chiều'),
                    subtitle: const Text(
                      'Tạo 2 cạnh ngược hướng, cùng khoảng cách. Chỉ chọn khi đã kiểm tra.',
                    ),
                    onChanged: (value) => update(() => twoWay = value ?? false),
                  ),
                if (error != null)
                  Text(
                    error!,
                    key: const Key('draft-edge-error'),
                    style: const TextStyle(color: Colors.red),
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
              key: const Key('draft-edge-save'),
              onPressed: () {
                try {
                  validate(candidate());
                  Navigator.pop(dialog, true);
                } on FormatException catch (e) {
                  update(() => error = e.message);
                }
              },
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
        if (!identical(draft, _draft)) {
          throw const FormatException(
            'Tầng đã đổi. Hãy mở lại cạnh cần chỉnh.',
          );
        }
        final edge = candidate();
        validate(edge);
        if (existing == null) {
          draft.addEdge(edge);
          if (twoWay) draft.addEdge(reverse(edge));
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
        OutlinedButton(
          onPressed: _busy ? null : _projectCloud,
          child: const Text('Server / Publish / QR'),
        ),
        OutlinedButton.icon(
          onPressed: _busy || draft.image == null ? null : _aiAssistant,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('AI đề xuất Node / Edge'),
        ),
        SizedBox(
          height: 220,
          child: ListView(
            children: [
              for (final (index, node) in draft.nodes.indexed)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _nodeIcon(node),
                    color: _nodeColor(node),
                    size: 20,
                  ),
                  selected: node.code == _selected,
                  title: Text(node.listLabel(index)),
                  subtitle: Text(node.code),
                  onTap: _busy || _preview
                      ? null
                      : () => setState(() {
                          _selected = node.code;
                          _selectedEdge = null;
                          _refreshSheet?.call();
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
    height: MediaQuery.sizeOf(context).width < 600 ? 390 : 480,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.secondary,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 8 : 24,
        ),
        child: FloorPlanCanvas(
          key: ValueKey(
            'draft-canvas-${draft.localWorkspaceId ?? draft.floor.id}',
          ),
          image: draft.image?.imageProvider,
          onViewMetrics: (size, scale) {
            _sceneSize = size;
            _viewScale = scale;
          },
          painterBuilder: (scale) => DraftMapPainter(
            draft,
            _selected,
            selectedEdge: _selectedEdge,
            preview: _preview,
            route: _previewRoute,
            movingCode: _dragNode,
            movingPoint: _dragPoint,
            showLabels: _showMapLabels,
            viewScale: scale,
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
                        _refreshSheet?.call();
                      }),
                child: Text(
                  '${e.from} → ${e.to} • ${e.isMeasured ? '${e.meters} m' : 'chưa đo'}',
                ),
              ),
          ] else if (edge != null) ...[
            Text(
              '${edge.from} → ${edge.to}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '${edge.type} • ${edge.isMeasured ? '${edge.meters} m' : 'chưa đo'} • ${edge.isActive ? 'active' : 'inactive'}',
            ),
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
            'Chỉ sửa bản nháp. Save Draft lưu revision riêng, không cập nhật graph production hoặc WayMark.',
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
                  key: const Key('add-draft-edge'),
                  onPressed: _busy || draft.nodes.length < 2
                      ? null
                      : () => _edgeDialog(),
                  child: const Text('Thêm cạnh có hướng'),
                ),
              if (!_preview)
                OutlinedButton(
                  key: const Key('mark-selected-node-destination'),
                  onPressed: _busy || _selected == null
                      ? null
                      : _editSelectedDestinationNode,
                  child: const Text('Đánh dấu điểm đến'),
                ),
            ],
          ),
          if (!_preview)
            ExpansionTile(
              key: const Key('legacy-room-tools'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Nâng cao / Tương thích cũ'),
              subtitle: const Text('Công cụ Room/Place thủ công'),
              children: [_roomPanel(draft)],
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
              draft.graphSummary,
              key: const Key('draft-graph-summary'),
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
          _roomPanel(draft),
          const SizedBox(height: 12),
          canvas,
          if (!_preview) _properties(draft),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    _exitGuard.setDirty(_dirty || _busy);
    if (!_owner.current) return _recoveryScreen();
    return mapUiTheme(
      context,
      PopScope(
        canPop: !_dirty && !_busy,
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
          title: 'Map Builder — bản nháp',
          scaffoldKey: _scaffoldKey,
          beforeNavigate: _beforeNavigate,
          child: MediaQuery.sizeOf(context).width < 600
              ? _mobileBody()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'BẢN NHÁP — chưa duyệt cho bệnh nhân. Save/Load dùng kho draft riêng; không xuất bản hoặc sửa graph production.',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (!_files.supported)
                        const Text(
                          'Chọn ảnh và nhập/xuất file hiện hỗ trợ trên Web. Canvas và sửa bản nháp dùng được trên Android.',
                        ),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: _busy ? null : _newLocal,
                            child: const Text('Bản đồ cục bộ mới'),
                          ),
                          OutlinedButton(
                            onPressed: _busy || !_files.supported
                                ? null
                                : _openLocal,
                            child: const Text('Mở JSON cục bộ'),
                          ),
                        ],
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
                                  child: Text(
                                    _message!,
                                    key: const Key('draft-message'),
                                  ),
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
                                          if (value != null) {
                                            _choose(level, value);
                                          }
                                        },
                                ),
                              ),
                            ),
                          if (_sites.isEmpty && !_busy)
                            TextButton(
                              onPressed: () => _read(() async {
                                _sites = await _wait(_api.getSites());
                              }),
                              child: const Text('Tải lại Site'),
                            ),
                        ],
                      ),
                      if (_draft case final draft?) ...[
                        const SizedBox(height: 12),
                        _panel(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _dirty
                                    ? 'Có thay đổi local chưa lưu server'
                                    : _server?.savedAt == null
                                    ? 'Bản local — chưa xác nhận lưu server'
                                    : 'Đã xác nhận bản nháp server',
                                key: const Key('draft-save-state'),
                              ),
                              if (_server?.metadata case final metadata?)
                                Text(
                                  'Revision ${metadata.version} • Site ${metadata.siteId} / Building ${metadata.buildingId} / Floor ${metadata.floorId}',
                                ),
                              if (_server?.savedAt case final saved?)
                                Text(
                                  'Server xác nhận cập nhật: ${saved.toLocal()}',
                                ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (!draft.isLocal)
                                    FilledButton.icon(
                                      key: const Key('save-server-draft'),
                                      onPressed: _busy ? null : _saveServer,
                                      icon: const Icon(
                                        Icons.cloud_upload_outlined,
                                      ),
                                      label: const Text('Save Draft'),
                                    ),
                                  if (!draft.isLocal)
                                    OutlinedButton(
                                      key: const Key('load-server-draft'),
                                      onPressed: _busy ? null : _loadServer,
                                      child: const Text('Load / Reload Draft'),
                                    ),
                                  if (!draft.isLocal)
                                    OutlinedButton(
                                      key: const Key('draft-revisions'),
                                      onPressed: _busy ? null : _history,
                                      child: const Text('Lịch sử phiên bản'),
                                    ),
                                  if (!draft.isLocal)
                                    TextButton(
                                      key: const Key('draft-server-images'),
                                      onPressed: _busy ? null : _recoverImage,
                                      child: const Text('Ảnh đã upload'),
                                    ),
                                ],
                              ),
                              Text(
                                'Room/Place: ${draft.places.length} • chuyển tầng: ${draft.transitions.length} (bảo toàn tham chiếu, chưa có công cụ sửa).',
                              ),
                              for (final place in draft.places)
                                Text(
                                  '${place['name']} (${place['placeCode']}) • ${(place['entranceNodeIds'] as List).length} cửa vào',
                                ),
                            ],
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              key: const Key('export-draft'),
                              onPressed: _busy || !_files.supported
                                  ? null
                                  : _export,
                              child: const Text('Lưu bản nháp JSON + ảnh'),
                            ),
                            OutlinedButton(
                              key: const Key('import-draft'),
                              onPressed: _busy || !_files.supported
                                  ? null
                                  : _import,
                              child: const Text('Mở bản nháp JSON'),
                            ),
                          ],
                        ),
                        _workspace(draft),
                      ] else
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Chọn Site, Building và Floor từ dữ liệu API.',
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

IconData _nodeIcon(DraftNode node) => node.wayMarkCode != null
    ? Icons.qr_code
    : node.searchableAsDestination
    ? Icons.flag_outlined
    : switch (node.type) {
        'Destination' => Icons.flag_outlined,
        'Elevator' => Icons.elevator_outlined,
        'Stairs' => Icons.stairs_outlined,
        'Entrance' => Icons.login,
        _ => Icons.circle_outlined,
      };
Color _nodeColor(DraftNode node) => node.wayMarkCode != null
    ? Colors.cyan.shade700
    : node.searchableAsDestination &&
          !['Stairs', 'Elevator'].contains(node.type)
    ? AppColors.accent
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
    this.showLabels = false,
    this.viewScale = 1,
  });
  final DraftMap draft;
  final String? selected, movingCode;
  final DraftEdge? selectedEdge;
  final bool preview;
  final DraftRoute? route;
  final Offset? movingPoint;
  final bool showLabels;
  final double viewScale;
  List<String> get visibleRoomNames => showLabels
      ? draft.places.map((p) => p['name'] as String).toList()
      : const [];
  String nodeLabel(DraftNode node) => showLabels || node.code == selected
      ? node.listLabel(draft.nodes.indexOf(node))
      : node.badge(draft.nodes.indexOf(node));
  List<String> get visibleNodeCodes => preview
      ? route?.nodeCodes ?? []
      : draft.nodes.map((n) => n.code).toList();
  List<DraftEdge> get visibleEdges =>
      preview ? route?.edges ?? [] : draft.edges;

  @override
  void paint(Canvas canvas, Size size) {
    // Enlarge normalized geometry while compensating only its drawing units.
    // The viewer still transforms node centers with the image; strokes, markers
    // and text remain in screen logical pixels. No source coordinates change.
    size = beginScreenSizedMapPaint(canvas, size, viewScale);
    final nodes = {for (final n in draft.nodes) n.code: n};
    Offset at(DraftNode n) {
      final point = n.code == movingCode && movingPoint != null
          ? movingPoint!
          : Offset(n.x, n.y);
      return Offset(point.dx * size.width, point.dy * size.height);
    }

    for (final place
        in showLabels ? draft.places : const <Map<String, dynamic>>[]) {
      final p = place['label'] as Map;
      final point = Offset(
        (p['x'] as num).toDouble() * size.width,
        (p['y'] as num).toDouble() * size.height,
      );
      final polygon = place['polygon'] as List;
      if (polygon.length >= 3) {
        final path = Path();
        for (var i = 0; i < polygon.length; i++) {
          final v = polygon[i] as Map;
          final x = (v['x'] as num).toDouble() * size.width,
              y = (v['y'] as num).toDouble() * size.height;
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(
          path..close(),
          Paint()..color = const Color(0x1806b6d4),
        );
      }
      final label = TextPainter(
        text: TextSpan(
          text: '${place['name']}',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
            backgroundColor: Color(0xefffffff),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 120);
      label.paint(canvas, point);
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
      final destination = n.searchableAsDestination || n.type == 'Destination';
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
          text: nodeLabel(n),
          style: const TextStyle(
            color: AppColors.primary,
            fontFamily: 'Inter',
            fontSize: 11,
            backgroundColor: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 130);
      label.paint(canvas, point + const Offset(12, 12));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DraftMapPainter oldDelegate) => true;
}
