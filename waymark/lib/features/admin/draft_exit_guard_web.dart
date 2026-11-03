import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Best-effort browser close/reload warning. Browsers control whether a prompt
/// is shown and its wording; this never silently saves or publishes a draft.
class DraftExitGuard {
  bool _dirty = false;
  late final JSFunction _listener = ((web.Event event) {
    if (!_dirty) return;
    event.preventDefault();
    (event as web.BeforeUnloadEvent).returnValue = '';
  }).toJS;
  DraftExitGuard() {
    web.window.addEventListener('beforeunload', _listener);
  }
  void setDirty(bool value) {
    _dirty = value;
  }

  void dispose() {
    web.window.removeEventListener('beforeunload', _listener);
  }
}
