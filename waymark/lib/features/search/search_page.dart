import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../services/waymark_api_service.dart';
import '../../models/route_models.dart';
import '../scanner/scanner_page.dart';
import '../route/route_preview_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.start, this.api, this.initialQuery = ''});
  final WayMarkMapLocation? start;
  final WayMarkApiService? api;
  final String initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<WayMark> _wayMarks = const [];
  bool _isLoading = true;
  Object? _loadError;
  late final WayMarkApiService _api = widget.api ?? WayMarkApiService();
  late WayMarkMapLocation? _start = widget.start;
  bool _accessibleOnly = false;
  bool _openingRoute = false;

  List<WayMark> get _filteredWayMarks {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _wayMarks;
    return _wayMarks
        .where((wayMark) {
          return wayMark.name.toLowerCase().contains(query) ||
              wayMark.location.toLowerCase().contains(query) ||
              wayMark.wayMarkCode.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialQuery;
    _searchController.addListener(_onSearchChanged);
    _loadWayMarks();
  }

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
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() => setState(() {});

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _chooseStart() async {
    final start = await Navigator.push<WayMarkMapLocation>(
      context,
      MaterialPageRoute<WayMarkMapLocation>(
        builder: (_) => ScannerPage(api: _api, selectStartOnly: true),
      ),
    );
    if (mounted && start != null) setState(() => _start = start);
  }

  Future<void> _selectWayMark(WayMark wayMark) async {
    if (_openingRoute) return;
    _openingRoute = true;
    try {
      if (_start == null) await _chooseStart();
      if (!mounted || _start == null) return;
      FocusScope.of(context).unfocus();
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => RoutePreviewPage(
            startWayMarkCode: _start!.wayMarkCode,
            destinationWayMarkCode: wayMark.wayMarkCode,
            accessibleOnly: _accessibleOnly,
            api: _api,
          ),
        ),
      );
    } finally {
      _openingRoute = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _filteredWayMarks;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: AppColors.card,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          hintText: 'Tìm theo tên, vị trí hoặc mã WayMark',
                          prefixIcon: Icon(
                            Icons.search,
                            color: AppColors.textMuted,
                            size: 20,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.my_location, color: AppColors.accent),
              title: Text(
                _start == null
                    ? 'Quét QR để chọn điểm xuất phát'
                    : 'Từ: ${_start!.name}',
              ),
              subtitle: _start == null ? null : Text(_start!.wayMarkCode),
              trailing: IconButton(
                tooltip: 'Quét điểm xuất phát',
                onPressed: _chooseStart,
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ),
            SwitchListTile(
              title: const Text('Chỉ dùng lối đi được đánh dấu accessible'),
              subtitle: const Text(
                'Theo dữ liệu quản trị; chưa bảo đảm phù hợp mọi xe lăn.',
              ),
              value: _accessibleOnly,
              onChanged: (value) => setState(() => _accessibleOnly = value),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError != null
                  ? _messageState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Không thể tải danh sách WayMark',
                      detail: '$_loadError',
                      action: TextButton.icon(
                        onPressed: _loadWayMarks,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Thử lại'),
                      ),
                    )
                  : _wayMarks.isEmpty
                  ? _messageState(
                      icon: Icons.location_off_outlined,
                      title: 'Chưa có WayMark nào',
                      detail: 'Danh sách địa điểm từ hệ thống hiện đang trống.',
                    )
                  : results.isEmpty
                  ? _messageState(
                      icon: Icons.search_off,
                      title: 'Không tìm thấy WayMark',
                      detail: 'Thử tìm theo tên, vị trí hoặc mã WayMark khác.',
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 8, bottom: 14),
                          child: Text(
                            'ĐỊA ĐIỂM',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                        for (final wayMark in results)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _wayMarkCard(wayMark),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wayMarkCard(WayMark wayMark) => InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: () => _selectWayMark(wayMark),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.location_on_outlined,
              color: AppColors.primary,
              size: 21,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wayMark.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  wayMark.location,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            constraints: const BoxConstraints(maxWidth: 110),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              wayMark.wayMarkCode,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _messageState({
    required IconData icon,
    required String title,
    required String detail,
    Widget? action,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: AppColors.textMuted),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          ?action,
        ],
      ),
    ),
  );
}
