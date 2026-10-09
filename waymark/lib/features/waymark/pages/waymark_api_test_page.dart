import 'package:flutter/material.dart';

import '../../../services/waymark_api_service.dart';

class WayMarkApiTestPage extends StatefulWidget {
  const WayMarkApiTestPage({super.key});

  @override
  State<WayMarkApiTestPage> createState() => _WayMarkApiTestPageState();
}

class _WayMarkApiTestPageState extends State<WayMarkApiTestPage> {
  late Future<List<WayMark>> _wayMarksFuture;

  @override
  void initState() {
    super.initState();
    _wayMarksFuture = WayMarkApiService().getWayMarks();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('WayMark API Test')),
    body: FutureBuilder<List<WayMark>>(
      future: _wayMarksFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Lỗi khi tải dữ liệu: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final wayMarks = snapshot.data ?? const <WayMark>[];
        if (wayMarks.isEmpty) {
          return const Center(child: Text('Không có WayMark nào.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: wayMarks.length,
          itemBuilder: (context, index) {
            final wayMark = wayMarks[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text(wayMark.name),
                subtitle: Text(
                  'Location: ${wayMark.location}\n'
                  'WayMark Code: ${wayMark.wayMarkCode}',
                ),
                isThreeLine: true,
              ),
            );
          },
        );
      },
    ),
  );
}
