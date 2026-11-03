import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/auth_api_service.dart';
import 'package:waymark/services/map_draft_api_service.dart';
import 'package:waymark/services/published_map_api_service.dart';
import 'package:waymark/services/waymark_api_service.dart';
import 'package:waymark/features/auth/workflow_recovery.dart';
import 'package:waymark/features/auth/account_security_page.dart';
import 'package:waymark/features/admin/draft_map_editor.dart';
import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/route/floor_plan_canvas.dart';

import 'fixtures/published_map_fixture.dart';
import 'floor_image_cleanup_test.dart' show cleanupTestImage;

http.Response profileResponse() => http.Response(
  jsonEncode({
    'userName': 'owner-A',
    'displayName': 'A',
    'email': null,
    'emailVerified': false,
    'roles': [],
  }),
  200,
  headers: {'content-type': 'application/json'},
);
void main() {
  setUp(() => AuthSession.establish('token-A', 'owner-A'));
  tearDown(AuthSession.clear);
  testWidgets('completed account dialog cannot log out a replacement session', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(home: AccountSecurityPage(api: _SuccessfulAccountAction())),
    );
    await t.enterText(
      find.byKey(const Key('current-password')),
      'old-fixture-password',
    );
    await t.enterText(
      find.byKey(const Key('new-password')),
      'new-fixture-password',
    );
    await t.enterText(
      find.byKey(const Key('confirm-password')),
      'new-fixture-password',
    );
    await t.ensureVisible(find.text('Đổi mật khẩu cho tài khoản này'));
    await t.tap(find.text('Đổi mật khẩu cho tài khoản này'));
    await t.pumpAndSettle();
    expect(find.text('Đăng nhập lại'), findsOneWidget);
    AuthSession.establish('token-B', 'owner-B');
    await t.pumpAndSettle();
    expect(find.text('Đăng nhập lại'), findsNothing);
    expect(find.byType(WorkflowRecovery), findsOneWidget);
    expect(AuthSession.accessToken, 'token-B');
  });
  test('owner rebind cannot revive an earlier continuation', () async {
    final scope = OwnerWorkflow();
    addTearDown(scope.dispose);
    final pending = Completer<int>();
    final result = scope.wait(pending.future);
    AuthSession.rejectUnauthorized(
      AuthSession.accessToken,
      AuthSession.revision,
    );
    expect(scope.current, false);
    AuthSession.establish('token-A2', 'owner-A');
    expect(scope.rebind(), true);
    pending.complete(1);
    await expectLater(result, throwsA(isA<AuthWorkflowException>()));
    AuthSession.establish('token-B', 'owner-B');
    expect(scope.rebind(), false);
  });
  test('disposed owner blocks deferred request before send', () async {
    final scope = OwnerWorkflow();
    final signal = Completer<void>();
    var requests = 0;
    final api = PublishedMapApiService(
      client: MockClient((_) async {
        requests++;
        return http.Response('[]', 200);
      }),
    );
    final result = scope.run(() async {
      await signal.future;
      await api.list();
    });
    scope.dispose();
    signal.complete();
    await expectLater(result, throwsA(isA<AuthWorkflowException>()));
    expect(requests, 0);
  });
  test(
    'save response lost is uncertain; late A response never applied to B',
    () async {
      var writes = 0;
      final api = PublishedMapApiService(
        client: MockClient((_) async {
          writes++;
          throw TimeoutException('committed fixture');
        }),
      );
      await expectLater(
        api.save('A', {}),
        throwsA(
          isA<MapDraftApiException>().having(
            (e) => e.uncertain,
            'uncertain',
            true,
          ),
        ),
      );
      expect(writes, 1);
      final pending = Completer<http.Response>();
      final delayed = PublishedMapApiService(
        client: MockClient((_) => pending.future),
      );
      final result = delayed.save('A', {});
      AuthSession.establish('token-B', 'owner-B');
      pending.complete(http.Response('{}', 200));
      await expectLater(
        result,
        throwsA(
          isA<MapDraftApiException>().having(
            (e) => e.code,
            'code',
            'auth_session_changed',
          ),
        ),
      );
    },
  );
  testWidgets(
    'Save confirmation drafted by A disabled after switch; no mutation',
    (t) async {
      final scope = OwnerWorkflow();
      addTearDown(scope.dispose);
      var writes = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Save A'),
                onPressed: () async {
                  final yes = await showWorkflowDialog<bool>(
                    context: context,
                    workflow: scope,
                    builder: (c) => AlertDialog(
                      content: const Text('Private draft A'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Confirm save'),
                        ),
                      ],
                    ),
                  );
                  if (yes == true && scope.current) writes++;
                },
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Save A'));
      await t.pumpAndSettle();
      AuthSession.establish('token-B', 'owner-B');
      await t.pumpAndSettle();
      expect(find.text('Private draft A'), findsNothing);
      expect(find.text('Confirm save'), findsNothing);
      await t.tap(find.text('Đóng'));
      await t.pumpAndSettle();
      expect(writes, 0);
    },
  );
  testWidgets(
    'Builder dirty RAM graph retained across expiry and verified same-owner recovery',
    (t) async {
      t.view.physicalSize = const Size(1024, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final fixture = PublishedMapFixture(
        (await t.runAsync(cleanupTestImage))!,
      );
      final requests = <String>[];
      final api = WayMarkApiService(
        client: MockClient((r) async {
          requests.add(r.method);
          return profileResponse();
        }),
      );
      await t.pumpWidget(
        MaterialApp(
          home: DraftMapEditor(initialProject: fixture.project, api: api),
        ),
      );
      final image = t
          .widget<FloorPlanCanvas>(find.byType(FloorPlanCanvas))
          .image;
      if (image != null) {
        await t.runAsync(
          () => precacheImage(image, t.element(find.byType(DraftMapEditor))),
        );
      }
      await t.pumpAndSettle();
      // Mutate through the same editor-owned project and retain its stable identity.
      fixture.project.floors.first.putNode(
        const DraftNode('UNSAVED-A', 'Private unsaved A', .35, .4, 'Junction'),
      );
      final before = fixture.project.encode();
      AuthSession.rejectUnauthorized(
        AuthSession.accessToken,
        AuthSession.revision,
      );
      await t.pumpAndSettle();
      expect(find.byType(WorkflowRecovery), findsOneWidget);
      expect(fixture.project.encode(), before);
      AuthSession.establish('token-B', 'owner-B');
      await t.pumpAndSettle();
      expect(find.byType(WorkflowRecovery), findsOneWidget);
      expect(find.textContaining('Private unsaved A'), findsNothing);
      AuthSession.establish('token-A2', 'owner-A');
      await t.pumpAndSettle();
      await t.tap(find.text('Đăng nhập lại / xác minh chủ phiên'));
      await t.pumpAndSettle();
      expect(find.byType(WorkflowRecovery), findsNothing);
      expect(fixture.project.encode(), before);
      expect(requests, [
        'GET',
      ]); // profile verification only; no automatic Save/Publish.
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('recovery verifies owner and never reveals A to B', (t) async {
    final scope = OwnerWorkflow();
    addTearDown(scope.dispose);
    AuthSession.establish('token-B', 'owner-B');
    final api = AuthApiService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'userName': 'owner-B',
            'displayName': 'B',
            'email': null,
            'emailVerified': false,
            'roles': [],
          }),
          200,
        ),
      ),
    );
    // Same session as B avoids login; the original A workflow still rejects rebind.
    final b = OwnerWorkflow();
    addTearDown(b.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: WorkflowRecovery(workflow: scope, api: api),
      ),
    );
    expect(scope.rebind(), false);
    expect(b.current, true);
    await t.pumpWidget(const SizedBox());
  });
}

class _SuccessfulAccountAction extends AuthApiService {
  @override
  Future<void> accountAction(String action, Map<String, String> body) async {}
}
