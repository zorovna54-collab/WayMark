import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/admin/draft_map.dart';
import 'package:waymark/features/admin/draft_map_editor.dart';
import 'package:waymark/features/admin/local_map_project.dart';
import 'package:waymark/services/auth_api_service.dart';
import 'package:waymark/services/auth_session.dart';

import 'draft_floor_workflow_test.dart' show MemoryDraftFiles;

DraftMap blankGraph() => DraftMap.local('Clinic', 'Building', 'Ground', 'G')
  ..putNode(
    const DraftNode(
      'A',
      'Reception desk with a long destination name',
      .2,
      .5,
      'Entrance',
    ),
  )
  ..putNode(
    const DraftNode(
      'B',
      'Destination B',
      .8,
      .5,
      'Destination',
      searchableAsDestination: true,
    ),
  );

void main() {
  tearDown(AuthSession.clear);
  test('Edge form preflight is read-only and shares graph constraints, preserves stable IDs', () {
    final d = blankGraph();
    final before = jsonEncode(d.toJson());
    d.checkEdge(const DraftEdge('A', 'B', 2.5, 'Corridor'));
    expect(jsonEncode(d.toJson()), before);
    for (final e in [
      const DraftEdge('A', 'A', 3, 'Corridor'),
      const DraftEdge('A', 'missing', 3, 'Corridor'),
      const DraftEdge('A', 'B', 0, 'Corridor'),
    ]) {
      expect(() => d.checkEdge(e), throwsFormatException);
    }
    expect(jsonEncode(d.toJson()), before);
  });
  for (final width in [320.0, 360.0, 393.0, 430.0]) {
    testWidgets(
      'Phone $width: invalid edge retains form; explicit two-way creates two measured edges',
      (t) async {
        t.view.physicalSize = Size(width, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final d = blankGraph(), files = MemoryDraftFiles();
        final ids = Map.of(d.nodeIds);
        final project = LocalMapProject(d)
          ..floors.add(DraftMap.local('Clinic', 'Building', 'First', 'L1'));
        await t.pumpWidget(
          MaterialApp(
            home: DraftMapEditor(initialProject: project, files: files),
          ),
        );
        await t.pumpAndSettle();
        Future<void> tap(Finder f) async {
          await t.ensureVisible(f);
          await t.pumpAndSettle();
          await t.tap(f);
          await t.pumpAndSettle();
        }

        await tap(find.text('Thêm cạnh có hướng'));
        await tap(find.byKey(const Key('draft-edge-save')));
        expect(find.byKey(const Key('draft-edge-error')), findsOneWidget);
        expect(find.byType(AlertDialog), findsOneWidget);
        for (final (key, label) in [
          (
            'draft-edge-from',
            'N01 · Reception desk with a long destination name',
          ),
          ('draft-edge-to', 'N02 · Destination B'),
        ]) {
          await tap(find.byKey(Key(key)));
          await tap(find.text(label).last);
        }
        await t.enterText(find.byKey(const Key('draft-edge-meters')), '0');
        await tap(find.byKey(const Key('draft-edge-save')));
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(d.edges, isEmpty);
        expect(
          t
              .widget<TextField>(find.byKey(const Key('draft-edge-meters')))
              .controller!
              .text,
          '0',
        );
        await t.enterText(find.byKey(const Key('draft-edge-meters')), '2,5');
        await tap(find.byKey(const Key('draft-edge-bidirectional')));
        await tap(find.byKey(const Key('draft-edge-save')));
        expect(d.edges.map((e) => '${e.from}->${e.to}'), ['A->B', 'B->A']);
        expect(d.edges.every((e) => e.isMeasured && e.meters == 2.5), isTrue);
        expect(d.nodeIds, ids);
        final edgeIds = Map.of(d.edgeIds);
        await tap(find.byKey(const Key('export-draft')));
        final loaded = (await t.runAsync(
          () => LocalMapProject.decode(files.saved!),
        ))!;
        expect(loaded.id, project.id);
        expect(loaded.floors.first.edgeIds, edgeIds);
        expect(loaded.floors.last.nodes, isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Existing reverse edge prevents partial two-way insert; cancelling preserves graph',
    (t) async {
      t.view.physicalSize = const Size(393, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final d = blankGraph()..addEdge(const DraftEdge('B', 'A', 4, 'Corridor'));
      final before = jsonEncode(d.toJson());
      await t.pumpWidget(
        MaterialApp(
          home: DraftMapEditor(
            initialProject: LocalMapProject(d),
            files: MemoryDraftFiles(),
          ),
        ),
      );
      await t.pumpAndSettle();
      Future<void> tap(Finder f) async {
        await t.ensureVisible(f);
        await t.pumpAndSettle();
        await t.tap(f);
        await t.pumpAndSettle();
      }

      await tap(find.text('Thêm cạnh có hướng'));
      for (final (key, label) in [
        (
          'draft-edge-from',
          'N01 · Reception desk with a long destination name',
        ),
        ('draft-edge-to', 'N02 · Destination B'),
      ]) {
        await tap(find.byKey(Key(key)));
        await tap(find.text(label).last);
      }
      await t.enterText(find.byKey(const Key('draft-edge-meters')), '5');
      await tap(find.byKey(const Key('draft-edge-bidirectional')));
      await tap(find.byKey(const Key('draft-edge-save')));
      expect(find.byKey(const Key('draft-edge-error')), findsOneWidget);
      expect(jsonEncode(d.toJson()), before);
      await tap(find.text('Hủy'));
      expect(jsonEncode(d.toJson()), before);
    },
  );
  for (final status in [200, 401, 500]) {
    test(
      'Settings API probe distinguishes HTTP $status from network failure, retains AuthSession',
      () async {
        AuthSession.accessToken = 'unit-only-token';
        final api = AuthApiService(
          client: MockClient((r) async {
            expect(r.method, 'GET');
            expect(r.headers['Authorization'], isNull);
            return http.Response('{}', status);
          }),
        );
        if (status == 500) {
          await expectLater(
            api.checkConnection(),
            throwsA(isA<AuthApiException>()),
          );
        } else {
          final text = await api.checkConnection();
          expect(text, contains('Đã kết nối API'));
          expect(text, contains('$status'));
          if (status == 401) expect(text, contains('cần đăng nhập'));
        }
        expect(AuthSession.accessToken, 'unit-only-token');
      },
    );
  }
}
