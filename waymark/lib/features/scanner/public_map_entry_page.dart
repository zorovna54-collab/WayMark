import 'package:flutter/material.dart';

import '../../services/published_map_api_service.dart';
import '../../services/published_read_failure.dart';
import '../../services/navigation_history_service.dart';
import '../search/local_map_search_page.dart';
import 'scanner_page.dart';

/// Public read only, with a paste fallback for a damaged/unavailable camera.
class PublicMapEntryPage extends StatefulWidget {
  const PublicMapEntryPage({super.key, this.api, this.initialPayload = ''});
  final PublishedMapApiService? api;
  final String initialPayload;
  @override
  State<PublicMapEntryPage> createState() => _PublicMapEntryPageState();
}

class _PublicMapEntryPageState extends State<PublicMapEntryPage> {
  late final _code = TextEditingController(text: widget.initialPayload);
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await (widget.api ?? PublishedMapApiService()).loadQr(
        _code.text,
      );
      if (!mounted) return;
      recordPublishedScan(
        session,
        service: NavigationHistoryService(
          client: widget.api?.client,
          baseUrl: widget.api?.baseUrl,
        ),
      );
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
    } catch (e) {
      if (mounted) {
        _error = publishedReadFailure(e).message;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Visitor • QR bản đồ công khai')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Không cần đăng nhập. Dùng mã QR do Creator tạo; chỉ tải snapshot đã được công khai.',
          ),
          TextField(
            key: const Key('public-qr-input'),
            controller: _code,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Mã WMQR1 hoặc URL /q/...',
            ),
          ),
          FilledButton(
            onPressed: _busy ? null : _open,
            child: const Text('Mở bản đồ từ QR'),
          ),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    final raw = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ScannerPage.capture(),
                      ),
                    );
                    if (raw != null && mounted) {
                      _code.text = raw;
                      await _open();
                    }
                  },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Quét bằng camera'),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!, key: const Key('public-map-error')),
          const Text(
            'Snapshot công khai không chứng minh vị trí liên tục, cửa hoặc khả năng tiếp cận xe lăn đã được kiểm chứng.',
          ),
        ],
      ),
    ),
  );
}
