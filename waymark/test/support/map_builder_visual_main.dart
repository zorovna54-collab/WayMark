// Isolated manual visual harness. Not imported by lib/main.dart or any runtime route.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waymark/features/admin/draft_map_editor.dart';
import 'package:waymark/services/auth_session.dart';
import 'package:waymark/services/waymark_api_service.dart';

import '../fixtures/routing_fixture.dart';

void main() {
  AuthSession.accessToken = 'visual-harness-only';
  final client = MockClient((request) async {
    if (request.method != 'GET') {
      throw StateError('Visual harness permits GET only');
    }
    final path = request.url.path;
    final data = path.endsWith('/sites')
        ? [
            {'id': 1, 'name': 'Test site — fixture'},
          ]
        : path.endsWith('/buildings')
        ? [
            {'id': 1, 'siteId': 1, 'name': 'Test building'},
          ]
        : path.endsWith('/floors')
        ? [floorGraphJson(1)['floor'], floorGraphJson(2)['floor']]
        : floorGraphJson(path.endsWith('/2/graph') ? 2 : 1);
    return http.Response(
      jsonEncode(data),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  runApp(
    MaterialApp(
      title: 'WayMark 7B Visual Test',
      builder: (context, child) => Column(
        children: [
          Material(
            color: Colors.amber.shade100,
            child: const SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'VISUAL TEST ONLY — API fixture, no SQL, no publish',
                ),
              ),
            ),
          ),
          Expanded(child: child!),
        ],
      ),
      home: DraftMapEditor(api: WayMarkApiService(client: client)),
    ),
  );
}
