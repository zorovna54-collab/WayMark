import 'package:flutter/material.dart';

import '../../models/ai_map_suggestion.dart';
import '../../models/ai_graph_proposal.dart';
import '../../services/ai_map_provider.dart';
import '../../services/ai_timeout_preferences.dart';
import '../route/floor_plan_canvas.dart';
import 'draft_map.dart';
import 'floor_plan_asset.dart';
import 'ai_graph_review.dart';
import 'ai_graph_review_panel.dart';
import 'ai_timeout_control.dart';

typedef AiMapProviderFactory = AiMapProvider Function(String url, String token);

/// No reference to a mutable draft: review cannot modify a graph by accident.
class AiMapAssistantPage extends StatefulWidget {
  const AiMapAssistantPage({
    super.key,
    required this.image,
    required this.floorName,
    this.providerFactory,
    this.graphInput,
    this.timeoutPreferences,
  });
  final FloorPlanAsset image;
  final String floorName;
  final AiMapProviderFactory? providerFactory;
  final AiGraphInput? graphInput;
  final AiTimeoutPreferences? timeoutPreferences;
  @override
  State<AiMapAssistantPage> createState() => _AiMapAssistantPageState();
}

class _AiMapAssistantPageState extends State<AiMapAssistantPage> {
  final _url = TextEditingController(
    text: const String.fromEnvironment('WAYMARK_AI_BASE_URL'),
  );
  final _token = TextEditingController();
  List<String> _models = [];
  String? _model;
  String _status =
      'Chưa kết nối. Nhập URL /v1; token chỉ giữ trong màn hình này.';
  List<AiMapSuggestion> _nodes = [];
  final _accepted = <String>{}, _rejected = <String>{};
  bool _busy = false;
  // Graph proposals need a longer bounded inference window than node-only
  // analysis on a local Vision model. The user can still choose a shorter wait.
  late int _timeoutSeconds = widget.graphInput == null ? 120 : 300;
  late final _preferences =
      widget.timeoutPreferences ?? const AiTimeoutPreferences();
  bool _timeoutLoading = true, _timeoutValid = true;
  String? _timeoutStorageMessage;
  int _timeoutRevision = 0;
  Future<void> _settingsWrite = Future.value();
  bool? _failedRequest;
  String get _timeoutScope =>
      AiTimeoutPreferences.scope(widget.graphInput != null);

  @override
  void initState() {
    super.initState();
    _loadTimeout();
  }

  Future<void> _loadTimeout() async {
    final scope = _timeoutScope, revision = ++_timeoutRevision;
    int? saved;
    try {
      saved = await _preferences
          .read(scope)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      /* Keep bounded default. */
    }
    if (!mounted || scope != _timeoutScope || revision != _timeoutRevision) {
      return;
    }
    setState(() {
      _timeoutSeconds = AiTimeoutPreferences.valid(saved)
          ? saved!
          : widget.graphInput == null
          ? 120
          : 300;
      _timeoutLoading = false;
      _timeoutValid = true;
    });
  }

  void _changeTimeout(int? seconds) {
    final revision = ++_timeoutRevision, scope = _timeoutScope;
    setState(() {
      _timeoutValid = seconds != null;
      if (seconds != null) _timeoutSeconds = seconds;
      _timeoutStorageMessage = null;
    });
    if (seconds == null) return;
    // Serial writes prevent a slow earlier selection overwriting a newer one.
    _settingsWrite = _settingsWrite.then((_) async {
      var saved = false;
      try {
        saved = await _preferences
            .write(scope, seconds)
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        /* Session choice remains usable. */
      }
      if (mounted && revision == _timeoutRevision && scope == _timeoutScope) {
        setState(
          () => _timeoutStorageMessage = saved
              ? 'Đã nhớ thời gian chờ trên thiết bị này.'
              : 'Đã áp dụng cho lần này; chưa lưu được tùy chọn trên thiết bị.',
        );
      }
    });
  }

  AiMapProvider? _active;
  String? _connectedUrl, _connectedToken;
  AiGraphReview? _graphReview;
  int _operation = 0;

  void _cancel() {
    _operation++;
    _active?.dispose();
    _active = null;
    if (mounted) {
      setState(() {
        _busy = false;
        _failedRequest = null;
        _status = 'Đã hủy AI. Graph gốc không thay đổi.';
      });
    }
  }

  @override
  void didUpdateWidget(covariant AiMapAssistantPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.graphInput == null) != (widget.graphInput == null)) {
      _timeoutLoading = true;
      _loadTimeout();
    }
    if (!identical(oldWidget.image, widget.image) ||
        !identical(oldWidget.graphInput, widget.graphInput)) {
      _cancel();
      _nodes = [];
      _graphReview = null;
      _accepted.clear();
      _rejected.clear();
    }
  }

  @override
  void dispose() {
    _active?.dispose();
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _run(bool analyze) async {
    if (_busy || (analyze && (_timeoutLoading || !_timeoutValid))) return;
    if (analyze &&
        (_connectedUrl != _url.text || _connectedToken != _token.text)) {
      setState(
        () => _status =
            'Cấu hình đã đổi. Hãy kiểm tra kết nối và chọn lại model.',
      );
      return;
    }
    if (analyze && (_nodes.isNotEmpty || _graphReview != null)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Thay bộ đề xuất?'),
          content: const Text(
            'Chỉ kết quả review hiện tại sẽ bị thay khi phân tích thành công. Graph gốc không đổi.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Phân tích lại'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _failedRequest = null;
      _status = analyze
          ? 'Đang phân tích ảnh… Thời gian chờ tối đa $_timeoutSeconds giây. Bạn có thể hủy.'
          : 'Đang lấy model…';
    });
    final operation = ++_operation;
    AiMapProvider? provider;
    try {
      provider =
          widget.providerFactory?.call(_url.text, _token.text) ??
          OpenAiMapProvider(
            baseUrl: _url.text,
            token: _token.text,
            timeout: Duration(seconds: _timeoutSeconds),
          );
      _active = provider;
      if (analyze) {
        if (widget.graphInput case final input?) {
          if (provider is! AiGraphProvider) {
            throw const FormatException(
              'Provider này chưa hỗ trợ graph proposal. Phase 1 vẫn dùng được.',
            );
          }
          final result = await provider.analyzeGraph(input, _model!);
          if (!mounted || operation != _operation) return;
          setState(() {
            _graphReview = AiGraphReview(input, result);
            _nodes = result.nodes.map((n) => n.node).toList();
            _accepted.clear();
            _rejected.clear();
            _status =
                'Vision có ảnh: ${result.nodes.length} Node / ${result.edges.length} Edge proposal; bỏ ${result.discarded} mục lỗi. Chưa ghi vào Draft. Mọi vị trí/lối đi còn chưa xác minh.';
          });
          return;
        }
        final result = await provider.analyze(widget.image, _model!);
        if (!mounted || operation != _operation) return;
        setState(() {
          _nodes = result.nodes;
          _accepted.clear();
          _rejected.clear();
          _status =
              'Đã nhận ${_nodes.length} đề xuất hợp lệ từ request có ảnh; bỏ ${result.rejected} mục lỗi. '
              'Tọa độ/nội dung chưa được xác minh. Không phải bằng chứng cửa/lối đi an toàn.';
        });
      } else {
        final models = await provider.models();
        if (!mounted || operation != _operation) return;
        setState(() {
          _models = models;
          _model = models.firstOrNull;
          _connectedUrl = _url.text;
          _connectedToken = _token.text;
          _status = models.isEmpty
              ? 'Server phản hồi nhưng không có model. Hãy load model Vision trong LM Studio.'
              : 'Server phản hồi ${models.length} model. CHƯA kiểm chứng Vision; bấm Phân tích ảnh để gửi ảnh thật.';
        });
      }
    } catch (e) {
      if (mounted && operation == _operation) {
        setState(() {
          _failedRequest = analyze;
          if (!analyze) {
            _models = [];
            _model = null;
            _connectedUrl = null;
            _connectedToken = null;
          }
          _status = e is AiMapException
              ? e.message
              : e is FormatException
              ? e.message
              : 'Không thể xử lý AI. Bản nháp thủ công không thay đổi.';
        });
      }
    } finally {
      provider?.dispose();
      if (identical(_active, provider)) _active = null;
      if (mounted && operation == _operation) setState(() => _busy = false);
    }
  }

  Future<void> _edit(int index) async {
    final node = _nodes[index];
    final name = TextEditingController(text: node.name);
    final x = TextEditingController(text: node.x.toString());
    final y = TextEditingController(text: node.y.toString());
    final note = TextEditingController(text: node.landmarkNote ?? '');
    var type = node.type, destination = node.destination;
    String? error;
    final result = await showDialog<AiMapSuggestion>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: const Text('Sửa đề xuất chưa xác minh'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Tên điểm đến'),
                  maxLength: 200,
                ),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  items: [
                    for (final t in AiMapSuggestion.types)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) => type = v!,
                  decoration: const InputDecoration(labelText: 'Loại node'),
                ),
                TextField(
                  controller: x,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'X chuẩn hóa 0–1',
                  ),
                ),
                TextField(
                  controller: y,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Y chuẩn hóa 0–1',
                  ),
                ),
                TextField(
                  controller: note,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Landmark có bằng chứng (tùy chọn)',
                  ),
                ),
                CheckboxListTile(
                  value: destination,
                  onChanged: (v) => update(() => destination = v!),
                  title: const Text('Có thể tìm kiếm như điểm đến'),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final revised = AiMapSuggestion.parse({
                    ...node.toJson(),
                    'displayName': name.text,
                    'nodeType': type,
                    'normalizedX': double.tryParse(x.text),
                    'normalizedY': double.tryParse(y.text),
                    'suggestedAsDestination': destination,
                    'landmarkNote': note.text.trim().isEmpty
                        ? null
                        : note.text.trim(),
                  });
                  Navigator.pop(dialog, revised);
                } on FormatException catch (e) {
                  update(() => error = e.message);
                }
              },
              child: const Text('Lưu chỉnh sửa'),
            ),
          ],
        ),
      ),
    );
    // Dialog exit animation still owns the text fields until the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      x.dispose();
      y.dispose();
      note.dispose();
    });
    if (result != null && mounted) {
      setState(() {
        _nodes = [..._nodes]..[index] = result;
        _accepted.remove(node.id);
        if (_graphReview case final review?) {
          final original = review.nodes[index];
          review.editNode(
            AiGraphNode(result, original.floorId, original.evidence),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.graphInput == null
            ? 'AI • Review node'
            : 'AI • Review Node / Edge',
      ),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${widget.floorName} • ${widget.image.name} • ${widget.image.width} × ${widget.image.height}',
          ),
          Text(
            'AI chỉ gợi ý; bạn cần kiểm tra trước khi thêm vào bản nháp. '
            'Ảnh sẽ gửi tới máy chủ bạn chọn. ${widget.graphInput == null ? 'Không tạo cạnh.' : 'Cạnh cần bạn xác nhận hướng và khoảng cách.'}',
          ),
          ExpansionTile(
            key: ValueKey(
              'ai-connection-${_graphReview != null || _nodes.isNotEmpty}',
            ),
            initiallyExpanded: _graphReview == null && _nodes.isEmpty,
            title: const Text('Kết nối và thời gian chờ'),
            tilePadding: EdgeInsets.zero,
            children: [
              TextField(
                key: const Key('ai-url'),
                controller: _url,
                enabled: !_busy,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Base URL (kết thúc /v1)',
                  hintText: 'http(s)://host:port/v1',
                ),
              ),
              const ExpansionTile(
                title: Text('Hướng dẫn kết nối và giới hạn ảnh'),
                children: [
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Windows: 127.0.0.1 • Android Emulator: 10.0.2.2 • Android thật: IP LAN của máy LM Studio. Port 1234. HTTP chỉ cho debug. '
                      'Ảnh gửi AI tối đa 4 MB / 8 MP. Bản sao thu nhỏ cạnh dài tối đa 768 px; không crop hoặc sửa ảnh gốc. Chỉ dùng máy chủ tin cậy.',
                    ),
                  ),
                ],
              ),
              TextField(
                key: const Key('ai-token'),
                controller: _token,
                enabled: !_busy,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Token LM Studio (nếu bắt buộc, không lưu)',
                ),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _run(false),
                child: const Text('Kiểm tra kết nối / models'),
              ),
              if (_models.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: ValueKey(_models.join('|')),
                  initialValue: _model,
                  isExpanded: true,
                  items: [
                    for (final model in _models)
                      DropdownMenuItem(
                        value: model,
                        child: Text(model, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _model = v),
                  decoration: const InputDecoration(
                    labelText: 'Model ID từ server',
                  ),
                ),
              if (_timeoutLoading)
                const LinearProgressIndicator()
              else
                AiTimeoutControl(
                  key: ValueKey(_timeoutScope),
                  seconds: _timeoutSeconds,
                  enabled: !_busy,
                  onChanged: _changeTimeout,
                ),
              if (_timeoutStorageMessage != null)
                Text(
                  _timeoutStorageMessage!,
                  key: const Key('ai-timeout-storage-status'),
                ),
            ],
          ),
          FilledButton(
            onPressed:
                _busy || _model == null || _timeoutLoading || !_timeoutValid
                ? null
                : () => _run(true),
            child: const Text('Phân tích ảnh bằng Vision'),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_busy)
            TextButton(
              key: const Key('ai-cancel-request'),
              onPressed: _cancel,
              child: const Text('Hủy phân tích'),
            ),
          Text(_status, key: const Key('ai-status')),
          if (_failedRequest != null)
            OutlinedButton.icon(
              key: const Key('ai-retry'),
              onPressed: _busy ? null : () => _run(_failedRequest!),
              icon: const Icon(Icons.refresh),
              label: Text(
                _failedRequest! ? 'Thử lại phân tích' : 'Thử kết nối lại',
              ),
            ),
          if (_graphReview case final review?)
            AiGraphReviewPanel(
              key: ObjectKey(review),
              review: review,
              enabled: !_busy,
              onEditNode: _edit,
              onApply: (batch) => Navigator.pop(context, batch),
            ),
          if (widget.graphInput == null) ...[
            SizedBox(
              height: 320,
              child: FloorPlanCanvas(
                image: widget.image.imageProvider,
                painterBuilder: (scale) => _SuggestionPainter(
                  _nodes,
                  Set.of(_accepted),
                  Set.of(_rejected),
                  scale,
                ),
              ),
            ),
            const Text(
              'Đánh số trên ảnh tương ứng danh sách. Accept chỉ đưa vào hàng đợi; nút cuối mới thêm vào bản nháp.',
            ),
            for (var i = 0; i < _nodes.length; i++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${i + 1}. ${_nodes[i].name} • ${_nodes[i].type}'),
                      Text(
                        'X ${_nodes[i].x.toStringAsFixed(3)}, Y ${_nodes[i].y.toStringAsFixed(3)} • confidence ${(_nodes[i].confidence * 100).round()}%',
                      ),
                      Text('Chưa xác minh: ${_nodes[i].uncertainty}'),
                      if (_nodes[i].landmarkNote != null)
                        Text('Landmark đề xuất: ${_nodes[i].landmarkNote}'),
                      Text(
                        _rejected.contains(_nodes[i].id)
                            ? 'Đã Reject'
                            : _accepted.contains(_nodes[i].id)
                            ? 'Đã Accept • chưa thêm vào graph'
                            : 'Chờ duyệt',
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            key: Key('accept-$i'),
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _accepted.add(_nodes[i].id);
                                    _rejected.remove(_nodes[i].id);
                                  }),
                            child: const Text('Accept'),
                          ),
                          TextButton(
                            key: Key('edit-$i'),
                            onPressed: _busy ? null : () => _edit(i),
                            child: const Text('Edit'),
                          ),
                          TextButton(
                            key: Key('reject-$i'),
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _accepted.remove(_nodes[i].id);
                                    _rejected.add(_nodes[i].id);
                                  }),
                            child: const Text('Reject'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            FilledButton(
              key: const Key('ai-add-reviewed'),
              onPressed: _busy || _accepted.isEmpty
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: Text(
                            'Thêm ${_accepted.length} node vào bản nháp?',
                          ),
                          content: const Text(
                            'Đây là node AI chưa xác minh. Phải kiểm tra trên ảnh/thực địa, chỉnh vị trí cửa trước khi nối cạnh. Không cấp chứng nhận lối đi hay xe lăn.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Hủy'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Xác nhận thêm'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && context.mounted) {
                        Navigator.pop(
                          context,
                          _nodes
                              .where((n) => _accepted.contains(n.id))
                              .toList(),
                        );
                      }
                    },
              child: Text(
                'Thêm ${_accepted.length} node đã duyệt vào bản nháp',
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _SuggestionPainter extends CustomPainter {
  _SuggestionPainter(this.nodes, this.accepted, this.rejected, this.scale);
  final List<AiMapSuggestion> nodes;
  final Set<String> accepted, rejected;
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(1 / scale);
    size = size * scale;
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      if (rejected.contains(n.id)) continue;
      final p = Offset(n.x * size.width, n.y * size.height);
      canvas.drawCircle(
        p,
        13,
        Paint()
          ..color = accepted.contains(n.id)
              ? Colors.green.shade800
              : Colors.deepOrange.shade800,
      );
      final label = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, p - Offset(label.width / 2, label.height / 2));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SuggestionPainter oldDelegate) => true;
}

/// Explicit review commit only; append fresh local IDs, never replace AI/client IDs.
void appendReviewedAiNodes(
  DraftMap draft,
  FloorPlanAsset source,
  List<AiMapSuggestion> reviewed,
) {
  if (!identical(draft.image, source)) {
    throw const FormatException('Ảnh đã đổi; cần phân tích lại.');
  }
  if (draft.nodes.length + reviewed.length > 2000) {
    throw const FormatException('Bản nháp tối đa 2000 node.');
  }
  // Validate every item before making any mutation.
  final checked = reviewed
      .map((n) => AiMapSuggestion.parse(n.toJson()))
      .toList();
  for (final n in checked) {
    draft.putNode(
      DraftNode(
        'AI-${newDraftGuid()}',
        n.name,
        n.x,
        n.y,
        n.type,
        displayName: n.name,
        searchableAsDestination: n.destination,
        landmarkNote:
            'AI chưa xác minh vị trí/lối đi.${n.landmarkNote == null ? '' : ' ${n.landmarkNote}'}',
      ),
    );
  }
  if (checked.isNotEmpty) draft.layoutReviewed = false;
}
