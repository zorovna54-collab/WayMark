import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/navigation/manual_navigation.dart';
import 'package:waymark/features/navigation/reroute_navigation.dart';
import 'package:waymark/models/route_models.dart';
import 'package:waymark/services/waymark_api_service.dart';

import 'fixtures/qr_navigation_fixture.dart';
import 'fixtures/routing_fixture.dart';

void main() {
  for (final preference in [
    'ShortestDistance',
    'PreferElevators',
    'LessWalking',
  ]) {
    test(
      'Reroute retains restrictions and $preference, validates new node and destination',
      () async {
        final json = routeJson(accessibleOnly: true);
        json['options'] = RoutingOptions(
          avoidStairs: true,
          preference: preference,
        ).toJson();
        final state = ManualNavigation(WayMarkRoute.fromJson(json));
        state.confirmNext();
        final replacement = routeJson(accessibleOnly: true);
        replacement['options'] = json['options'];
        replacement['start'] = navigationQrJson(999, 1);
        (replacement['nodes'] as List).first['id'] = 999;
        (replacement['edges'] as List).first['fromNodeId'] = 999;
        final client = MockClient((request) async {
          expect(request.url.queryParameters['accessibleOnly'], 'true');
          expect(jsonDecode(request.body)['options'], json['options']);
          return http.Response(jsonEncode(replacement), 200);
        });
        addTearDown(client.close);
        final next = await rerouteNavigation(
          state,
          qrLocation(999, 1),
          WayMarkApiService(client: client),
        );
        expect(state.nodeIndex, 1); // old object never mutates
        expect(next.nodeIndex, 0);
        expect(next.currentConfirmation, NavigationConfirmation.qr);
        expect(next.route.destination.wayMarkCode, destinationCode);
        expect(next.route.options.preference, preference);
      },
    );
  }

  test(
    'Network failure leaves original route and manual evidence intact',
    () async {
      final state = ManualNavigation(WayMarkRoute.fromJson(routeJson()));
      state.confirmNext();
      final client = MockClient(
        (request) async => throw http.ClientException('offline'),
      );
      addTearDown(client.close);
      await expectLater(
        rerouteNavigation(
          state,
          qrLocation(999, 1),
          WayMarkApiService(client: client),
        ),
        throwsA(isA<WayMarkApiException>()),
      );
      expect(state.nodeIndex, 1);
      expect(state.currentConfirmation, NavigationConfirmation.manual);
    },
  );

  for (final bad in ['missingOptions', 'stairs', 'wheelchair']) {
    test('Client rejects unsafe or unacknowledged options: $bad', () async {
      final options = RoutingOptions(
        avoidStairs: true,
        wheelchair: bad == 'wheelchair',
      );
      final json = routeJson();
      if (bad != 'missingOptions') json['options'] = options.toJson();
      if (bad == 'stairs') (json['edges'] as List).first['edgeType'] = 'Stairs';
      final client = MockClient(
        (request) async => http.Response(jsonEncode(json), 200),
      );
      addTearDown(client.close);
      await expectLater(
        WayMarkApiService(client: client).findRoute(
          RouteRequest(
            startWayMarkCode: startCode,
            destinationWayMarkCode: destinationCode,
            options: options,
          ),
        ),
        throwsA(isA<WayMarkApiException>()),
      );
    });
  }

  test(
    'QR evidence marker remains separate from subsequent manual progress',
    () {
      final state = ManualNavigation(WayMarkRoute.fromJson(routeJson()));
      state.acceptQr(state.inspectQr(qrLocation(11, 1)));
      state.confirmNext();
      expect(state.lastVerifiedNodeIndex, 0);
      expect(state.nodeIndex, 1);
      expect(state.currentConfirmation, NavigationConfirmation.manual);
    },
  );
}
