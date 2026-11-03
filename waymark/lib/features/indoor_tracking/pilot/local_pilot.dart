import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../admin/draft_map.dart';
import '../../admin/floor_plan_asset.dart';
import '../../admin/local_map_project.dart';
import '../../navigation/local_map_navigation.dart';
import '../../navigation/navigation_page.dart';

Future<({LocalMapProject project, LocalMapNavigation map})>
createLocalLivePilot() async {
  final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 1000, 600),
    Paint()..color = const Color(0xffe2e8f0),
  );
  final path = Path()
    ..moveTo(100, 300)
    ..lineTo(900, 300)
    ..moveTo(500, 60)
    ..lineTo(500, 540);
  canvas.drawPath(
    path,
    Paint()
      ..color = Colors.white
      ..strokeWidth = 60
      ..style = PaintingStyle.stroke,
  );
  final text = TextPainter(
    text: const TextSpan(
      text: 'LOCAL PILOT • sơ đồ giả định • mỗi đoạn 10m',
      style: TextStyle(color: Colors.black, fontSize: 24),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  text.paint(canvas, const Offset(25, 15));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1000, 600);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  final asset = await FloorPlanAsset.validate(
    bytes!.buffer.asUint8List(),
    'local-live-pilot.png',
    'image/png',
  );
  final ground = DraftMap.local(
    'Live Test local',
    'Synthetic pilot',
    'Pilot G',
    'G',
  )..image = asset;
  ground.putNode(const DraftNode('A', 'A • mốc đầu', .1, .5, 'Entrance'));
  ground.putNode(const DraftNode('J', 'J • giao lộ', .5, .5, 'Junction'));
  ground.putNode(
    const DraftNode(
      'E',
      'E • đích thẳng',
      .9,
      .5,
      'Entrance',
      searchableAsDestination: true,
    ),
  );
  ground.putNode(
    const DraftNode(
      'N',
      'N • nhánh rẽ',
      .5,
      .1,
      'Entrance',
      searchableAsDestination: true,
    ),
  );
  ground.putNode(const DraftNode('S', 'S • cầu thang', .5, .9, 'Stairs'));
  for (final pair in [('A', 'J'), ('J', 'E'), ('J', 'N'), ('J', 'S')]) {
    ground.addEdge(DraftEdge(pair.$1, pair.$2, 10, 'Corridor'));
    ground.addEdge(DraftEdge(pair.$2, pair.$1, 10, 'Corridor'));
  }
  final upper = DraftMap.local(
    'Live Test local',
    'Synthetic pilot',
    'Pilot 1',
    '1',
  )..image = asset;
  upper.putNode(
    const DraftNode('S1', 'S1 • cầu thang tầng mới', .5, .9, 'Stairs'),
  );
  upper.putNode(
    const DraftNode(
      'D1',
      'D1 • đích tầng 1',
      .5,
      .1,
      'Entrance',
      searchableAsDestination: true,
    ),
  );
  upper.addEdge(const DraftEdge('S1', 'D1', 10, 'Corridor'));
  upper.addEdge(const DraftEdge('D1', 'S1', 10, 'Corridor'));
  final project = LocalMapProject(ground)..floors.add(upper);
  project.links.add(
    LocalFloorLink(
      fromFloor: ground.localWorkspaceId!,
      fromNode: ground.nodeId('S'),
      toFloor: upper.localWorkspaceId!,
      toNode: upper.nodeId('S1'),
      meters: 3,
      type: 'Stairs',
    ),
  );
  project.links.add(
    LocalFloorLink(
      fromFloor: upper.localWorkspaceId!,
      fromNode: upper.nodeId('S1'),
      toFloor: ground.localWorkspaceId!,
      toNode: ground.nodeId('S'),
      meters: 3,
      type: 'Stairs',
    ),
  );
  return (project: project, map: await LocalMapNavigation.fromProject(project));
}

class LocalLivePilotPage extends StatefulWidget {
  const LocalLivePilotPage({super.key});
  @override
  State<LocalLivePilotPage> createState() => _LocalLivePilotPageState();
}

class _LocalLivePilotPageState extends State<LocalLivePilotPage> {
  late final _pilot = createLocalLivePilot();
  String? _destination;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Local pilot • không cần API')),
    body: FutureBuilder(
      future: _pilot,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Không tạo được local pilot.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final map = snapshot.requireData.map;
        final destinations = map.destinationNodes;
        final selected =
            _destination ??
            '${destinations.first.floorId}/${destinations.first.nodeId}';
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Sơ đồ tổng hợp, không phải bản đồ cơ sở thật. A–J, J–E, J–N và J–S giả định 10m/đoạn. Hãy bố trí hành lang thử đo đúng chiều dài này; không dùng tại nơi nguy hiểm.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: selected,
              isExpanded: true,
              items: [
                for (final d in destinations)
                  DropdownMenuItem(
                    value: '${d.floorId}/${d.nodeId}',
                    child: Text('${d.floorName} • ${d.name}'),
                  ),
              ],
              onChanged: (v) => setState(() => _destination = v),
              decoration: const InputDecoration(
                labelText: 'Chọn đích local pilot',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                final destination = destinations.singleWhere(
                  (d) => '${d.floorId}/${d.nodeId}' == selected,
                );
                final route = map.routeToNode(
                  map.startChoices.first.key,
                  destination.nodeId,
                  destination.floorId,
                );
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NavigationPage(
                      route: route,
                      localMap: map,
                      localLivePilot: true,
                    ),
                  ),
                );
              },
              child: const Text('Mở Navigation → chọn Live thử nghiệm'),
            ),
            const Text(
              'Mốc đầu A, không có QR server. Xác nhận Node thủ công được ghi là thử nghiệm. Dữ liệu cảm biến vẫn đến từ điện thoại thật; không phát bước giả.',
            ),
          ],
        );
      },
    ),
  );
}
