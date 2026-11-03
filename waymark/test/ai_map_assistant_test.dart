import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/admin/ai_map_assistant_page.dart';
import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/admin/floor_plan_asset.dart';
import 'package:waymark/models/ai_map_suggestion.dart';
import 'package:waymark/services/ai_map_provider.dart';

import 'floor_image_cleanup_test.dart' show cleanupTestImage;

Map<String, Object?> proposal({String id = 'p1'}) => {
  'proposedNodeId': id,
  'displayName': 'Phòng khám',
  'nodeType': 'Destination',
  'normalizedX': .25,
  'normalizedY': .75,
  'suggestedAsDestination': true,
  'landmarkNote': null,
  'confidence': .7,
  'uncertainty': 'Cần kiểm tra cửa và vị trí thực địa',
};
String resultJson() => jsonEncode({
  'nodes': [proposal()],
});

class FakeAi implements AiMapProvider {
  FakeAi({this.offline = false});
  final bool offline;
  int calls = 0;
  @override
  Future<List<String>> models() async => ['actual-server-id'];
  @override
  Future<AiMapResult> analyze(FloorPlanAsset image, String model) async {
    calls++;
    if (offline) {
      throw const AiMapException(
        AiMapFailure.connection,
        'AI offline • bản nháp giữ nguyên',
      );
    }
    return AiMapResult.parse(resultJson());
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Strict valid schema and fenced JSON; no implicit graph writes', () {
    final result = AiMapResult.parse('```json\n${resultJson()}\n```');
    expect(result.nodes.single.x, .25);
    expect(result.nodes.single.uncertainty, contains('kiểm tra'));
  });
  for (final invalid in [
    {'normalizedX': -0.1},
    {'normalizedY': 1.1},
    {'normalizedX': '0.5'},
    {'nodeType': 'Room'},
    {'suggestedAsDestination': 'true'},
    {'confidence': 2},
    {'displayName': ''},
    {'uncertainty': null},
    {'landmarkNote': 42},
  ]) {
    test('Reject malformed field $invalid', () {
      expect(
        () => AiMapResult.parse(
          jsonEncode({
            'nodes': [
              {...proposal(), ...invalid},
            ],
          }),
        ),
        throwsFormatException,
      );
    });
  }
  test(
    'Discard invalid and duplicate proposals without trusting surrounding text',
    () {
      final result = AiMapResult.parse(
        jsonEncode({
          'nodes': [
            proposal(),
            proposal(),
            {'bad': true},
          ],
        }),
      );
      expect(result.nodes.length, 1);
      expect(result.rejected, 2);
      expect(
        () => AiMapResult.parse('Here is JSON: ${resultJson()}'),
        throwsFormatException,
      );
      expect(() => AiMapResult.parse('[]'), throwsFormatException);
    },
  );
  test('Normalized coordinates independent of image aspect ratio', () {
    final n = AiMapSuggestion.parse(proposal());
    for (final size in [const Size(900, 598), const Size(400, 1000)]) {
      final position = Offset(n.x * size.width, n.y * size.height);
      expect(position.dx / size.width, .25);
      expect(position.dy / size.height, .75);
    }
  });
  test('Provider sends actual image_url, MIME, model and isolated token; parses response', () async {
    final image = await cleanupTestImage();
    final provider = OpenAiMapProvider(
      baseUrl: 'http://localhost:1234/v1/',
      token: 'local-test-only',
      client: MockClient((r) async {
        expect(r.followRedirects, false);
        expect(r.headers['Authorization'], 'Bearer local-test-only');
        if (r.method == 'GET') {
          expect(r.url.path, '/v1/models');
          return http.Response('{"data":[{"id":"model-from-server"}]}', 200);
        }
        expect(r.url.path, '/v1/chat/completions');
        final body = jsonDecode(r.body);
        expect(body['model'], 'model-from-server');
        final url =
            body['messages'][0]['content'][1]['image_url']['url'] as String;
        expect(base64Decode(url.split(',').last), image.bytes);
        expect(url.startsWith('data:image/png;base64,'), true);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {'content': resultJson()},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    expect(await provider.models(), ['model-from-server']);
    expect(
      (await provider.analyze(image, 'model-from-server')).nodes.length,
      1,
    );
    provider.dispose();
  });
  for (final (status, kind) in [
    (401, AiMapFailure.authentication),
    (404, AiMapFailure.noModel),
    (422, AiMapFailure.unsupportedImage),
    (503, AiMapFailure.server),
    (302, AiMapFailure.server),
  ]) {
    test(
      'Provider classifies HTTP $status without exposing server body',
      () async {
        final image = await cleanupTestImage();
        final p = OpenAiMapProvider(
          baseUrl: 'http://localhost/v1',
          client: MockClient(
            (_) async => http.Response('sensitive server detail', status),
          ),
        );
        await expectLater(
          p.analyze(image, 'id'),
          throwsA(
            isA<AiMapException>()
                .having((e) => e.kind, 'kind', kind)
                .having(
                  (e) => e.message,
                  'message',
                  isNot(contains('sensitive')),
                ),
          ),
        );
      },
    );
  }
  test(
    'Provider timeout, invalid response, empty models and unsafe URL',
    () async {
      final image = await cleanupTestImage();
      final p = OpenAiMapProvider(
        baseUrl: 'http://localhost/v1',
        timeout: const Duration(milliseconds: 1),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        p.analyze(image, 'id'),
        throwsA(
          isA<AiMapException>().having(
            (e) => e.kind,
            'kind',
            AiMapFailure.timeout,
          ),
        ),
      );
      final empty = OpenAiMapProvider(
        baseUrl: 'http://localhost/v1',
        client: MockClient((_) async => http.Response('{"data":[]}', 200)),
      );
      expect(await empty.models(), isEmpty);
      final invalid = OpenAiMapProvider(
        baseUrl: 'http://localhost/v1',
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await expectLater(
        invalid.analyze(image, 'id'),
        throwsA(isA<AiMapException>()),
      );
      for (final url in [
        'file:///v1',
        'http://token@localhost/v1',
        'http://localhost/v1?token=x',
        'http://localhost',
      ]) {
        expect(() => OpenAiMapProvider(baseUrl: url), throwsFormatException);
      }
    },
  );
  test('Explicit reviewed commit appends only; JSON roundtrip preserves data and stale image blocks write', () async {
    final image = await cleanupTestImage();
    final draft = DraftMap.local('Site', 'Building', 'Floor', 'G')
      ..image = image;
    draft.putNode(const DraftNode('existing', 'Existing', .1, .2, 'Entrance'));
    final before = draft.encode();
    final suggestions = AiMapResult.parse(resultJson()).nodes;
    expect(draft.encode(), before); // Analysis alone makes no mutation.
    appendReviewedAiNodes(draft, image, suggestions);
    expect(draft.nodes.first.code, 'existing');
    expect(draft.nodes.last.code, startsWith('AI-'));
    expect(draft.nodes.last.landmarkNote, contains('chưa xác minh'));
    expect(draft.edges, isEmpty);
    final reopened = await openLocalDraft(draft.encode());
    expect(reopened.nodes.last.landmarkNote, contains('chưa xác minh'));
    expect(reopened.nodes.first.code, 'existing');
    final count = draft.nodes.length;
    final other = await cleanupTestImage();
    expect(
      () => appendReviewedAiNodes(draft, other, suggestions),
      throwsFormatException,
    );
    expect(draft.nodes.length, count);
  });
  test(
    'Resize transport copy preserves aspect ratio and original bytes',
    () async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 1200, 600),
        Paint()..color = Colors.blue,
      );
      final picture = recorder.endRecording(),
          decoded = await picture.toImage(1200, 600);
      final data = (await decoded.toByteData(format: ui.ImageByteFormat.png))!;
      final image = await FloorPlanAsset.validate(
        data.buffer.asUint8List(),
        'wide.png',
        'image/png',
      );
      decoded.dispose();
      picture.dispose();
      final original = Uint8List.fromList(image.bytes);
      final p = OpenAiMapProvider(
        baseUrl: 'http://localhost/v1',
        client: MockClient((r) async {
          final body = jsonDecode(r.body);
          final url =
              body['messages'][0]['content'][1]['image_url']['url'] as String;
          final codec = await ui.instantiateImageCodec(
            base64Decode(url.split(',').last),
          );
          final frame = await codec.getNextFrame();
          expect(frame.image.width, 768);
          expect(frame.image.height, 384);
          frame.image.dispose();
          codec.dispose();
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': resultJson()},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      expect((await p.analyze(image, 'id')).nodes.single.x, .25);
      expect(image.bytes, original);
    },
  );
  test('Oversize image rejected before network; invalid batch cannot partially append', () async {
    final image = await cleanupTestImage();
    final padded = Uint8List(4 * 1024 * 1024 + 1)
      ..setRange(0, image.bytes.length, image.bytes);
    final large = await FloorPlanAsset.validate(
      padded,
      'large.png',
      'image/png',
    );
    var calls = 0;
    final p = OpenAiMapProvider(
      baseUrl: 'http://localhost/v1',
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(p.analyze(large, 'id'), throwsFormatException);
    expect(calls, 0);
    final draft = DraftMap.local('S', 'B', 'G', 'G')..image = image;
    final valid = AiMapSuggestion.parse(proposal());
    const invalid = AiMapSuggestion(
      id: 'invalid',
      name: '',
      type: 'Destination',
      x: .1,
      y: .2,
      destination: true,
      confidence: .5,
      uncertainty: 'unknown',
    );
    expect(
      () => appendReviewedAiNodes(draft, image, [valid, invalid]),
      throwsFormatException,
    );
    expect(draft.nodes, isEmpty);
    expect(draft.image, same(image));
  });
  for (final offline in [false, true]) {
    testWidgets(
      'Review ${offline ? 'offline preserves graph' : 'Accept Edit Reject explicit commit'}',
      (tester) async {
        final image = (await tester.runAsync(cleanupTestImage))!;
        final fake = FakeAi(offline: offline);
        List<AiMapSuggestion>? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (c) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    selected = await Navigator.push<List<AiMapSuggestion>>(
                      c,
                      MaterialPageRoute(
                        builder: (_) => AiMapAssistantPage(
                          image: image,
                          floorName: 'G',
                          providerFactory: (_, _) => fake,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => precacheImage(
            image.imageProvider,
            tester.element(find.text('Open')),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('ai-url')),
          'http://10.0.2.2:1234/v1',
        );
        await tester.tap(find.text('Kiểm tra kết nối / models'));
        await tester.pumpAndSettle();
        expect(find.textContaining('CHƯA kiểm chứng Vision'), findsOneWidget);
        await tester.ensureVisible(find.text('Phân tích ảnh bằng Vision'));
        await tester.tap(find.text('Phân tích ảnh bằng Vision'));
        await tester.pumpAndSettle();
        expect(fake.calls, 1);
        expect(selected, isNull);
        if (offline) {
          expect(find.textContaining('AI offline'), findsOneWidget);
        } else {
          await tester.ensureVisible(find.byKey(const Key('accept-0')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('accept-0')));
          await tester.pumpAndSettle();
          expect(selected, isNull);
          await tester.tap(find.byKey(const Key('reject-0')));
          await tester.pumpAndSettle();
          expect(find.text('Đã Reject'), findsOneWidget);
          await tester.tap(find.byKey(const Key('edit-0')));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.widgetWithText(TextField, 'Tên điểm đến'),
            'Đích đã sửa',
          );
          await tester.tap(find.text('Lưu chỉnh sửa'));
          await tester.pumpAndSettle();
          expect(find.textContaining('Đích đã sửa'), findsOneWidget);
          await tester.tap(find.byKey(const Key('accept-0')));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byKey(const Key('ai-add-reviewed')));
          await tester.tap(find.byKey(const Key('ai-add-reviewed')));
          await tester.pumpAndSettle();
          expect(selected, isNull);
          await tester.tap(find.text('Xác nhận thêm'));
          await tester.pumpAndSettle();
          expect(selected!.single.name, 'Đích đã sửa');
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
