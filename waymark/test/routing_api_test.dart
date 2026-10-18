import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/models/route_models.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/waymark_api_service.dart';

import 'fixtures/routing_fixture.dart';

void main() {
  const request = RouteRequest(
    startWayMarkCode: startCode,
    destinationWayMarkCode: destinationCode,
  );
  tearDown(AuthSession.clear);

  test(
    'Parse real contract, decimal distances and ordered cross-floor edges',
    () {
      final route = WayMarkRoute.fromJson(routeJson());
      expect(route.totalDistanceMeters, 40);
      expect(route.edges.first.distanceMeters, 24.75);
      expect(route.nodes.last.floor.floorCode, 'F2');
      expect(route.edges.last.movement, 'ChangeFloor');
      expect(formatMeters(40), '40 m');
      expect(formatMeters(0), '0 m');
      expect(formatMeters(24.75), '24.75 m');
    },
  );

  test('Start = destination permits one node and no edges', () {
    final json = routeJson();
    json['destination'] = json['start'];
    json['nodes'] = [(json['nodes'] as List).first];
    json['edges'] = [];
    json['totalDistanceMeters'] = 0;
    expect(WayMarkRoute.fromJson(json).edges, isEmpty);
  });

  test('Reject empty or disconnected successful response', () {
    final json = routeJson();
    json['nodes'] = [];
    expect(() => WayMarkRoute.fromJson(json), throwsFormatException);
    final broken = routeJson();
    (broken['edges'] as List).first['toNodeId'] = 999;
    expect(() => WayMarkRoute.fromJson(broken), throwsFormatException);
  });

  test(
    'POST uses shared base URL, AuthSession Bearer, two codes and query filter',
    () async {
      AuthSession.accessToken = 'test-token';
      final client = MockClient((r) async {
        expect(r.method, 'POST');
        expect(
          r.url.toString(),
          '${WayMarkApiService.baseUrl}/routes?accessibleOnly=true',
        );
        expect(r.headers['Authorization'], 'Bearer test-token');
        expect(r.headers['Content-Type'], 'application/json');
        expect(jsonDecode(r.body), {
          'startWayMarkCode': startCode,
          'destinationWayMarkCode': destinationCode,
        });
        return http.Response(jsonEncode(routeJson(accessibleOnly: true)), 200);
      });
      addTearDown(client.close);
      final route = await WayMarkApiService(client: client)
          .findRoute(request, accessibleOnly: true);
      expect(route.accessibleOnly, isTrue);
    },
  );

  test('Map-location uses encoded code and handles nullable node', () async {
    final client = MockClient((r) async {
      expect(r.url.path, '/api/WayMarks/code/$startCode/map-location');
      return http.Response(jsonEncode(mapLocationJson(mapped: false)), 200);
    });
    addTearDown(client.close);
    final location = await WayMarkApiService(client: client)
        .getMapLocation(' $startCode ');
    expect(location.node, isNull);
    expect(location.wayMarkCode, startCode);
  });

  for (final status in [400, 401, 403, 404, 409, 422, 500, 503]) {
    test('HTTP $status is typed and never exposes server body', () async {
      final client = MockClient(
        (r) async => http.Response('private server details', status),
      );
      addTearDown(client.close);
      await expectLater(
        WayMarkApiService(client: client).findRoute(request),
        throwsA(
          isA<WayMarkApiException>()
              .having((e) => e.statusCode, 'status', status)
              .having(
                (e) => e.message.contains('private'),
                'no server detail',
                false,
              ),
        ),
      );
    });
  }

  test('Connection failure is understandable', () async {
    final client = MockClient(
      (r) async => throw http.ClientException('network'),
    );
    addTearDown(client.close);
    await expectLater(
      WayMarkApiService(client: client).findRoute(request),
      throwsA(
        isA<WayMarkApiException>().having(
          (e) => e.message,
          'message',
          contains('Không thể kết nối'),
        ),
      ),
    );
  });

  test('Timeout completes with an actionable message', () async {
    final pending = Completer<http.Response>();
    final client = MockClient((r) => pending.future);
    addTearDown(client.close);
    await expectLater(
      WayMarkApiService(
        client: client,
        requestTimeout: const Duration(milliseconds: 5),
      ).findRoute(request),
      throwsA(
        isA<WayMarkApiException>().having(
          (e) => e.message,
          'message',
          contains('quá lâu'),
        ),
      ),
    );
    pending.complete(http.Response('{}', 200));
  });

  for (final body in ['not json', '[]', '{}']) {
    test('Malformed 200 response is not displayed as route: $body', () async {
      final client = MockClient((r) async => http.Response(body, 200));
      addTearDown(client.close);
      await expectLater(
        WayMarkApiService(client: client).findRoute(request),
        throwsA(isA<WayMarkApiException>()),
      );
    });
  }

  test('Invalid code is rejected before HTTP', () async {
    final client = MockClient((r) async => fail('HTTP must not be called'));
    addTearDown(client.close);
    await expectLater(
      WayMarkApiService(client: client).findRoute(
        const RouteRequest(
          startWayMarkCode: ' ',
          destinationWayMarkCode: destinationCode,
        ),
      ),
      throwsA(isA<WayMarkApiException>()),
    );
  });
}
