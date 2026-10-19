import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/navigation/manual_navigation.dart';
import 'package:waymark/models/route_models.dart';

import 'fixtures/routing_fixture.dart';

WayMarkRoute singleNodeRoute() {
  final json = routeJson();
  json['destination'] = json['start'];
  json['nodes'] = [(json['nodes'] as List).first];
  json['edges'] = [];
  json['totalDistanceMeters'] = 0;
  return WayMarkRoute.fromJson(json);
}

void main() {
  test(
    'Next and previous follow directed route edges and floor transitions',
    () {
      final state = ManualNavigation(WayMarkRoute.fromJson(routeJson()));
      expect(state.issue, isNull);
      expect(state.nodeIndex, 0);
      expect(state.progress, 0);
      expect(state.previous(), isFalse);
      expect(state.currentEdge!.distanceMeters, 24.75);
      expect(state.followingEdge!.edgeType, 'Elevator');
      expect(state.confirmNext(), isTrue);
      expect(state.nodeIndex, 1);
      expect(state.progress, 0.5);
      expect(state.currentEdge!.distanceMeters, 15.25);
      expect(state.currentNode!.floor.id, 1);
      expect(state.confirmNext(), isTrue);
      expect(state.currentNode!.floor.id, 2);
      expect(state.progress, 1);
      expect(state.completed, isTrue);
      expect(state.currentEdge, isNull);
      expect(state.confirmNext(), isFalse);
      expect(state.previous(), isTrue);
      expect(state.nodeIndex, 1);
      expect(state.currentNode!.floor.id, 1);
      expect(state.completed, isFalse);
    },
  );

  test('Single node requires an explicit completion and supports undo', () {
    final state = ManualNavigation(singleNodeRoute());
    expect(state.completed, isFalse);
    expect(state.progress, 0);
    expect(state.currentEdge, isNull);
    expect(state.confirmNext(), isTrue);
    expect(state.completed, isTrue);
    expect(state.progress, 1);
    expect(state.previous(), isTrue);
    expect(state.completed, isFalse);
  });

  test('Empty or incomplete route cannot progress', () {
    final route = WayMarkRoute.fromJson(routeJson());
    for (final nodes in [<RouteNode>[], route.nodes]) {
      final state = ManualNavigation(
        WayMarkRoute(
          start: route.start,
          destination: route.destination,
          totalDistanceMeters: 0,
          accessibleOnly: false,
          nodes: nodes,
          edges: [],
        ),
      );
      expect(state.issue, isNotNull);
      expect(state.currentNode, isNull);
      expect(state.confirmNext(), isFalse);
      expect(state.previous(), isFalse);
    }
  });

  test('Missing floor/name or non-matching direction is rejected', () {
    for (final field in ['floor', 'name', 'edge']) {
      final json = routeJson();
      if (field == 'floor') (json['nodes'] as List).first['floor']['name'] = '';
      if (field == 'name') (json['nodes'] as List).first['name'] = '';
      if (field == 'edge') {
        (json['edges'] as List).last['movement'] = 'SameFloor';
      }
      expect(ManualNavigation(WayMarkRoute.fromJson(json)).isValid, isFalse);
    }
  });
}
