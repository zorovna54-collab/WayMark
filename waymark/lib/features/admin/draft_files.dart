export 'draft_files_stub.dart'
    if (dart.library.io) 'draft_files_native.dart'
    if (dart.library.js_interop) 'draft_files_web.dart';
