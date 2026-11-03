import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:waymark/features/admin/ai_graph_review.dart';
import 'package:waymark/features/admin/ai_graph_review_panel.dart';
import 'package:waymark/features/admin/ai_map_assistant_page.dart';
import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/admin/draft_map_editor.dart';
import 'package:waymark/features/admin/floor_plan_asset.dart';
import 'package:waymark/features/admin/local_map_project.dart';
import 'package:waymark/models/ai_graph_proposal.dart';
import 'package:waymark/models/ai_map_suggestion.dart';
import 'package:waymark/services/ai_map_provider.dart';
import 'package:waymark/services/auth_session.dart';

import 'floor_image_cleanup_test.dart' show cleanupTestImage;
import 'ai_map_assistant_test.dart' show proposal;
import 'draft_floor_workflow_test.dart' show MemoryDraftFiles;

Map<String, dynamic> graphJson(AiGraphInput input) => {
  'schemaVersion': 2,
  'floorId': input.floorId,
  'nodes': [
    {
      ...proposal(id: 'p1'),
      'nodeType': 'Junction',
      'normalizedX': .2,
      'normalizedY': .5,
      'floorId': input.floorId,
      'evidence': 'Visible corridor junction',
    },
    {
      ...proposal(id: 'p2'),
      'normalizedX': .8,
      'normalizedY': .5,
      'floorId': input.floorId,
      'evidence': 'Visible destination sign',
    },
  ],
  'edges': [
    {
      'proposedEdgeId': 'e1',
      'sourceNodeId': 'p1',
      'targetNodeId': 'p2',
      'floorId': input.floorId,
      'edgeType': 'Corridor',
      'directionHint': 'Unknown',
      'distanceMeters': null,
      'confidence': .6,
      'evidence': 'Visible continuous corridor',
      'uncertainty': 'Human must inspect passage, direction and metres',
    },
  ],
  'uncertainAreas': [
    {
      'label': 'Possible doorway',
      'normalizedX': .3,
      'normalizedY': .1,
      'reason': 'Door opening not clear',
    },
  ],
};
AiGraphProposal parseGraph(AiGraphInput input, Map<String, dynamic> json) =>
    AiGraphProposal.parse(
      jsonEncode(json),
      floorId: input.floorId,
      existingRefs: input.existingRefs,
    );
Future<(DraftMap, AiGraphInput)> source() async {
  final d = DraftMap.local('Test site', 'Test building', 'Ground', 'G')
    ..image = await cleanupTestImage();
  d.putNode(
    const DraftNode(
      'KEEP',
      'Existing QR anchor',
      .1,
      .1,
      'Entrance',
      wayMarkCode: 'TEST-ONLY',
    ),
  );
  return (d, AiGraphInput.capture(d, projectId: 'project-a'));
}

AiGraphBatch accepted(
  AiGraphInput input, {
  AiEdgeDirection direction = AiEdgeDirection.forward,
}) {
  final r = AiGraphReview(input, parseGraph(input, graphJson(input)));
  for (final n in r.nodes) {
    r.acceptNode(n.node.id);
  }
  r.acceptEdge('e1', meters: 7.25, direction: direction, confirmed: true);
  return r.batch();
}

// Only the explicit opt-in live smoke uses real sockets. Unit/widget tests
// keep Flutter's normal network isolation and fake providers.
class _LiveHttp extends HttpOverrides {}

class FakeGraphAi implements AiGraphProvider {
  FakeGraphAi({this.pending, this.offline = false});
  final Completer<AiGraphProposal>? pending;
  final bool offline;
  AiGraphInput? received;
  @override
  Future<List<String>> models() async => ['fake-vision-for-unit-test'];
  @override
  Future<AiMapResult> analyze(FloorPlanAsset image, String model) async =>
      AiMapResult.parse(
        jsonEncode({
          'nodes': [proposal()],
        }),
      );
  @override
  Future<AiGraphProposal> analyzeGraph(AiGraphInput input, String model) async {
    received = input;
    if (offline) {
      throw const AiMapException(
        AiMapFailure.connection,
        'AI offline; manual draft intact',
      );
    }
    if (pending != null) return pending!.future;
    return parseGraph(input, graphJson(input));
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(AuthSession.clear);
  test('Strict proposal on correct floor with unmeasured edges and uncertainty; capture is read-only', () async {
    final (d, input) = await source();
    final before = jsonEncode(d.toJson());
    final p = parseGraph(input, graphJson(input));
    expect(p.nodes, hasLength(2));
    expect(p.edges, hasLength(1));
    expect(p.areas, hasLength(1));
    expect(p.edges.single.floorId, input.floorId);
    expect(AiGraphInput.capture(d, projectId: 'project-a').stamp, input.stamp);
    expect(jsonEncode(d.toJson()), before);
  });
  for (final change in [
    {'sourceNodeId': 'missing'},
    {'targetNodeId': 'missing'},
    {'targetNodeId': 'p1'},
    {'floorId': 'another-floor'},
    {'distanceMeters': 5},
    {'edgeType': 'Teleport'},
    {'directionHint': 'surely-safe'},
    {'confidence': double.infinity},
    {'isAccessible': true},
  ]) {
    test('Invalid edge is discarded before review: $change', () async {
      final (_, input) = await source();
      final j = graphJson(input);
      (j['edges'] as List)[0] = <String, Object?>{
        ...(j['edges'] as List)[0] as Map<String, Object?>,
        ...change,
      };
      // JSON cannot represent infinity, test numeric bound using 2 instead.
      if (change['confidence'] == double.infinity) {
        (j['edges'] as List)[0]['confidence'] = 2;
      }
      final p = parseGraph(input, j);
      expect(p.edges, isEmpty);
      expect(p.discarded, 1);
      expect(p.nodes, hasLength(2));
    });
  }
  test(
    'Malformed JSON/root/wrong floor and normalized coordinates rejected',
    () async {
      final (_, input) = await source();
      for (final text in [
        '[]',
        'not JSON',
        jsonEncode({...graphJson(input), 'floorId': 'wrong'}),
        jsonEncode({...graphJson(input), 'publish': true}),
      ]) {
        expect(
          () => AiGraphProposal.parse(
            text,
            floorId: input.floorId,
            existingRefs: input.existingRefs,
          ),
          throwsFormatException,
        );
      }
      for (final bad in [-.1, 1.01, '0.5', null]) {
        final j = graphJson(input);
        (j['nodes'] as List)[0]['normalizedX'] = bad;
        final p = parseGraph(input, j);
        expect(p.nodes, hasLength(1));
        expect(p.edges, isEmpty);
      }
    },
  );
  test('Accept nodes does not write; edge requires endpoints, direction, metres and explicit confirmation', () async {
    final (d, input) = await source();
    final before = jsonEncode(d.toJson());
    final r = AiGraphReview(input, parseGraph(input, graphJson(input)));
    expect(
      () => r.acceptEdge(
        'e1',
        meters: 5,
        direction: AiEdgeDirection.forward,
        confirmed: true,
      ),
      throwsFormatException,
    );
    r.acceptNode('p1');
    r.acceptNode('p2');
    for (final meters in [null, 0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => r.acceptEdge(
          'e1',
          meters: meters,
          direction: AiEdgeDirection.forward,
          confirmed: true,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => r.acceptEdge('e1', meters: 5, confirmed: true),
      throwsFormatException,
    );
    expect(
      () => r.acceptEdge(
        'e1',
        meters: 5,
        direction: AiEdgeDirection.forward,
        confirmed: false,
      ),
      throwsFormatException,
    );
    expect(r.edgeStatus('e1'), AiReviewStatus.pending);
    expect(jsonEncode(d.toJson()), before);
    r.acceptEdge(
      'e1',
      meters: 5,
      direction: AiEdgeDirection.forward,
      confirmed: true,
    );
    expect(jsonEncode(d.toJson()), before);
    expect(r.batch().directedEdges, 1);
  });
  test('Edit/Reject node invalidates accepted dependent edges; rejected nodes do not enter batch', () async {
    final (_, input) = await source();
    final r = AiGraphReview(input, parseGraph(input, graphJson(input)));
    r.acceptNode('p1');
    r.acceptNode('p2');
    r.acceptEdge(
      'e1',
      meters: 5,
      direction: AiEdgeDirection.both,
      confirmed: true,
    );
    final n = r.nodes.first;
    r.editNode(
      AiGraphNode(
        AiMapSuggestion.parse({...n.node.toJson(), 'normalizedX': .3}),
        input.floorId,
        n.evidence,
      ),
    );
    expect(r.nodeStatus('p1'), AiReviewStatus.pending);
    expect(r.edgeStatus('e1'), AiReviewStatus.pending);
    expect(r.reviewedEdges, isEmpty);
    r.rejectNode('p2');
    expect(r.batch().nodes, isEmpty);
    r.acceptNode('p1');
    r.acceptNode('p2');
    r.editEdge('e1', from: 'p2', to: 'p1', type: 'Door');
    r.acceptEdge(
      'e1',
      meters: 4,
      direction: AiEdgeDirection.forward,
      confirmed: true,
    );
    expect(r.batch().edges.single.proposal.from, 'p2');
    r.rejectEdge('e1');
    expect(r.batch().edges, isEmpty);
  });
  test('Existing stable GUID references; reject duplicates, self-loop and cross-floor refs', () async {
    final (d, _) = await source();
    d.putNode(const DraftNode('B', 'Existing second', .8, .1, 'Junction'));
    d.addEdge(const DraftEdge('KEEP', 'B', 3, 'Corridor'));
    final input = AiGraphInput.capture(d, projectId: 'project-a');
    final j = graphJson(input);
    (j['edges'] as List)[0]['sourceNodeId'] = input.existing.first.ref;
    (j['edges'] as List)[0]['targetNodeId'] = input.existing.last.ref;
    final r = AiGraphReview(input, parseGraph(input, j));
    expect(
      () => r.acceptEdge(
        'e1',
        meters: 3,
        direction: AiEdgeDirection.forward,
        confirmed: true,
      ),
      throwsFormatException,
    );
    r.acceptEdge(
      'e1',
      meters: 3,
      direction: AiEdgeDirection.reverse,
      confirmed: true,
    );
    final batch = r.batch();
    applyAiGraphBatch(d, batch, projectId: 'project-a');
    expect(d.edges, hasLength(2));
    expect(d.edges.last.from, 'B');
    expect(d.nodeIds['KEEP'], input.existing.first.ref.substring(9));
  });
  test('Apply atomic, appends fresh IDs; bidirectional = two edges; undo preserves existing IDs/metres', () async {
    final (d, input) = await source();
    final before = jsonEncode(d.toJson());
    final oldIds = Map.of(d.nodeIds);
    final batch = accepted(input, direction: AiEdgeDirection.both);
    final applied = applyAiGraphBatch(d, batch, projectId: 'project-a');
    expect(d.nodes, hasLength(3));
    expect(d.edges, hasLength(2));
    expect(
      d.edges.every((e) => e.meters == 7.25 && e.isMeasured && e.isActive),
      isTrue,
    );
    expect(d.nodes.last.code, isNot('p2'));
    expect(d.nodeIds['KEEP'], oldIds['KEEP']);
    expect(d.nodes.last.landmarkNote, contains('AI chưa xác minh'));
    expect(d.edges.every((e) => e.toJson()['isAccessible'] == false), isTrue);
    applied.undo(d, projectId: 'project-a');
    expect(jsonEncode(d.toJson()), before);
  });
  for (final stale in ['image', 'project', 'graph']) {
    test('Reject stale $stale without partial mutation', () async {
      final (d, input) = await source();
      final batch = accepted(input);
      if (stale == 'image') d.image = await cleanupTestImage();
      if (stale == 'graph') d.putNode(d.nodes.single.at(.3, .1), replace: true);
      final before = jsonEncode(d.toJson());
      expect(
        () => applyAiGraphBatch(
          d,
          batch,
          projectId: stale == 'project' ? 'other' : 'project-a',
        ),
        throwsFormatException,
      );
      expect(jsonEncode(d.toJson()), before);
    });
  }
  test(
    'Wrong floor, forged invalid batch, and undo after manual changes are safe',
    () async {
      final (d, input) = await source();
      final other = DraftMap.local('S', 'B', 'L1', 'L1')..image = d.image;
      final batch = accepted(input);
      expect(
        () => applyAiGraphBatch(other, batch, projectId: 'project-a'),
        throwsFormatException,
      );
      final before = jsonEncode(d.toJson());
      final bad = AiGraphBatch(input, batch.nodes, [
        AiReviewedEdge(
          batch.edges.single.proposal,
          double.nan,
          AiEdgeDirection.forward,
        ),
      ]);
      expect(
        () => applyAiGraphBatch(d, bad, projectId: 'project-a'),
        throwsFormatException,
      );
      expect(jsonEncode(d.toJson()), before);
      final applied = applyAiGraphBatch(d, batch, projectId: 'project-a');
      d.putNode(const DraftNode('MANUAL', 'Keep manual', .4, .7, 'Junction'));
      final edited = jsonEncode(d.toJson());
      expect(
        () => applied.undo(d, projectId: 'project-a'),
        throwsFormatException,
      );
      expect(jsonEncode(d.toJson()), edited);
    },
  );
  test('JSON v2/v3 round trip and other floors retain graph/image; local route uses confirmed metres', () async {
    final (d, input) = await source();
    final other = DraftMap.local('S', 'B', 'L1', 'L1')
      ..image = await cleanupTestImage();
    final otherBefore = jsonEncode(other.toJson());
    final project = LocalMapProject(d)..floors.add(other);
    final applied = applyAiGraphBatch(
      d,
      accepted(input),
      projectId: 'project-a',
    );
    expect(
      d.shortestRoute(applied.nodes.first.code, applied.nodes.last.code).meters,
      7.25,
    );
    final floor = await openLocalDraft(d.encode());
    expect(floor.nodes, hasLength(3));
    expect(floor.edges.single.meters, 7.25);
    final loaded = await LocalMapProject.decode(project.encode());
    expect(loaded.floors, hasLength(2));
    expect(jsonEncode(loaded.floors[1].toJson()), otherBefore);
    expect(
      loaded.floors.first.nodes.last.landmarkNote,
      contains('AI chưa xác minh'),
    );
    expect(jsonEncode(other.toJson()), otherBefore);
  });
  test('Phase2 provider sends actual image, explicit floor and stable refs, never app JWT/metres', () async {
    final (d, input) = await source();
    AuthSession.accessToken = 'unit-app-jwt-never-send';
    final before = jsonEncode(d.toJson());
    final p = OpenAiMapProvider(
      baseUrl: 'http://localhost:1234/v1',
      token: 'unit-ai-token',
      client: MockClient((r) async {
        expect(r.headers['Authorization'], 'Bearer unit-ai-token');
        expect(r.followRedirects, isFalse);
        final body = jsonDecode(r.body);
        final content = body['messages'][0]['content'] as List;
        expect(
          (content[0]['text'] as String),
          contains(input.existing.single.ref),
        );
        expect((content[0]['text'] as String), contains(input.floorId));
        expect(body['max_tokens'], 3500);
        expect(
          base64Decode(
            (content[1]['image_url']['url'] as String).split(',').last,
          ),
          input.image.bytes,
        );
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {'content': jsonEncode(graphJson(input))},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final result = await p.analyzeGraph(input, 'unit-model');
    expect(result.edges, hasLength(1));
    expect(jsonEncode(d.toJson()), before);
    p.dispose();
  });

  Future<void> connect(WidgetTester t) async {
    await t.enterText(
      find.byKey(const Key('ai-url')),
      'http://localhost:1234/v1',
    );
    await t.ensureVisible(find.text('Kiểm tra kết nối / models'));
    await t.tap(find.text('Kiểm tra kết nối / models'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Phân tích ảnh bằng Vision'));
    await t.tap(find.text('Phân tích ảnh bằng Vision'));
    await t.pump();
  }

  testWidgets(
    'Review UI gates Edge metres/direction; final confirmation only returns batch, Cancel preserves Draft',
    (t) async {
      final image = (await t.runAsync(cleanupTestImage))!;
      final d = DraftMap.local('S', 'B', 'G', 'G')..image = image;
      final input = AiGraphInput.capture(d, projectId: 'p');
      final before = jsonEncode(d.toJson());
      AiGraphBatch? selected;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                child: const Text('Open AI'),
                onPressed: () async {
                  selected = await Navigator.push<AiGraphBatch>(
                    c,
                    MaterialPageRoute(
                      builder: (_) => AiMapAssistantPage(
                        image: image,
                        floorName: 'G',
                        graphInput: input,
                        providerFactory: (_, _) => FakeGraphAi(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await t.runAsync(
        () =>
            precacheImage(image.imageProvider, t.element(find.text('Open AI'))),
      );
      await t.tap(find.text('Open AI'));
      await t.pumpAndSettle();
      await connect(t);
      await t.pumpAndSettle();
      Future<void> tapKey(String key) async {
        final f = find.byKey(Key(key));
        if (f.evaluate().isEmpty) {
          await t.scrollUntilVisible(
            f,
            250,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await t.ensureVisible(f);
        await t.pumpAndSettle();
        await t.ensureVisible(f);
        await t.pumpAndSettle();
        await t.tap(f);
        await t.pumpAndSettle();
      }

      await tapKey('graph-accept-node-p1');
      await tapKey('graph-edit-node-p1');
      final dialog = find.byType(AlertDialog);
      await t.enterText(
        find.descendant(of: dialog, matching: find.byType(TextField)).first,
        'Edited junction',
      );
      await t.tap(find.text('Lưu chỉnh sửa'));
      await t.pumpAndSettle();
      await tapKey('graph-reject-node-p1');
      await tapKey('graph-accept-node-p1');
      await tapKey('graph-accept-node-p2');
      await tapKey('graph-accept-edge-e1');
      await t.tap(find.byKey(const Key('ai-edge-save')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ai-edge-error')), findsOneWidget);
      await t.enterText(find.byKey(const Key('ai-edge-meters')), '5.25');
      await t.tap(find.byKey(const Key('ai-edge-direction')));
      await t.pumpAndSettle();
      await t.tap(find.text('Source → Target').last);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('ai-edge-confirm')));
      await t.tap(find.byKey(const Key('ai-edge-confirm')));
      await t.tap(find.byKey(const Key('ai-edge-save')));
      await t.pumpAndSettle();
      expect(jsonEncode(d.toJson()), before);
      expect(selected, isNull);
      await tapKey('ai-graph-apply');
      await t.tap(find.text('Hủy'));
      await t.pumpAndSettle();
      expect(jsonEncode(d.toJson()), before);
      expect(selected, isNull);
      await tapKey('ai-graph-apply');
      await t.tap(find.byKey(const Key('ai-graph-final-confirm')));
      await t.pumpAndSettle();
      expect(selected!.edges.single.meters, 5.25);
      expect(jsonEncode(d.toJson()), before);
      applyAiGraphBatch(d, selected!, projectId: 'p');
      expect(d.nodes.first.name, 'Edited junction');
      expect(d.edges.single.meters, 5.25);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Cancelled/stale async response and offline provider never mutate Draft',
    (t) async {
      final image = (await t.runAsync(cleanupTestImage))!;
      final d = DraftMap.local('S', 'B', 'G', 'G')..image = image;
      final before = jsonEncode(d.toJson());
      final input = AiGraphInput.capture(d, projectId: 'p');
      final pending = Completer<AiGraphProposal>();
      final fake = FakeGraphAi(pending: pending);
      await t.pumpWidget(
        MaterialApp(
          home: AiMapAssistantPage(
            image: image,
            floorName: 'G',
            graphInput: input,
            providerFactory: (_, _) => fake,
          ),
        ),
      );
      await connect(t);
      await t.pump(const Duration(milliseconds: 100));
      await t.ensureVisible(find.byKey(const Key('ai-cancel-request')));
      await t.tap(find.byKey(const Key('ai-cancel-request')));
      await t.pumpAndSettle();
      pending.complete(parseGraph(input, graphJson(input)));
      await t.pumpAndSettle();
      expect(find.byType(AiGraphReviewPanel), findsNothing);
      expect(jsonEncode(d.toJson()), before);
      final other = DraftMap.local('S', 'B', 'L1', 'L1')..image = image;
      final next = AiGraphInput.capture(other, projectId: 'p');
      await t.pumpWidget(
        MaterialApp(
          home: AiMapAssistantPage(
            image: image,
            floorName: 'L1',
            graphInput: next,
            providerFactory: (_, _) => FakeGraphAi(offline: true),
          ),
        ),
      );
      await t.pumpAndSettle();
      await connect(t);
      await t.pumpAndSettle();
      expect(find.textContaining('AI offline'), findsOneWidget);
      expect(jsonEncode(d.toJson()), before);
    },
  );

  testWidgets(
    'In-flight result is ignored when image/floor/project input changes',
    (t) async {
      final image = (await t.runAsync(cleanupTestImage))!;
      final d = DraftMap.local('S', 'B', 'G', 'G')..image = image;
      final input = AiGraphInput.capture(d, projectId: 'p');
      final pending = Completer<AiGraphProposal>();
      await t.pumpWidget(
        MaterialApp(
          home: AiMapAssistantPage(
            image: image,
            floorName: 'G',
            graphInput: input,
            providerFactory: (_, _) => FakeGraphAi(pending: pending),
          ),
        ),
      );
      await connect(t);
      final other = DraftMap.local('S', 'B', 'L1', 'L1')..image = image;
      final next = AiGraphInput.capture(other, projectId: 'other-project');
      await t.pumpWidget(
        MaterialApp(
          home: AiMapAssistantPage(
            image: image,
            floorName: 'L1',
            graphInput: next,
            providerFactory: (_, _) => FakeGraphAi(),
          ),
        ),
      );
      pending.complete(parseGraph(input, graphJson(input)));
      await t.pumpAndSettle();
      expect(find.byType(AiGraphReviewPanel), findsNothing);
      expect(d.nodes, isEmpty);
      expect(other.nodes, isEmpty);
    },
  );

  testWidgets('Builder AI confirmation -> local JSON v3 save/load', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final image = (await t.runAsync(cleanupTestImage))!;
    final d = DraftMap.local('S', 'B', 'G', 'G')..image = image;
    final files = MemoryDraftFiles();
    final project = LocalMapProject(d);
    project.floors.add(DraftMap.local('S', 'B', 'L1', 'L1')..image = image);
    await t.pumpWidget(
      MaterialApp(
        home: DraftMapEditor(
          initialProject: project,
          files: files,
          aiProviderFactory: (_, _) => FakeGraphAi(),
        ),
      ),
    );
    await t.runAsync(
      () => precacheImage(
        image.imageProvider,
        t.element(find.byType(DraftMapEditor)),
      ),
    );
    await t.pumpAndSettle();
    Future<void> tap(String key) async {
      final f = find.byKey(Key(key));
      if (f.evaluate().isEmpty) {
        await t.scrollUntilVisible(
          f,
          200,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await t.ensureVisible(f);
      await t.pumpAndSettle();
      await t.ensureVisible(f);
      await t.pumpAndSettle();
      await t.tap(f);
      await t.pumpAndSettle();
    }

    await tap('ai-map-assistant');
    await connect(t);
    await t.pumpAndSettle();
    await tap('graph-accept-node-p1');
    await tap('graph-reject-node-p2');
    expect(d.nodes, isEmpty);
    await tap('ai-graph-apply');
    await tap('ai-graph-final-confirm');
    expect(d.nodes, hasLength(1));
    expect(d.edges, isEmpty);
    await tap('export-draft');
    final loaded = (await t.runAsync(
      () => LocalMapProject.decode(files.saved!),
    ))!;
    expect(loaded.id, project.id);
    expect(loaded.floors, hasLength(2));
    expect(loaded.floors.first.nodeIds, d.nodeIds);
    expect(loaded.floors.first.image!.bytes, image.bytes);
    expect(loaded.floors.last.nodes, isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'AI overlay pixels: centers follow zoom/pan, marker diameter stays fixed at 1x/2x/4x',
    (t) async {
      final image = (await t.runAsync(cleanupTestImage))!;
      final d = DraftMap.local('S', 'B', 'G', 'G')..image = image;
      final input = AiGraphInput.capture(d, projectId: 'p');
      final review = AiGraphReview(input, parseGraph(input, graphJson(input)));
      final diameters = <int>[];
      for (final scale in [1.0, 2.0, 4.0]) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)
          ..drawColor(Colors.white, BlendMode.src)
          ..translate(25, 20)
          ..scale(scale);
        AiProposalPainter(
          review,
          viewScale: scale,
        ).paint(canvas, const Size(200, 100));
        final picture = recorder.endRecording();
        final raster = (await t.runAsync(() => picture.toImage(900, 500)))!;
        final bytes = (await t.runAsync(
          () => raster.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        final x = (25 + 40 * scale).round(), y = (20 + 50 * scale).round();
        final marker = <int>[];
        for (var dx = -18; dx <= 18; dx++) {
          final p = (y * 900 + x + dx) * 4;
          if (bytes.getUint8(p) > 130 &&
              bytes.getUint8(p + 1) < 100 &&
              bytes.getUint8(p + 2) < 70) {
            marker.add(dx);
          }
        }
        expect(marker, isNotEmpty);
        diameters.add(marker.last - marker.first + 1);
        raster.dispose();
        picture.dispose();
      }
      expect(
        diameters.every((d) => (d - diameters.first).abs() <= 1),
        isTrue,
        reason: '$diameters',
      );
    },
  );

  const live = bool.fromEnvironment('WAYMARK_AI_PHASE2_LIVE');
  test(
    'LM Studio REAL image graph proposal (opt-in, never SQL)',
    () async {
      const path = String.fromEnvironment('WAYMARK_AI_PHASE2_IMAGE');
      const url = String.fromEnvironment('WAYMARK_AI_BASE_URL');
      expect(path, isNotEmpty);
      expect(url, isNotEmpty);
      final file = File(path);
      final image = await FloorPlanAsset.validate(
        await file.readAsBytes(),
        file.uri.pathSegments.last,
        path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg',
      );
      final d = DraftMap.local('Local vision test', 'Test', 'G', 'G')
        ..image = image;
      final input = AiGraphInput.capture(d, projectId: 'vision-smoke');
      final liveClient = IOClient(_LiveHttp().createHttpClient(null));
      final p = OpenAiMapProvider(
        baseUrl: url,
        timeout: const Duration(seconds: 300),
        client: liveClient,
      );
      try {
        final models = await p.models();
        final model = models.firstWhere((id) => id == 'qwen/qwen3-vl-8b');
        final before = jsonEncode(d.toJson());
        final result = await p.analyzeGraph(input, model);
        final evidence = Directory('build/ai-phase2-evidence')
          ..createSync(recursive: true);
        await File('${evidence.path}/live-proposal.json').writeAsString(
          jsonEncode({
            'model': model,
            'imageName': image.name,
            'floorId': input.floorId,
            'nodes': [
              for (final n in result.nodes)
                {
                  ...n.node.toJson(),
                  'floorId': n.floorId,
                  'evidence': n.evidence,
                },
            ],
            'edges': [
              for (final e in result.edges)
                {
                  'id': e.id,
                  'from': e.from,
                  'to': e.to,
                  'evidence': e.evidence,
                  'uncertainty': e.uncertainty,
                  'type': e.type,
                },
            ],
            'areas': [
              for (final a in result.areas)
                {'label': a.name, 'reason': a.reason},
            ],
            'discarded': result.discarded,
          }),
        );
        expect(jsonEncode(d.toJson()), before);
        expect(
          result.nodes.isNotEmpty ||
              result.edges.isNotEmpty ||
              result.areas.isNotEmpty,
          isTrue,
        );
      } finally {
        p.dispose();
        liveClient.close();
      }
    },
    skip: !live,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
