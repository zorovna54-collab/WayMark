import 'package:flutter/material.dart';

import 'map_readiness.dart';

class PublishedLivePreflight extends StatelessWidget {
  const PublishedLivePreflight({
    super.key,
    required this.report,
    required this.onManual,
    this.sensorMessage = 'Cảm biến sẽ được kiểm tra ở bước 2.',
    this.surveyed = const {},
  });
  final MapReadinessReport report;
  final VoidCallback onManual;
  final String sensorMessage;
  final Set<String> surveyed;
  @override
  Widget build(BuildContext context) {
    String node(String id) {
      final name = report.input.nodes
          .where((n) => n.id == id)
          .firstOrNull
          ?.name;
      return name == null ||
              name.trim().isEmpty ||
              MapReadinessValidator.validGuid(name)
          ? 'Điểm trên bản đồ'
          : name;
    }

    final images = report.input.floors.where((f) => f.imageReady).length;
    final global = report.issues
        .where(
          (i) => i.edge == null && i.reasonCode != 'physicalSurveyRequired',
        )
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Kiểm tra bản đồ Published trước khi đi',
              key: Key('published-live-preflight'),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Snapshot đã tải • Published phiên bản ${report.input.pin?.version ?? 'chưa hợp lệ'}',
            ),
            Text(
              'Ảnh tầng sẵn sàng: $images/${report.input.floors.length}. Điểm bắt đầu: ${report.input.routeNodes.isEmpty ? 'chưa hợp lệ' : node(report.input.routeNodes.first)}.',
            ),
            Text(
              '${report.eligibleRouteEdges}/${report.routeEdges} đoạn tuyến đủ điều kiện dữ liệu để ước lượng theo bước.',
              key: const Key('preflight-route-count'),
            ),
            if (!report.canStartLive)
              const Text(
                'Bản đồ chưa có đủ dữ liệu để bật Live trên tuyến này. Bạn vẫn có thể dùng chỉ đường thủ công.',
                key: Key('preflight-blocked'),
              )
            else if (!report.readyByData)
              const Text(
                'Chỉ hỗ trợ Live trên một số đoạn. Các đoạn còn lại cần manual/QR, không tự chuyển tầng.',
              ),
            const Text(
              'Đủ dữ liệu không có nghĩa đã khảo sát thực tế. Đối chiếu hành lang thẳng và chiều dài tại bước 4; không có chứng nhận độ chính xác.',
            ),
            for (final i in global.take(6))
              Text('${i.message} ${i.suggestedAction}'),
            ExpansionTile(
              title: const Text('Xem từng đoạn tuyến và ảnh tầng'),
              children: [
                for (final f in report.input.floors)
                  Text(
                    '${f.name}: ${f.imageReady ? 'ảnh đã tải và decode' : 'không tìm thấy ảnh tầng cần hiển thị'}',
                  ),
                for (final e in report.onRoute)
                  ListTile(
                    title: Text('${node(e.edge.from)} → ${node(e.edge.to)}'),
                    subtitle: Text(
                      !e.eligibleByData
                          ? '${e.reasonCode == 'floorTransition' ? 'Chuyển tầng: xác nhận tại tầng mới' : 'Chưa hỗ trợ Live trên đoạn này'} — manual/QR. ${report.issues.where((i) => i.edge == e.edge.id).firstOrNull?.message ?? ''}'
                          : surveyed.contains(e.edge.id) || e.physicallySurveyed
                          ? 'Đủ dữ liệu • bạn đã xác nhận đối chiếu trong phiên này, không phải chứng nhận khảo sát độc lập.'
                          : 'Đủ dữ liệu • chưa xác nhận chiều dài/hình học thực tế.',
                    ),
                  ),
              ],
            ),
            Text(sensorMessage),
            const Text(
              'Tiếp theo: bước 1 xác nhận vị trí/QR; bước 2 cảm biến; bước 3 chiều dài bước; bước 4 hành lang/hướng; bước 5 bắt đầu.',
            ),
            TextButton(
              key: const Key('preflight-manual'),
              onPressed: onManual,
              child: const Text('Dùng chỉ đường thủ công / QR'),
            ),
          ],
        ),
      ),
    );
  }
}
