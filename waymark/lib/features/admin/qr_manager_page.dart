import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../services/waymark_api_service.dart';
import 'admin_page_shell.dart';

class AdminQrManagerPage extends StatefulWidget {
  const AdminQrManagerPage({super.key});

  @override
  State<AdminQrManagerPage> createState() => _AdminQrManagerPageState();
}

class _AdminQrManagerPageState extends State<AdminQrManagerPage> {
  final WayMarkApiService _api = WayMarkApiService();
  final TextEditingController _searchController = TextEditingController();

  List<WayMark> _wayMarks = const [];
  bool _isLoading = true;
  bool _isMutating = false;
  String? _loadError;

  List<WayMark> get _filteredWayMarks {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _wayMarks;
    return _wayMarks
        .where((wayMark) {
          return wayMark.name.toLowerCase().contains(query) ||
              wayMark.location.toLowerCase().contains(query) ||
              wayMark.wayMarkCode.toLowerCase().contains(query) ||
              '${wayMark.id ?? ''}'.contains(query);
        })
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadWayMarks();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  Future<void> _loadWayMarks() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final wayMarks = await _api.getWayMarks();
      if (!mounted) return;
      setState(() {
        _wayMarks = wayMarks;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error is WayMarkApiException ? error.message : 'Không thể tải danh sách WayMark. Hãy kiểm tra kết nối API rồi thử lại.';
        _isLoading = false;
      });
    }
  }

  Future<_WayMarkFormData?> _showEditor(WayMark? wayMark) =>
      showDialog<_WayMarkFormData>(
        context: context,
        builder: (_) => _WayMarkEditorDialog(wayMark: wayMark),
      );
  Future<void> _addWayMark() async {
    final values = await _showEditor(null);
    if (values == null || !mounted) return;

    setState(() => _isMutating = true);
    try {
      await _api.createWayMark(
        name: values.name,
        location: values.location,
        wayMarkCode: values.wayMarkCode,
      );
      if (!mounted) return;
      _showMessage('Đã tạo WayMark.');
      await _loadWayMarks();
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error));
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  Future<void> _editWayMark(WayMark wayMark) async {
    final values = await _showEditor(wayMark);
    if (values == null || !mounted) return;
    final id = wayMark.id;
    if (id == null) {
      _showMessage('Không thể cập nhật vì API không trả về ID WayMark.');
      return;
    }

    setState(() => _isMutating = true);
    try {
      await _api.updateWayMark(
        id: id,
        name: values.name,
        location: values.location,
        wayMarkCode: values.wayMarkCode,
      );
      if (!mounted) return;
      _showMessage('Đã cập nhật WayMark.');
      await _loadWayMarks();
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error));
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  Future<void> _deleteWayMark(WayMark wayMark) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa WayMark?'),
        content: Text(
          'Bạn có chắc muốn xóa “${wayMark.name}” (${wayMark.wayMarkCode}) không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final id = wayMark.id;
    if (id == null) {
      _showMessage('Không thể xóa vì API không trả về ID WayMark.');
      return;
    }

    setState(() => _isMutating = true);
    try {
      await _api.deleteWayMark(id);
      if (!mounted) return;
      _showMessage('Đã xóa WayMark.');
      await _loadWayMarks();
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error));
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  String _errorMessage(Object error) {
    if (error is WayMarkApiException) return error.message;
    return 'Không thể hoàn tất thao tác. Hãy kiểm tra kết nối API rồi thử lại.';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => AdminPageShell(
    title: 'Quản lý WayMark',
    child: Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 420,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Tìm theo tên, vị trí hoặc mã WayMark',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isLoading || _isMutating
                          ? null
                          : _loadWayMarks,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tải lại'),
                    ),
                    FilledButton.icon(
                      onPressed: _isMutating ? null : _addWayMark,
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm WayMark'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_loadError != null)
              _EmptyState(
                icon: Icons.cloud_off_outlined,
                message: _loadError!,
                action: TextButton.icon(
                  onPressed: _loadWayMarks,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                ),
              )
            else if (_wayMarks.isEmpty)
              const _EmptyState(
                icon: Icons.location_searching,
                message: 'Chưa có WayMark nào trong dữ liệu.',
              )
            else if (_filteredWayMarks.isEmpty)
              const _EmptyState(
                icon: Icons.search_off,
                message: 'Không tìm thấy WayMark phù hợp.',
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < _filteredWayMarks.length;
                      index++
                    ) ...[
                      _WayMarkRow(
                        wayMark: _filteredWayMarks[index],
                        enabled: !_isMutating,
                        onEdit: () => _editWayMark(_filteredWayMarks[index]),
                        onDelete: () =>
                            _deleteWayMark(_filteredWayMarks[index]),
                      ),
                      if (index < _filteredWayMarks.length - 1)
                        const Divider(height: 1),
                    ],
                  ],
                ),
              ),
          ],
        ),
        if (_isMutating)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(),
          ),
      ],
    ),
  );
}

class _WayMarkRow extends StatelessWidget {
  const _WayMarkRow({
    required this.wayMark,
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
  });

  final WayMark wayMark;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.qr_code_2, color: AppColors.accent),
    title: Text(
      wayMark.name,
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      '${wayMark.wayMarkCode} · ${wayMark.location}'
      '${wayMark.id == null ? '' : ' · ID ${wayMark.id}'}',
    ),
    isThreeLine: false,
    trailing: Wrap(
      spacing: 4,
      children: [
        IconButton(
          tooltip: 'Chỉnh sửa',
          onPressed: enabled ? onEdit : null,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Xóa',
          onPressed: enabled ? onDelete : null,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
    child: Column(
      children: [
        Icon(icon, size: 42, color: AppColors.textSecondary),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 8), action!],
      ],
    ),
  );
}

class _WayMarkFormData {
  const _WayMarkFormData({
    required this.name,
    required this.location,
    required this.wayMarkCode,
  });

  final String name;
  final String location;
  final String wayMarkCode;
}

class _WayMarkEditorDialog extends StatefulWidget {
  const _WayMarkEditorDialog({this.wayMark});

  final WayMark? wayMark;

  @override
  State<_WayMarkEditorDialog> createState() => _WayMarkEditorDialogState();
}

class _WayMarkEditorDialogState extends State<_WayMarkEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _locationController;
  late final TextEditingController _codeController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.wayMark?.name ?? '');
    _locationController = TextEditingController(
      text: widget.wayMark?.location ?? '',
    );
    _codeController = TextEditingController(
      text: widget.wayMark?.wayMarkCode ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required int maxLength,
  }) => TextFormField(
    controller: controller,
    maxLength: maxLength,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      counterText: '',
    ),
    validator: (value) {
      final text = value?.trim() ?? '';
      if (text.isEmpty) return '$label không được để trống.';
      if (text.length > maxLength) {
        return '$label không được vượt quá $maxLength ký tự.';
      }
      return null;
    },
  );

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _WayMarkFormData(
        name: _nameController.text.trim(),
        location: _locationController.text.trim(),
        wayMarkCode: _codeController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.wayMark == null ? 'Thêm WayMark' : 'Chỉnh sửa WayMark'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _textField(
                controller: _nameController,
                label: 'Name',
                maxLength: 200,
              ),
              const SizedBox(height: 12),
              _textField(
                controller: _locationController,
                label: 'Location',
                maxLength: 300,
              ),
              const SizedBox(height: 12),
              _textField(
                controller: _codeController,
                label: 'WayMarkCode',
                maxLength: 100,
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Hủy'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Lưu')),
    ],
  );
}
