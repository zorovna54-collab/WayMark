import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/map_draft_api_service.dart';
import 'package:waymark/services/published_map_api_service.dart';

void main() {
  setUp(() => AuthSession.accessToken = 'isolated-creator-test');
  tearDown(AuthSession.clear);

  test(
    'Draft permission failure does not instruct Creator to acquire Admin',
    () async {
      final client = MockClient((request) async {
        expect(
          request.headers['Authorization'],
          'Bearer isolated-creator-test',
        );
        return http.Response('{"code":"draft_scope_denied"}', 403);
      });
      addTearDown(client.close);
      await expectLater(
        MapDraftApiService(client: client).metadata(1),
        throwsA(
          isA<MapDraftApiException>()
              .having((error) => error.status, 'status', 403)
              .having(
                (error) => error.message,
                'permission',
                contains('Site membership'),
              )
              .having(
                (error) => error.message,
                'least privilege',
                isNot(contains('Admin')),
              ),
        ),
      );
      expect(AuthSession.accessToken, 'isolated-creator-test');
    },
  );

  test(
    'Publish denial explains separate Site permission and preserves login',
    () async {
      final client = MockClient(
        (request) async => http.Response('{"code":"site_publish_denied"}', 403),
      );
      addTearDown(client.close);
      await expectLater(
        PublishedMapApiService(client: client)
            .publish('00000000-0000-4000-8000-000000000001', 1),
        throwsA(
          isA<MapDraftApiException>()
              .having((error) => error.status, 'status', 403)
              .having(
                (error) => error.message,
                'publication',
                contains('quyền xuất bản riêng'),
              )
              .having(
                (error) => error.message,
                'least privilege',
                isNot(contains('Admin')),
              ),
        ),
      );
      expect(AuthSession.accessToken, 'isolated-creator-test');
    },
  );
}
