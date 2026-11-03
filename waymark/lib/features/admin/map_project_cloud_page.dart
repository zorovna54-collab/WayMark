import 'dart:typed_data';

import '../../services/auth_session.dart';
import '../../services/auth_api_service.dart';
import '../auth/workflow_recovery.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals, kDebugMode;
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/map_draft_api_service.dart';
import '../../services/published_map_api_service.dart';
import '../../services/waymark_api_service.dart';
import '../search/local_map_search_page.dart';
import 'draft_file_gateway.dart';
import 'local_map_project.dart';
import 'floor_plan_asset.dart';
import 'project_publish_state.dart';

class ProjectCloudLink {
  ProjectCloudLink(this.document, LocalMapProject project)
    : images = {for (final f in project.floors) f.localWorkspaceId!: f.image};
  final Map<String, dynamic> document;
  final Map<String, FloorPlanAsset?> images;
}

Future<Uint8List> nodeQrPng(String payload) async {
  if (publicQrToken(payload) == null) {
    throw const FormatException('QR payload không hợp lệ.');
  }
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 640, 640),
    Paint()..color = Colors.white,
  );
  canvas.translate(64, 64);
  QrPainter(
    data: payload,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
  ).paint(canvas, const Size(512, 512));
  final picture = recorder.endRecording(),
      image = await picture.toImage(640, 640);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw const FormatException('Không render được QR PNG.');
    return Uint8List.fromList(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// A detached copy: network errors, canceled dialogs and loads cannot replace the editor draft.
class MapProjectCloudPage extends StatefulWidget {
  const MapProjectCloudPage({
    super.key,
    this.project,
    this.selectedNodeId,
    this.files,
    this.api,
    this.maps,
    this.images,
    this.link,
    this.onLinked,
    this.onSaved,
  });
  final LocalMapProject? project;
  final String? selectedNodeId;
  final DraftFileGateway? files;
  final WayMarkApiService? api;
  final PublishedMapApiService? maps;
  final MapDraftApiService? images;
  final ProjectCloudLink? link;
  final ValueChanged<ProjectCloudLink>? onLinked;
  final VoidCallback? onSaved;
  @override
  State<MapProjectCloudPage> createState() => _MapProjectCloudPageState();
}

class _MapProjectCloudPageState extends State<MapProjectCloudPage> {
  final _owner = OwnerWorkflow();
  void _ownerChanged() {
    if (mounted) setState(() {});
  }

  Future<T> _wait<T>(Future<T> future) => _owner.wait(future);
  late LocalMapProject? _project = widget.project;
  late final _api = widget.api ?? WayMarkApiService();
  late final _maps = widget.maps ?? PublishedMapApiService(client: _api.client);
  late final _images = widget.images ?? MapDraftApiService(client: _api.client);
  late final _files = widget.files ?? const PlatformDraftFiles();
  final _name = TextEditingController(text: 'Bản đồ của tôi');
  List<Map<String, dynamic>> _saved = [],
      _sites = [],
      _buildings = [],
      _floors = [],
      _qrs = [];
  final _bindings = <String, int>{}, _assets = <String, String>{};
  final _uncertainImages = <String>{};
  Map<String, dynamic>? _document;
  int? _site, _building;
  late String? _node = widget.selectedNodeId;
  bool _busy = false, _uncertainSave = false;
  bool _savedVerified = false;
  String _stage = 'Mở màn hình';
  String? _failureCode, _readinessError;
  int? _editBaseVersion;
  List<Map<String, dynamic>> _checks = [];
  String _message =
      'Lưu draft → chọn node xuất phát → tạo QR cho phiên bản đã lưu → xuất bản → tải QR cho Visitor. Bản local chưa công khai.';
  List<SavedQrNode> get _savedNodes => savedQrNodes(_document);
  String? get _qrBlocked => _busy
      ? 'Đang xử lý yêu cầu; vui lòng chờ.'
      : !_savedVerified
      ? 'Chưa đọc xác nhận graph từ Server. Bấm Đọc lại trạng thái server.'
      : _savedNodes.isEmpty
      ? 'Chưa có Node được lưu trên Server. Workspace trống không phải graph đã lưu.'
      : !_savedNodes.any((n) => n.id == _node)
      ? 'Chọn một Node đã lưu ở danh sách bên dưới.'
      : null;
  bool get _localChanged {
    final p = _project, doc = _document;
    if (p == null || doc == null) return false;
    if (p.floors.any(
      (f) => f.image != null && !_assets.containsKey(f.localWorkspaceId),
    )) {
      return true;
    }
    try {
      return _name.text.trim() != doc['name'] ||
          !sameProjectGraph(
            PublishedMapApiService.content(p, _bindings, _assets),
            Map<String, dynamic>.from(doc['content'] as Map),
          );
    } on FormatException {
      return true;
    }
  }

  String? get _publishBlocked {
    if (_busy) return 'Đang xử lý yêu cầu; vui lòng chờ.';
    if (!_savedVerified) return 'Chưa đọc xác nhận bản đã lưu từ Server.';
    if (_document?['canPublish'] == null) {
      return 'Backend chưa trả khả năng xuất bản. Restart API bản mới rồi đọc lại trạng thái.';
    }
    if (_document?['canPublish'] != true) {
      return 'Chưa có quyền xuất bản bản đồ này.';
    }
    if (_readinessError != null) return _readinessError;
    for (final check in _checks) {
      if (check['passed'] != true) return check['message'] as String;
    }
    if (!_qrs.any(
      (q) =>
          q['isActive'] == true && q['draftVersion'] == _document?['version'],
    )) {
      return 'Tạo QR cho ít nhất một node xuất phát của phiên bản đã lưu trước khi xuất bản.';
    }
    return null;
  }

  Future<void> _refreshSaved() async {
    if (_document == null) return;
    _stage = 'GET xác nhận graph server';
    _savedVerified = false;
    _checks = [];
    _readinessError =
        'Chưa xác minh đầy đủ điều kiện Publish. Đọc lại trạng thái server.';
    final doc = await _wait(_maps.get(_document!['id'] as String));
    if (draftGuid(doc['id']) != draftGuid(_document!['id']) ||
        doc['version'] is! int ||
        doc['content'] is! Map) {
      throw const FormatException(
        'Phản hồi bản đã lưu không đúng map/version. Bản local được giữ.',
      );
    }
    if (_editBaseVersion != null && _editBaseVersion != doc['version']) {
      _uncertainSave = true;
    }
    _document = doc;
    _savedVerified = true;
    if (!_savedNodes.any((n) => n.id == _node)) _node = null;
    _stage = 'GET QR và kiểm tra Publish';
    _qrs = await _wait(_maps.qrs(doc['id'] as String));
    try {
      final status = await _wait(_maps.readiness(doc['id'] as String));
      if (status['mapId'] != doc['id'] || status['version'] != doc['version']) {
        throw const FormatException(
          'Bản server thay đổi trong lúc kiểm tra. Đọc lại trạng thái.',
        );
      }
      final checks = (status['checks'] as List).cast<Map<String, dynamic>>();
      if (checks.isEmpty ||
          checks.any(
            (c) =>
                c['passed'] is! bool ||
                c['message'] is! String ||
                c['code'] is! String,
          )) {
        throw const FormatException(
          'Kiểm tra Publish chưa đầy đủ. Kiểm tra phiên bản API.',
        );
      }
      _checks = checks;
      _readinessError = null;
    } on MapDraftApiException catch (e) {
      _readinessError = e.status == 404
          ? 'Backend chưa có kiểm tra hotfix QR-P0. Restart API bản mới rồi Đọc lại trạng thái server.'
          : e.toString();
    }
  }

  Future<void> _createStartQr() async {
    final node = _savedNodes.where((n) => n.id == _node).firstOrNull;
    if (node == null) return;
    Map<String, dynamic>? created;
    await _run(() async {
      created = await _wait(
        _maps.createQr(
          _document!['id'] as String,
          _document!['version'] as int,
          node.floorKey,
          node.id,
        ),
      );
      _qrs = await _wait(_maps.qrs(_document!['id'] as String));
      await _refreshSaved();
      _message = 'Đã chuẩn bị QR khởi đầu cho bản đã lưu. Tiếp theo: Xuất bản snapshot; QR chưa publish chưa định vị được Visitor.';
    });
    if (created != null && mounted && _owner.current) {
      await _showQrSafe(created!);
    }
  }

  @override
  void initState() {
    super.initState();
    _owner.addListener(_ownerChanged);
    final link = widget.link;
    _node = _node == null ? null : draftGuid(_node);
    if (link != null && _project != null) {
      _document = link.document;
      _editBaseVersion = _document!['version'] as int;
      _name.text = _document!['name'] as String;
      _site = _document!['siteId'] as int;
      _building = _document!['buildingId'] as int;
      for (final f in (_document!['content'] as Map)['floors'] as List) {
        final key = f['id'] as String;
        _bindings[key] = f['floorId'] as int;
        final current = _project!.floors
            .where((x) => x.localWorkspaceId == key)
            .firstOrNull
            ?.image;
        final previous = link.images[key];
        if (current != null &&
            previous != null &&
            current.mime == previous.mime &&
            listEquals(current.bytes, previous.bytes)) {
          final asset = f['content']['imageAssetId'];
          if (asset != null) _assets[key] = asset as String;
        }
      }
    }
    _run(() async {
      _saved = await _wait(_maps.list());
      _sites = await _wait(_api.getSites());
      if (_building != null) _floors = await _wait(_api.getFloors(_building!));
      if (_document != null) {
        _qrs = await _wait(_maps.qrs(_document!['id'] as String));
      }
      await _refreshSaved();
    });
  }

  @override
  void dispose() {
    _owner.removeListener(_ownerChanged);
    _owner.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy || !_owner.current) return;
    setState(() {
      _busy = true;
      _failureCode = null;
    });
    try {
      await _owner.run(task);
    } catch (e) {
      if (mounted) {
        final code = e is MapDraftApiException ? e.code : null;
        _failureCode = code != null && RegExp(r'^[a-z_]{1,80}$').hasMatch(code)
            ? code
            : null;
        _message =
            e is MapDraftApiException ||
                e is WayMarkApiException ||
                e is FormatException
            ? '$_stage: $e'
            : 'Không xử lý được bản đồ server. Bản local giữ nguyên.';
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _run(() async {
    final p = _project;
    if (p == null) {
      throw const FormatException('Hãy tạo/mở bản đồ local trước.');
    }
    if (_uncertainSave) {
      throw const FormatException(
        'Lần lưu trước chưa rõ kết quả. Tải lại danh sách và mở bản server; không ghi đè tự động.',
      );
    }
    _stage = 'Chuẩn bị lưu graph/ảnh';
    final storage = _checks
        .where(
          (c) =>
              c['passed'] == false &&
              [
                'image_storage_unavailable',
                'image_storage_configuration',
              ].contains(c['code']),
        )
        .firstOrNull;
    if (storage != null &&
        p.floors.any(
          (f) => f.image != null && !_assets.containsKey(f.localWorkspaceId),
        )) {
      throw FormatException(storage['message'] as String);
    }
    // Validate the entire graph/mapping before uploading any bytes.
    if (_document?['publicationKind'] == 'PersonalDemo') {
      for (final f in p.floors.where(
        (f) => !_bindings.containsKey(f.localWorkspaceId),
      )) {
        final added = await _wait(
          _maps.addPersonalFloor(
            _document!['id'] as String,
            f.floor.name,
            f.floor.floorCode,
          ),
        );
        _bindings[f.localWorkspaceId!] = added['id'] as int;
      }
      _floors = await _wait(_api.getFloors(_building!));
    }
    PublishedMapApiService.content(p, _bindings, _assets);
    if (p.floors.map((f) => _bindings[f.localWorkspaceId]).toSet().length !=
        p.floors.length) {
      throw const FormatException(
        'Mỗi tầng local cần ghép với một tầng server khác nhau.',
      );
    }
    for (final f in p.floors) {
      final key = f.localWorkspaceId!, floorId = _bindings[f.localWorkspaceId]!;
      if (_uncertainImages.contains(key)) {
        throw const FormatException(
          'Upload chưa rõ kết quả. Dùng Đối chiếu ảnh để chọn lại asset trước khi lưu.',
        );
      }
      if (f.image == null || _assets.containsKey(key)) continue;
      try {
        _stage = 'Chuẩn bị ảnh tầng ${f.floor.name}';
        try {
          await _wait(_images.metadata(floorId));
        } on MapDraftApiException catch (e) {
          if (e.status != 404 || e.code != 'draft_resource_not_found') rethrow;
          await _wait(
            _images.create(floorId, {
              'schemaVersion': 1,
              'imageAssetId': null,
              'nodes': [],
              'edges': [],
              'places': [],
              'transitions': [],
            }),
          );
        }
        _stage = 'Upload ảnh tầng ${f.floor.name}';
        final asset = await _wait(
          _images.upload(floorId, f.image!.bytes, f.image!.mime),
        );
        if (asset.width != f.image!.width || asset.height != f.image!.height) {
          throw const FormatException(
            'Kích thước ảnh server khác ảnh local. Không lưu graph lệch tọa độ.',
          );
        }
        _assets[key] = asset.id;
      } on MapDraftApiException catch (e) {
        if (e.uncertain) _uncertainImages.add(key);
        rethrow;
      }
    }
    try {
      _stage = 'PUT graph project';
      _document = await _wait(
        _maps.save(
          _name.text.trim(),
          PublishedMapApiService.content(p, _bindings, _assets),
          id: _document?['id'] as String?,
          version: _document?['version'] as int?,
        ),
      );
      _editBaseVersion = _document!['version'] as int;
      await _refreshSaved();
      if (_localChanged) {
        _uncertainSave = true;
        throw const FormatException(
          'GET server chưa khớp ảnh/graph vừa gửi. Không xác nhận đã lưu; bản local giữ nguyên.',
        );
      }
    } on MapDraftApiException catch (e) {
      if (e.uncertain) _uncertainSave = true;
      rethrow;
    }
    _message =
        'Đã lưu và GET xác nhận draft v${_document!['version']} • ${_savedNodes.length} node. Chưa publish; Visitor chưa đọc được.';
    widget.onLinked?.call(ProjectCloudLink(_document!, p));
    widget.onSaved?.call();
    _saved = await _wait(_maps.list());
    _qrs = await _wait(_maps.qrs(_document!['id'] as String));
  });
  Future<void> _load(String id) async {
    // Reading this workspace must never swap the Builder copy for an empty
    // onboarding document. Only an explicit *different project* load can replace it.
    Map<String, dynamic>? fetched;
    await _run(() async {
      fetched = await _wait(_maps.get(id));
    });
    if (fetched == null || !mounted || !_owner.current) return;
    final docToLoad = fetched!;
    final sameProject =
        _project != null &&
        draftGuid(docToLoad['content']['id']) == draftGuid(_project!.id);
    if (!sameProject && _project != null) {
      final confirm = await showWorkflowDialog<bool>(
        context: context,
        workflow: _owner,
        builder: (c) => AlertDialog(
          scrollable: true,
          title: const Text('Thay bằng bản đồ server khác?'),
          content: const Text(
            'Đây là project khác. Chỉ thay bản sao trong màn hình Cloud sau xác nhận; graph trong Builder vẫn giữ nguyên. Xuất JSON trước nếu cần giữ bản local.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Giữ bản local'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Tải bản server'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted || !_owner.current) return;
    }
    await _run(() async {
      final doc = docToLoad;
      final p = sameProject
          ? _project!
          : await _wait(_maps.project(doc, public: false));
      // A same-project read refreshes metadata/bindings only. It does not load
      // server graph or image over unsaved local content.
      // Assign only after all floor graphs and images succeeded.
      _project = p;
      _document = doc;
      if (!sameProject) _name.text = doc['name'] as String;
      final previousAssets = Map<String, String>.from(_assets);
      _bindings.clear();
      _assets.clear();
      if (!sameProject) {
        _uncertainImages.clear();
        _uncertainSave = false;
      }
      _node = null;
      if (!sameProject || _editBaseVersion == null) {
        _editBaseVersion = doc['version'] as int;
      }
      for (final f in (doc['content'] as Map)['floors'] as List) {
        _bindings[f['id'] as String] = f['floorId'] as int;
        final asset = f['content']['imageAssetId'];
        final local = p.floors
            .where((x) => draftGuid(x.localWorkspaceId) == draftGuid(f['id']))
            .firstOrNull;
        final previousImage = widget.link?.images[f['id']];
        if (asset != null &&
            (!sameProject ||
                previousAssets[f['id']] == asset ||
                (local?.image != null &&
                    previousImage != null &&
                    listEquals(local!.image!.bytes, previousImage.bytes) &&
                    local.image!.mime == previousImage.mime))) {
          _assets[f['id'] as String] = asset as String;
        }
      }
      _qrs = await _wait(_maps.qrs(id));
      _site = doc['siteId'] as int;
      _building = doc['buildingId'] as int;
      _floors = await _wait(_api.getFloors(_building!));
      await _refreshSaved();
      widget.onLinked?.call(ProjectCloudLink(doc, p));
      _message = sameProject
          ? 'Đã đọc workspace v${doc['version']}; giữ nguyên graph/ảnh local từ Builder. Bấm Lưu để đồng bộ, chưa ghi server.'
          : 'Đã tải đầy đủ draft v${doc['version']}. Bấm Mở trong Builder để thay bản đang chỉnh sau khi xác nhận.';
    });
  }

  Future<void> _reconcile(String key) => _run(() async {
    final id = _bindings[key];
    if (id == null) throw const FormatException('Chọn tầng server trước.');
    final assets = await _wait(_images.images(id));
    if (!mounted || !_owner.current) return;
    final selected = await showWorkflowDialog<DraftImageMetadata>(
      context: context,
      workflow: _owner,
      builder: (c) => SimpleDialog(
        title: const Text('Ảnh đã upload • chọn để đối chiếu'),
        children: [
          for (final a in assets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, a),
              child: Text(
                '${a.id} • ${a.width} × ${a.height} • ${a.byteLength} bytes',
              ),
            ),
        ],
      ),
    );
    if (selected == null) return;
    final local = _project!.floors
        .singleWhere((f) => f.localWorkspaceId == key)
        .image;
    if (local == null ||
        local.width != selected.width ||
        local.height != selected.height) {
      throw const FormatException('Kích thước không khớp ảnh local.');
    }
    final (bytes, _) = await _wait(_images.download(id, selected.id));
    if (!mounted || !_owner.current) return;
    final okay = await showWorkflowDialog<bool>(
      context: context,
      workflow: _owner,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('Xác nhận đúng ảnh đang chỉnh'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.memory(Uint8List.fromList(bytes), height: 220),
            const Text(
              'Kích thước trùng chưa chứng minh nội dung trùng. Chỉ chọn nếu đúng ảnh đang chỉnh.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Đúng ảnh này'),
          ),
        ],
      ),
    );
    if (okay == true) {
      _assets[key] = selected.id;
      _uncertainImages.remove(key);
      _message = 'Đã đối chiếu asset; bản local giữ nguyên.';
    }
  });
  Future<void> _publish() async {
    final confirmed = await showWorkflowDialog<bool>(
      context: context,
      workflow: _owner,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('Công khai snapshot đã lưu?'),
        content: const Text(
          'Ảnh, tên điểm đến, graph và Landmark của phiên bản đã lưu sẽ được Visitor đọc không cần đăng nhập. Chỉ công bố dữ liệu bạn được phép chia sẻ. Validation không xác nhận lối đi bệnh viện hoặc xe lăn an toàn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Xuất bản snapshot'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_owner.current) return;
    await _run(() async {
      _stage = 'Publish snapshot server';
      await _wait(
        _maps.publish(_document!['id'] as String, _document!['version'] as int),
      );
      _qrs = await _wait(_maps.qrs(_document!['id'] as String));
      _message =
          'Đã xuất bản snapshot v${_document!['version']}. QR được ghim phiên bản này, không tự trỏ sang bản sửa mới.';
    });
  }

  Future<void> _showQrSafe(Map<String, dynamic> q) async {
    if (!_owner.current || !mounted) return;
    try {
      await _owner.run(() => _showQr(q));
    } catch (_) {
      if (mounted && _owner.current) {
        setState(
          () =>
              _message = 'Chưa mở được QR; giữ bản nháp và thử đọc lại server.',
        );
      }
    }
  }

  Future<void> _showQr(Map<String, dynamic> q) async {
    final payload = q['payload'] as String;
    String label = 'Node ${q['nodeId']}';
    if (q['draftVersion'] == _document?['version']) {
      final saved = _savedNodes
          .where((n) => n.id == q['nodeId'] && n.floorKey == q['floorKey'])
          .firstOrNull;
      if (saved != null) label = saved.label;
    } else if (q['publishedVersion'] != null) {
      final old = await _wait(
        _maps.json(
          'public/maps/${q['mapId']}/versions/${q['publishedVersion']}',
        ),
      ) as Map;
      for (final f in old['content']['floors'] as List) {
        if (f['id'] != q['floorKey']) continue;
        for (final n in f['content']['nodes'] as List) {
          if (n['id'] == q['nodeId']) {
            label = '${n['displayName'] ?? n['name']} • ${f['name']}';
          }
        }
      }
    }
    if (!mounted || !_owner.current) return;
    await showWorkflowDialog<void>(
      context: context,
      workflow: _owner,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('QR vị trí • Node ID ổn định'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              if (q['isActive'] != true)
                const Text('ĐÃ THU HỒI • không dùng định vị'),
              SizedBox.square(
                dimension: 230,
                child: QrImageView(
                  data: payload,
                  size: 230,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(24),
                ),
              ),
              Text(
                q['publishedVersion'] == null
                    ? 'Chưa publish • không dùng định vị Visitor'
                    : 'Published v${q['publishedVersion']}',
              ),
              SelectableText(payload),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Đóng'),
          ),
          TextButton(
            onPressed: q['isActive'] != true
                ? null
                : () async {
                    try {
                      await _wait(
                        _files.save(
                          await _wait(nodeQrPng(payload)),
                          'waymark-qr-${q['id']}.png',
                          'image/png',
                        ),
                      );
                      if (mounted && c.mounted) {
                        ScaffoldMessenger.of(c).showSnackBar(
                          const SnackBar(content: Text('Đã lưu QR PNG.')),
                        );
                      }
                    } catch (e) {
                      if (mounted && c.mounted) {
                        ScaffoldMessenger.of(
                          c,
                        ).showSnackBar(SnackBar(content: Text(e.toString())));
                      }
                    }
                  },
            child: const Text('Lưu PNG'),
          ),
          if (q['isActive'] == true && q['publishedVersion'] != null)
            TextButton(
              onPressed: () async {
                Navigator.pop(c);
                await _run(() async {
                  final session = await _wait(_maps.loadQr(payload));
                  if (!mounted || !_owner.current) return;
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
                });
              },
              child: const Text('Thử như Visitor'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => !_owner.current
      ? WorkflowRecovery(
          workflow: _owner,
          api: AuthApiService(client: _api.client),
          onRecovered: () {
            setState(() {
              _savedVerified = false;
              _uncertainSave = true;
              _message = 'Đã xác minh chủ phiên. Đọc lại server và đối chiếu; chưa tự gửi lại thao tác.';
            });
          },
        )
      : Scaffold(
          appBar: AppBar(title: const Text('Server Draft • Publish • QR')),
          bottomNavigationBar: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .24,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Text(_message, key: const Key('project-cloud-status')),
              ),
            ),
          ),
          body: SafeArea(
            child: ListView(
              key: const Key('cloud-content'),
              padding: const EdgeInsets.all(16),
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_uncertainSave)
                  OutlinedButton(
                    key: const Key('reconcile-cloud-write'),
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await _refreshSaved();
                            if (!_localChanged && _document != null) {
                              _uncertainSave = false;
                              _editBaseVersion = _document!['version'] as int;
                              _message = 'Đã đối chiếu: server khớp bản local. Không gửi lại Save/Publish.';
                            } else {
                              _message = 'Server chưa khớp local. Giữ bản nháp; không tự ghi đè hoặc thử lại.';
                            }
                          }),
                    child: const Text('Đối chiếu lần ghi chưa rõ kết quả'),
                  ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          _saved = await _wait(_maps.list());
                          _sites = await _wait(_api.getSites());
                          await _refreshSaved();
                          _message =
                              'Đã đọc lại server; graph local giữ nguyên.';
                        }),
                  child: const Text('Tải lại bản đồ của tôi'),
                ),
                if (_document != null)
                  OutlinedButton.icon(
                    key: const Key('refresh-saved-project'),
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await _refreshSaved();
                            _message = 'Đã GET trạng thái server. Không thay graph đang chỉnh.';
                          }),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Đọc lại trạng thái server (giữ local)'),
                  ),
                if (kDebugMode)
                  Text(
                    'QR-P0-20261025.3 • busy=$_busy • verified=$_savedVerified • phase=$_stage${_failureCode == null ? '' : ' • error=$_failureCode'}',
                    key: const Key('qr-safe-diagnostics'),
                  ),
                for (final doc in _saved)
                  ListTile(
                    title: Text('${doc['name']} • draft v${doc['version']}'),
                    subtitle: Text(doc['id'] as String),
                    trailing: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _load(doc['id'] as String),
                      child: const Text('Tải draft'),
                    ),
                  ),
                if (_project case final p?) ...[
                  TextField(
                    controller: _name,
                    enabled: !_busy,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Tên bản đồ công khai',
                    ),
                  ),
                  const Text(
                    'Ghép mỗi tầng local với tầng server thuộc Building được cấp quyền. Không đổi GUID hoặc graph production.',
                  ),
                  if (_document == null) ...[
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: _site,
                      decoration: const InputDecoration(labelText: 'Site'),
                      items: [
                        for (final s in _sites)
                          DropdownMenuItem(
                            value: s['id'] as int,
                            child: Text(s['name'] as String),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (id) => _run(() async {
                              _buildings = await _wait(_api.getBuildings(id!));
                              _site = id;
                              _building = null;
                              _floors = [];
                              _bindings.clear();
                              _assets.clear();
                            }),
                    ),
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      key: ValueKey('building-$_site'),
                      initialValue: _building,
                      decoration: const InputDecoration(labelText: 'Building'),
                      items: [
                        for (final b in _buildings)
                          DropdownMenuItem(
                            value: b['id'] as int,
                            child: Text(b['name'] as String),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (id) => _run(() async {
                              _floors = await _wait(_api.getFloors(id!));
                              _building = id;
                              _bindings.clear();
                              _assets.clear();
                            }),
                    ),
                  ],
                  for (final f in p.floors) ...[
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      key: ValueKey('binding-${f.localWorkspaceId}-$_building'),
                      initialValue: _bindings[f.localWorkspaceId],
                      decoration: InputDecoration(
                        labelText: 'Tầng local: ${f.floor.name}',
                      ),
                      items: [
                        for (final floor in _floors)
                          DropdownMenuItem(
                            value: floor['id'] as int,
                            child: Text(floor['name'] as String),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                              _bindings[f.localWorkspaceId!] = v!;
                              _assets.remove(f.localWorkspaceId);
                            }),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _reconcile(f.localWorkspaceId!),
                      child: Text('Đối chiếu ảnh • ${f.floor.name}'),
                    ),
                  ],
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: const Text('Lưu draft nhiều tầng lên server'),
                  ),
                  if (_document != null) ...[
                    Text(
                      'Local: ${p.floors.fold<int>(0, (v, f) => v + f.nodes.length)} node • ${p.floors.fold<int>(p.links.length, (v, f) => v + f.edges.length)} cạnh. '
                      'Server v${_document!['version']}: ${_savedNodes.length} node • ${(_document!['content']['floors'] as List).fold<int>(0, (v, f) => v + (f['content']['edges'] as List).length)} cạnh.',
                      key: const Key('local-server-counts'),
                    ),
                    if (_localChanged)
                      const Text(
                        'Ảnh/graph/tên local khác bản đã lưu. QR và Publish chỉ dùng dữ liệu server bên dưới; không tự đưa thay đổi chưa lưu vào snapshot.',
                        key: Key('local-unsaved-project'),
                      ),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          '1. Lưu ảnh và graph, đánh dấu Node đích và nhập khoảng cách mét.\n2. Chọn Node khởi đầu bên dưới rồi Tạo / xem QR (chưa cần Publish).\n3. Xuất bản snapshot đã lưu để kích hoạt QR.\n4. Xem / tải PNG và thử như Visitor.\nThay đổi chưa lưu trong Builder không nằm trong snapshot này.',
                        ),
                      ),
                    ),
                    Text(
                      _savedNodes.isEmpty
                          ? 'Workspace server v${_document!['version']} còn trống; chưa xác nhận lưu graph/ảnh.'
                          : 'Draft server v${_document!['version']} • ${_savedNodes.length} node đã lưu • ảnh/graph private cho đến khi publish',
                    ),
                    if (_qrBlocked != null)
                      Text(_qrBlocked!, key: const Key('qr-blocked-reason')),
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        'qr-node-${_document!['id']}-${_document!['version']}-$_savedVerified',
                      ),
                      initialValue: _savedNodes.any((n) => n.id == _node)
                          ? _node
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Node tạo QR • cùng GUID với Builder',
                      ),
                      items: [
                        for (final n in _savedNodes)
                          DropdownMenuItem(
                            value: n.id,
                            child: Text(
                              n.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _busy || !_savedVerified || _savedNodes.isEmpty
                          ? null
                          : (v) => setState(() => _node = v),
                    ),
                    OutlinedButton(
                      onPressed: _qrBlocked != null ? null : _createStartQr,
                      child: const Text('Tạo / xem QR cho Node'),
                    ),
                    if (_document!['canPublish'] == true)
                      FilledButton(
                        onPressed: _publishBlocked != null ? null : _publish,
                        child: const Text('Xuất bản snapshot đã lưu'),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Cần được cấp quyền xuất bản cho cơ sở này. Liên hệ người quản lý Site; không tự cấp SitePublisher.',
                        ),
                      ),
                    if (_publishBlocked != null)
                      Text(
                        _publishBlocked!,
                        key: const Key('publish-blocked-reason'),
                      ),
                    if (_readinessError != null)
                      Text(
                        _readinessError!,
                        key: const Key('publish-readiness-error'),
                      ),
                    for (final check in _checks)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          check['passed'] == true
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                        ),
                        title: Text(check['message'] as String),
                      ),
                    if (_document!['publicationKind'] == 'PersonalDemo')
                      const Text(
                        'Bản đồ cá nhân/demo — không đại diện cơ sở được ủy quyền, chưa xác minh cho bệnh nhân.',
                      ),
                    if (_document!['canPublish'] == true &&
                        !_qrs.any(
                          (q) =>
                              q['isActive'] == true &&
                              q['draftVersion'] == _document!['version'],
                        ))
                      const Text(
                        'Tạo QR cho ít nhất một node xuất phát của phiên bản đã lưu trước khi xuất bản.',
                      ),
                    for (final q in _qrs)
                      ListTile(
                        title: Text(
                          'QR • draft v${q['draftVersion']} • ${q['isActive'] == true ? 'active' : 'revoked'}',
                        ),
                        subtitle: Text(
                          'Node ${q['nodeId']} • ${q['publishedVersion'] == null ? 'Chưa publish' : 'Published v${q['publishedVersion']}'}',
                        ),
                        onTap: _busy ? null : () => _showQrSafe(q),
                        trailing: q['isActive'] != true
                            ? null
                            : TextButton(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        final yes =
                                            await showWorkflowDialog<bool>(
                                              context: context,
                                              workflow: _owner,
                                              builder: (c) => AlertDialog(
                                                scrollable: true,
                                                title: const Text(
                                                  'Thu hồi QR?',
                                                ),
                                                content: const Text(
                                                  'QR đã in sẽ không còn dùng xác nhận vị trí. Snapshot đã công khai vẫn tồn tại.',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(c, false),
                                                    child: const Text('Hủy'),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(c, true),
                                                    child: const Text(
                                                      'Thu hồi',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                        if (yes == true && _owner.current) {
                                          await _run(() async {
                                            await _wait(
                                              _maps.revoke(
                                                _document!['id'] as String,
                                                q['id'] as String,
                                              ),
                                            );
                                            _qrs = await _wait(
                                              _maps.qrs(
                                                _document!['id'] as String,
                                              ),
                                            );
                                          });
                                        }
                                      },
                                child: const Text('Thu hồi'),
                              ),
                      ),
                    OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context, p),
                      child: const Text('Mở bản đang tải trong Builder'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
}
