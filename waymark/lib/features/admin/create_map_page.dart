import 'package:flutter/material.dart';

import '../../services/auth_session.dart';
import '../auth/workflow_recovery.dart';

import '../../models/account_profile.dart';
import '../../services/auth_api_service.dart';
import '../../services/published_map_api_service.dart';
import '../../services/map_draft_api_service.dart';
import '../profile/account_widgets.dart';
import 'draft_map.dart';
import 'draft_map_editor.dart';
import 'map_project_cloud_page.dart';

class CreateMapPage extends StatefulWidget {
  const CreateMapPage({super.key, required this.profile, this.maps, this.auth});
  final AccountProfile profile;
  final PublishedMapApiService? maps;
  final AuthApiService? auth;
  @override
  State<CreateMapPage> createState() => _CreateMapPageState();
}

class _CreateMapPageState extends State<CreateMapPage> {
  final _owner = OwnerWorkflow();
  void _ownerChanged() {
    if (mounted) setState(() {});
  }

  Future<T> _wait<T>(Future<T> future) => _owner.wait(future);
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _place = TextEditingController(),
      _description = TextEditingController();
  final _floor = TextEditingController(text: 'Tầng trệt'),
      _code = TextEditingController(text: 'G');
  final _requestId = newDraftGuid();
  String _purpose = 'PersonalDemo';
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _owner.removeListener(_ownerChanged);
    _owner.dispose();
    for (final c in [_name, _place, _description, _floor, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy || !_owner.current || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final maps = widget.maps ?? PublishedMapApiService();
      final doc = await _wait(
        maps.startPersonal({
          'requestId': _requestId,
          'name': _name.text.trim(),
          'purpose': _purpose,
          'placeName': _place.text.trim(),
          'description': _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
          'floorName': _floor.text.trim(),
          'floorCode': _code.text.trim(),
        }),
      );
      final project = await _wait(maps.project(doc, public: false));
      // Fetch effective capabilities from the server; no JWT role forgery or
      // forced logout/login is needed for a newly granted personal entitlement.
      try {
        await _wait((widget.auth ?? AuthApiService()).getProfile());
      } on AuthApiException {
        /* Draft already saved; do not repeat create for a profile refresh error. */
      }
      if (!mounted || !_owner.current) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => DraftMapEditor(
            initialProject: project,
            initialCloudLink: ProjectCloudLink(doc, project),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = error is MapDraftApiException || error is FormatException
              ? error.toString()
              : 'Chưa tạo được bản đồ. Thử lại với cùng yêu cầu hoặc mở Bản đồ của tôi.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    TextEditingController c,
    String label,
    String key,
    int max, {
    bool required = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: Key(key),
      controller: c,
      enabled: !_busy,
      maxLength: max,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (v) => required && (v == null || v.trim().isEmpty)
          ? 'Vui lòng nhập $label'
          : null,
    ),
  );
  @override
  Widget build(BuildContext context) => !_owner.current
      ? WorkflowRecovery(workflow: _owner, api: widget.auth)
      : Scaffold(
          appBar: AppBar(title: const Text('Bắt đầu tạo bản đồ')),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const AccountHeader(
                    name: 'Bản đồ của riêng bạn',
                    subtitle: 'Lưu bản nháp riêng tư trước. Chỉ chia sẻ snapshot khi bạn xác nhận.',
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error!,
                        key: const Key('create-map-error'),
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _field(_name, 'Tên bản đồ', 'create-map-name', 200),
                        DropdownButtonFormField<String>(
                          initialValue: _purpose,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Mục đích',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'PersonalDemo',
                              child: Text('Cá nhân / Demo'),
                            ),
                            DropdownMenuItem(
                              value: 'FacilityProposal',
                              child: Text('Đề xuất cơ sở — chưa ủy quyền'),
                            ),
                          ],
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _purpose = v!),
                        ),
                        const SizedBox(height: 16),
                        _field(_place, 'Tên địa điểm', 'create-map-place', 200),
                        _field(
                          _description,
                          'Mô tả ngắn',
                          'create-map-description',
                          1000,
                          required: false,
                        ),
                        Text(
                          'Email liên hệ: ${widget.profile.email ?? 'Chưa có email'}',
                        ),
                        const Text(
                          'Thông tin lấy từ tài khoản; không được dùng để tự nhận quyền đại diện bệnh viện.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 20),
                        _field(
                          _floor,
                          'Tên tầng đầu tiên',
                          'create-map-floor',
                          100,
                        ),
                        _field(_code, 'Mã tầng', 'create-map-floor-code', 30),
                        const Text(
                          'Workspace cá nhân tách biệt mọi Site bệnh viện. Tên cơ sở bạn nhập chưa được xác minh. Không cấp quyền Admin/SitePublisher.',
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          key: const Key('create-map-submit'),
                          onPressed: _busy ? null : _create,
                          icon: const Icon(Icons.add),
                          label: const Text('Tạo bản nháp và mở Builder'),
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
