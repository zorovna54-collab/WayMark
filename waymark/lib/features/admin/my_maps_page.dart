import 'package:flutter/material.dart';

import '../auth/workflow_recovery.dart';

import '../../services/published_map_api_service.dart';
import '../../services/auth_session.dart';
import 'draft_map_editor.dart';
import 'map_project_cloud_page.dart';
import 'map_builder_page.dart';

class MyMapsPage extends StatefulWidget {
  const MyMapsPage({super.key, this.api});
  final PublishedMapApiService? api;
  @override
  State<MyMapsPage> createState() => _MyMapsPageState();
}

class _MyMapsPageState extends State<MyMapsPage> {
  late final _api = widget.api ?? PublishedMapApiService();
  List<Map<String, dynamic>> _maps = [];
  bool _busy = true;
  String? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    AuthSession.changes.addListener(_sessionChanged);
    _load();
  }

  void _sessionChanged() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    AuthSession.changes.removeListener(_sessionChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _maps = [];
    });
    try {
      final maps = await _api.list();
      if (mounted && generation == _generation) setState(() => _maps = maps);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _open(String id) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final doc = await _api.get(id);
      if (!mounted || generation != _generation) return;
      final project = await _api.project(doc, public: false);
      if (!mounted || generation != _generation) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => DraftMapEditor(
            initialProject: project,
            initialCloudLink: ProjectCloudLink(doc, project),
          ),
        ),
      );
      if (mounted && generation == _generation) await _load();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Bản đồ của tôi'),
      actions: [
        IconButton(
          tooltip: 'Tải lại',
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminMapBuilderPage(),
                  ),
                ),
          icon: const Icon(Icons.edit_location_alt_outlined),
          label: const Text('Mở Builder cục bộ'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Bản local chưa lưu server. Lưu/xuất bản cho cơ sở cần membership và quyền Site do server cấp.',
          ),
        ),
        const SessionRecoveryButton(),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        if (!_busy && _maps.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Chưa có bản đồ được cấp quyền. Chọn Bắt đầu tạo bản đồ trong Cài đặt.',
            ),
          ),
        for (final map in _maps)
          Card(
            child: ListTile(
              leading: const Icon(Icons.map_outlined),
              title: Text(map['name'] as String),
              subtitle: Text(
                'Draft v${map['version']} • ${map['publishedVersion'] == null ? 'Chưa xuất bản' : 'Published v${map['publishedVersion']}'}\n${map['publicationKind'] == 'PersonalDemo' ? 'Cá nhân / Demo' : 'Theo quyền cơ sở'}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => _open(map['id'] as String),
            ),
          ),
      ],
    ),
  );
}
