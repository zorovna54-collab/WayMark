import 'package:flutter/material.dart';

import '../../services/waymark_api_service.dart';
import 'draft_map_editor.dart';

class AdminMapBuilderPage extends StatelessWidget {
  const AdminMapBuilderPage({super.key, this.api});
  final WayMarkApiService? api;
  @override
  Widget build(BuildContext context) => DraftMapEditor(api: api);
}
