import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/navigation/manual_navigation.dart';
import 'package:waymark/models/route_models.dart';

import 'fixtures/qr_navigation_fixture.dart';
import 'fixtures/routing_fixture.dart';
import 'manual_navigation_test.dart' show singleNodeRoute;

void main() {
  late ManualNavigation state;
  setUp(() => state = ManualNavigation(WayMarkRoute.fromJson(routeJson())));

  test('Next node matches ID plus floor despite different WayMarkCode and NodeCode', () {
    final location = qrLocation(12, 1);
    expect(location.wayMarkCode, isNot(location.node!.nodeCode));
    final match = state.inspectQr(location);
    expect(match.kind, QrRouteMatchKind.next);
    expect(state.nodeIndex, 0);
    expect(state.acceptQr(match), isTrue);
    expect(state.nodeIndex, 1);
    expect(state.currentConfirmation, NavigationConfirmation.qr);
    expect(state.skippedUnconfirmedSteps, 0);
    state.confirmNext();
    expect(state.currentConfirmation, NavigationConfirmation.manual);
    expect(state.currentQr, isNull);
  });

  test('Current node verifies QR without changing progress/completion', () {
    final match = state.inspectQr(qrLocation(11, 1));
    expect(match.kind, QrRouteMatchKind.current);
    expect(state.acceptQr(match), isTrue);
    expect(state.nodeIndex, 0);
    expect(state.progress, 0);
    expect(state.completed, isFalse);
    expect(state.currentQr!.node!.id, 11);
  });

  test(
    'Later node requires confirmation and records gaps, not traveled edges',
    () {
      final match = state.inspectQr(qrLocation(13, 2));
      expect(match.kind, QrRouteMatchKind.later);
      expect(state.acceptQr(match), isFalse);
      expect(state.nodeIndex, 0);
      expect(state.acceptQr(match, confirmedSelection: true), isTrue);
      expect(state.nodeIndex, 2);
      expect(state.currentNode!.floor.id, 2);
      expect(state.completed, isTrue);
      expect(state.skippedUnconfirmedSteps, 1);
    },
  );

  test('Wrong node or same ID on wrong floor never advances', () {
    for (final qr in [qrLocation(999, 1), qrLocation(12, 2)]) {
      final match = state.inspectQr(qr);
      expect(match.kind, QrRouteMatchKind.offRoute);
      expect(state.acceptQr(match, confirmedSelection: true), isFalse);
      expect(state.nodeIndex, 0);
      expect(state.currentConfirmation, isNull);
    }
  });

  test('Unmapped QR or invalid IDs are rejected', () {
    final json = navigationQrJson(11, 1)..['node'] = null;
    for (final qr in [
      WayMarkMapLocation.fromJson(json),
      qrLocation(0, 1),
      qrLocation(11, 0),
    ]) {
      expect(state.inspectQr(qr).kind, QrRouteMatchKind.unmapped);
      expect(state.acceptQr(state.inspectQr(qr)), isFalse);
      expect(state.nodeIndex, 0);
    }
  });

  test(
    'Passed node does not move backwards; stale result cannot be applied',
    () {
      final stale = state.inspectQr(qrLocation(13, 2));
      state.confirmNext();
      expect(state.acceptQr(stale, confirmedSelection: true), isFalse);
      expect(state.inspectQr(qrLocation(11, 1)).kind, QrRouteMatchKind.past);
      expect(
        state.acceptQr(
          state.inspectQr(qrLocation(11, 1)),
          confirmedSelection: true,
        ),
        isFalse,
      );
      expect(state.nodeIndex, 1);
      expect(state.currentConfirmation, NavigationConfirmation.manual);
    },
  );

  test(
    'Repeated node requires an explicit occurrence, including current vs later',
    () {
      state = ManualNavigation(repeatingNodeRoute());
      final match = state.inspectQr(qrLocation(11, 1));
      expect(match.kind, QrRouteMatchKind.ambiguous);
      expect(match.indices, [0, 2]);
      expect(state.acceptQr(match), isFalse);
      expect(state.acceptQr(match, confirmedSelection: true), isFalse);
      expect(
        state.acceptQr(match, selectedIndex: 1, confirmedSelection: true),
        isFalse,
      );
      expect(state.nodeIndex, 0);
      expect(
        state.acceptQr(match, selectedIndex: 0, confirmedSelection: true),
        isTrue,
      );
      expect(state.nodeIndex, 0);
      final nextMatch = state.inspectQr(qrLocation(11, 1));
      expect(
        state.acceptQr(nextMatch, selectedIndex: 2, confirmedSelection: true),
        isTrue,
      );
      expect(state.nodeIndex, 2);
    },
  );

  test(
    'Repeated node next occurrence is not inferred from a past occurrence',
    () {
      state = ManualNavigation(repeatingNodeRoute());
      state.confirmNext();
      final match = state.inspectQr(qrLocation(11, 1));
      expect(match.kind, QrRouteMatchKind.ambiguous);
      expect(
        state.acceptQr(match, selectedIndex: 0, confirmedSelection: true),
        isFalse,
      );
      expect(state.acceptQr(match, selectedIndex: 2), isFalse);
      expect(state.nodeIndex, 1);
      expect(
        state.acceptQr(match, selectedIndex: 2, confirmedSelection: true),
        isTrue,
      );
      expect(state.currentNode!.floor.id, 1);
    },
  );

  test('Single node QR keeps progress unchanged until explicit finish', () {
    state = ManualNavigation(singleNodeRoute());
    expect(state.acceptQr(state.inspectQr(qrLocation(11, 1))), isTrue);
    expect(state.progress, 0);
    expect(state.completed, isFalse);
    state.confirmNext();
    expect(state.completed, isTrue);
  });

  test('A result from another navigation session is never reused', () {
    final other = ManualNavigation(state.route);
    expect(other.acceptQr(state.inspectQr(qrLocation(12, 1))), isFalse);
    expect(other.progress, 0);
  });
}
