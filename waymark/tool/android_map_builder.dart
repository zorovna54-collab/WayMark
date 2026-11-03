// Explicit local editor rehearsal. Real Android picker; no fake file service,
// seed, login, server save or production navigation data.
import 'package:flutter/material.dart';
import 'package:waymark/features/admin/draft_map_editor.dart';

void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      fontFamily: 'Inter',
      colorSchemeSeed: const Color(0xff0f172a),
    ),
    home: const DraftMapEditor(),
  ),
);
