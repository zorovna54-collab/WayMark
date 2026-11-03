import 'package:flutter/material.dart';
import 'package:waymark/features/scanner/public_map_entry_page.dart';

// Uses the real configured HTTP API. No graph or image is embedded in this entrypoint.
void main() => runApp(
  const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: PublicMapEntryPage(
      initialPayload: String.fromEnvironment('WAYMARK_DEMO_PUBLIC_QR'),
    ),
  ),
);
