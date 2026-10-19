
import 'package:flutter/foundation.dart';

import 'draft_files.dart' as platform;

typedef DraftFile = ({Uint8List bytes, String name, String mime});

/// An injectable file boundary; draft files never go to the API.
abstract class DraftFileGateway {
  bool get supported;
  Future<DraftFile?> pick(String accept, int maxBytes);
  Future<void> save(Uint8List bytes, String name, String mime);
}

class PlatformDraftFiles implements DraftFileGateway {
  const PlatformDraftFiles();
  @override
  bool get supported => kIsWeb;
  @override
  Future<DraftFile?> pick(String accept, int maxBytes) =>
      platform.pickDraftFile(accept, maxBytes);
  @override
  Future<void> save(Uint8List bytes, String name, String mime) async =>
      platform.downloadDraftFile(bytes, name, mime);
}
