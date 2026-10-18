import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/services/lm_studio_service.dart';

void main() {
  group('LmStudioService', () {
    test('reads model IDs from the models response', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/models');
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'local-model-a'},
              {'id': 'local-model-b'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = LmStudioService(
        client: client,
        baseUrl: 'http://127.0.0.1:1234/v1/',
      );

      expect(await service.getModels(), ['local-model-a', 'local-model-b']);
      client.close();
      service.dispose();
    });

    test('sends a non-streaming chat request and reads its answer', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/chat/completions');
        expect(
          request.headers.entries.any(
            (entry) =>
                entry.key.toLowerCase() == 'content-type' &&
                entry.value == 'application/json',
          ),
          isTrue,
        );
        expect(
          request.headers.entries.any(
            (entry) =>
                entry.key.toLowerCase() == 'authorization' &&
                entry.value == 'Bearer test-token',
          ),
          isTrue,
        );
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], 'local-model');
        expect(body['temperature'], 0.7);
        expect(body['max_tokens'], 512);
        expect(body['stream'], isFalse);
        expect(body['messages'], [
          {'role': 'user', 'content': 'Xin chào'},
        ]);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'Xin chào bạn!'},
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = LmStudioService(client: client, apiToken: 'test-token');

      expect(
        await service.ask(model: 'local-model', question: 'Xin chào'),
        'Xin chào bạn!',
      );
      client.close();
      service.dispose();
    });

    test('returns an empty list when no models are loaded', () async {
      final client = MockClient((_) async => http.Response('{"data":[]}', 200));
      final service = LmStudioService(client: client);

      expect(await service.getModels(), isEmpty);
      client.close();
      service.dispose();
    });

    test('reports malformed JSON from the models endpoint', () async {
      final client = MockClient((_) async => http.Response('not json', 200));
      final service = LmStudioService(client: client);

      await expectLater(
        service.getModels(),
        throwsA(
          isA<LmStudioException>().having(
            (error) => error.message,
            'message',
            contains('JSON không hợp lệ'),
          ),
        ),
      );
      client.close();
      service.dispose();
    });

    test('reports when the request times out', () async {
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return http.Response('{"data":[]}', 200);
      });
      final service = LmStudioService(
        client: client,
        timeout: const Duration(milliseconds: 1),
      );

      await expectLater(
        service.getModels(),
        throwsA(
          isA<LmStudioException>().having(
            (error) => error.message,
            'message',
            contains('quá thời gian chờ'),
          ),
        ),
      );
      client.close();
      service.dispose();
    });

    test(
      'reports an HTTP error without exposing raw response content',
      () async {
        final client = MockClient(
          (_) async => http.Response('private server detail', 500),
        );
        final service = LmStudioService(client: client);

        await expectLater(
          service.getModels(),
          throwsA(
            isA<LmStudioException>().having(
              (error) => error.message,
              'message',
              contains('HTTP 500'),
            ),
          ),
        );
        client.close();
        service.dispose();
      },
    );
  });
}
