import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/admin/ai_map_assistant_page.dart';
import 'package:waymark/features/admin/ai_timeout_control.dart';
import 'package:waymark/features/admin/floor_plan_asset.dart';
import 'package:waymark/models/ai_map_suggestion.dart';
import 'package:waymark/services/ai_map_provider.dart';
import 'package:waymark/services/ai_timeout_preferences.dart';
import 'package:waymark/services/auth_session.dart';

import 'floor_image_cleanup_test.dart' show cleanupTestImage;
import 'ai_map_assistant_test.dart' show resultJson;

class MemoryAiSettings extends AiTimeoutPreferences {
  final values = <String, int>{};
  @override
  Future<int?> read(String scope) async => values[scope];
  @override
  Future<bool> write(String scope, int seconds) async {
    values[scope] = seconds;
    return true;
  }
}

class RetryAi implements AiMapProvider {
  int calls = 0;
  final delayed = Completer<AiMapResult>();
  @override
  Future<List<String>> models() async => ['vision-test-id'];
  @override
  Future<AiMapResult> analyze(FloorPlanAsset image, String model) async {
    calls++;
    if (calls == 1) {
      throw const AiMapException(
        AiMapFailure.timeout,
        'AI hết thời gian chờ. Bản nháp giữ nguyên.',
      );
    }
    if (calls == 2) return delayed.future;
    return AiMapResult.parse(resultJson());
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(AuthSession.clear);
  test(
    'Timeout validation: presets, boundaries, malformed or fractional values',
    () {
      for (final seconds in [...AiTimeoutPreferences.presets, 10, 600, 417]) {
        expect(AiTimeoutPreferences.parse('$seconds'), seconds);
      }
      for (final invalid in [
        '',
        '9',
        '601',
        '-1',
        'Infinity',
        '1e2',
        '3.5',
        '120s',
        '0120',
      ]) {
        expect(AiTimeoutPreferences.parse(invalid), isNull, reason: invalid);
      }
    },
  );
  test('Native preferences roundtrip scopes; corrupt value falls back; no URL/token stored', () async {
    const channel = MethodChannel('waymark/ai_preferences');
    final values = <String, int>{};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      expect(
        args.keys,
        unorderedEquals(
          call.method == 'writeTimeout' ? ['scope', 'seconds'] : ['scope'],
        ),
      );
      if (call.method == 'readTimeout') return values[args['scope']];
      values[args['scope']] = args['seconds'];
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    const first = AiTimeoutPreferences(), reopened = AiTimeoutPreferences();
    final graph = AiTimeoutPreferences.scope(true),
        nodes = AiTimeoutPreferences.scope(false);
    expect(await first.read(graph), isNull);
    await first.write(graph, 417);
    await first.write(nodes, 60);
    expect(await reopened.read(graph), 417);
    expect(await reopened.read(nodes), 60);
    values[graph] = 9999;
    expect(await reopened.read(graph), isNull);
    expect(() => first.write(graph, 0), throwsFormatException);
  });
  for (final width in [320.0, 360.0, 393.0, 430.0]) {
    testWidgets(
      'Preset/custom timeout at width $width, invalid input cannot be silently accepted',
      (t) async {
        t.view.physicalSize = Size(width, 820);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        int? chosen = 300;
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (c, update) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: AiTimeoutControl(
                    seconds: chosen ?? 300,
                    enabled: true,
                    onChanged: (v) => update(() => chosen = v),
                  ),
                ),
              ),
            ),
          ),
        );
        for (final seconds in AiTimeoutPreferences.presets) {
          await t.tap(find.byType(DropdownButtonFormField<int>));
          await t.pumpAndSettle();
          await t.tap(find.text('$seconds giây').last);
          await t.pumpAndSettle();
          expect(chosen, seconds);
        }
        await t.tap(find.byType(DropdownButtonFormField<int>));
        await t.pumpAndSettle();
        await t.tap(find.text('Tùy chỉnh…').last);
        await t.pumpAndSettle();
        for (final invalid in ['9', '601', 'abc']) {
          await t.enterText(
            find.byKey(const Key('ai-timeout-custom')),
            invalid,
          );
          await t.pump();
          expect(chosen, isNull);
          expect(
            find.text('Nhập số nguyên từ 10 đến 600 giây.'),
            findsOneWidget,
          );
        }
        await t.enterText(find.byKey(const Key('ai-timeout-custom')), '417');
        await t.pump();
        expect(chosen, 417);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'AI page remembers custom timeout on reopen without changing URL/model/token; retry/cancel ignores late reply',
    (t) async {
      final image = (await t.runAsync(cleanupTestImage))!;
      final prefs = MemoryAiSettings();
      final fake = RetryAi();
      AuthSession.accessToken = 'unit-app-token-kept';
      Widget page(Key key) => MaterialApp(
        home: AiMapAssistantPage(
          key: key,
          image: image,
          floorName: 'G',
          timeoutPreferences: prefs,
          providerFactory: (_, _) => fake,
        ),
      );
      await t.pumpWidget(page(const ValueKey('first')));
      await t.runAsync(
        () => precacheImage(
          image.imageProvider,
          t.element(find.byType(AiMapAssistantPage)),
        ),
      );
      await t.pumpAndSettle();
      Future<void> tap(Finder f) async {
        await t.ensureVisible(f);
        await t.pumpAndSettle();
        await t.tap(f);
        await t.pumpAndSettle();
      }

      await t.enterText(
        find.byKey(const Key('ai-url')),
        'http://localhost:1234/v1',
      );
      await tap(find.text('Kiểm tra kết nối / models'));
      final timeout = find.byType(DropdownButtonFormField<int>);
      await tap(timeout);
      await tap(find.text('Tùy chỉnh…').last);
      await t.enterText(find.byKey(const Key('ai-timeout-custom')), '417');
      await t.pumpAndSettle();
      expect(prefs.values[AiTimeoutPreferences.scope(false)], 417);
      await t.enterText(find.byKey(const Key('ai-timeout-custom')), '601');
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Phân tích ảnh bằng Vision'),
            )
            .onPressed,
        isNull,
      );
      expect(fake.calls, 0);
      await t.enterText(find.byKey(const Key('ai-timeout-custom')), '417');
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(find.byKey(const Key('ai-url'))).controller!.text,
        'http://localhost:1234/v1',
      );
      await tap(find.text('Phân tích ảnh bằng Vision'));
      expect(fake.calls, 1);
      expect(find.byKey(const Key('ai-retry')), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('ai-retry')));
      await t.tap(find.byKey(const Key('ai-retry')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(fake.calls, 2);
      expect(find.textContaining('417 giây'), findsWidgets);
      await t.ensureVisible(find.byKey(const Key('ai-cancel-request')));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(const Key('ai-cancel-request')));
      await t.pumpAndSettle();
      fake.delayed.complete(AiMapResult.parse(resultJson()));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('accept-0')), findsNothing);
      await tap(find.text('Phân tích ảnh bằng Vision'));
      expect(fake.calls, 3);
      expect(AuthSession.accessToken, 'unit-app-token-kept');
      await t.pumpWidget(page(const ValueKey('reopened')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(find.byKey(const Key('ai-timeout-custom')))
            .controller!
            .text,
        '417',
      );
      expect(t.takeException(), isNull);
    },
  );
  test('Real transport completes before AI timeout; timeout only affects AI, no app JWT sent', () async {
    final image = await cleanupTestImage();
    AuthSession.accessToken = 'unit-app-token';
    final provider = OpenAiMapProvider(
      baseUrl: 'http://localhost:1234/v1',
      timeout: const Duration(seconds: 30),
      client: MockClient((r) async {
        expect(r.headers['Authorization'], isNull);
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
    expect(
      (await provider.analyze(image, 'vision-test-id')).nodes,
      hasLength(1),
    );
    provider.dispose();
    final slow = OpenAiMapProvider(
      baseUrl: 'http://localhost:1234/v1',
      timeout: const Duration(milliseconds: 1),
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      slow.analyze(image, 'vision-test-id'),
      throwsA(
        isA<AiMapException>().having(
          (e) => e.kind,
          'kind',
          AiMapFailure.timeout,
        ),
      ),
    );
    expect(AuthSession.accessToken, 'unit-app-token');
    slow.dispose();
  });
}
