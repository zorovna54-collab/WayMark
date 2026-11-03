import 'package:flutter/material.dart';
import 'package:waymark/features/indoor_tracking/pilot/local_pilot.dart';
import 'package:waymark/features/indoor_tracking/debug/sensor_probe_page.dart';
import 'package:waymark/features/scanner/public_map_entry_page.dart';
import 'package:waymark/services/published_map_api_service.dart';
import 'package:waymark/services/published_read_failure.dart';
import 'package:waymark/features/indoor_tracking/debug/pilot_evidence_panel.dart';

void main() {
  if (!const bool.fromEnvironment('WAYMARK_LIVE_TEST')) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Build Live Test cần WAYMARK_LIVE_TEST=true và flavor liveTest.',
            ),
          ),
        ),
      ),
    );
    return;
  }
  runApp(
    MaterialApp(
      title: 'WayMark Live Test',
      navigatorObservers: [sensorProbeRouteObserver],
      home: const LiveTestHome(),
    ),
  );
}

class LiveTestHome extends StatefulWidget {
  const LiveTestHome({super.key});
  @override
  State<LiveTestHome> createState() => _LiveTestHomeState();
}

class _LiveTestHomeState extends State<LiveTestHome> {
  final _endpoint = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _endpoint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('WayMark Live Test')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'MVP thử nghiệm • chưa nghiệm thu định vị thật. Không dùng để đảm bảo an toàn hoặc dẫn đường cấp cứu.',
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LocalLivePilotPage()),
          ),
          child: const Text('1. Local pilot — không cần API'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SensorProbePage()),
          ),
          child: const Text('Sensor Probe — kiểm tra phần cứng'),
        ),
        const Divider(height: 32),
        OutlinedButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PilotHandoffPage()),
          ),
          child: const Text(
            'Published Pilot • checklist & báo cáo (không USB)',
          ),
        ),
        const Text(
          '2. Published QR pilot — cần API reachable và QR thật. 10.0.2.2/localhost của máy tính không dùng trực tiếp trên điện thoại. Không tự mở public server.',
        ),
        TextField(
          controller: _endpoint,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'API base URL do bạn cấu hình (https://host/api)',
          ),
        ),
        OutlinedButton(
          onPressed: () {
            final value = publishedEndpoint(_endpoint.text);
            if (value == null) {
              setState(
                () => _error = 'Nhập http(s)://host/api; không token, query hoặc credentials.',
              );
              return;
            }
            setState(() => _error = null);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PublicMapEntryPage(
                  api: PublishedMapApiService(baseUrl: value),
                ),
              ),
            );
          },
          child: const Text('Mở QR Published • guest'),
        ),
        if (_error != null) Text(_error!),
        const Text(
          'Sau Search → Preview → Navigation, chọn Live opt-in. Diagnostics nằm trong panel Live; chỉ sao chép khi bạn nhấn nút.',
        ),
      ],
    ),
  );
}
