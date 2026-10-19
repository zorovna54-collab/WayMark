import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<({Uint8List bytes, String name, String mime})?> pickDraftFile(
  String accept,
  int maxBytes,
) {
  final done = Completer<({Uint8List bytes, String name, String mime})?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = accept;
  input.style.display = 'none';
  web.document.body!.append(input);
  input.addEventListener(
    'cancel',
    ((web.Event event) {
      if (!done.isCompleted) done.complete(null);
      input.remove();
    }).toJS,
  );
  input.addEventListener(
    'change',
    ((web.Event event) {
      () async {
        try {
          final file = input.files?.item(0);
          if (file == null) {
            if (!done.isCompleted) done.complete(null);
            return;
          }
          if (file.size > maxBytes) {
            throw const FormatException('File vượt giới hạn dung lượng.');
          }
          final buffer = await file.arrayBuffer().toDart;
          if (!done.isCompleted) {
            done.complete((
              bytes: buffer.toDart.asUint8List(),
              name: file.name,
              mime: file.type,
            ));
          }
        } catch (error, stack) {
          if (!done.isCompleted) done.completeError(error, stack);
        } finally {
          input.remove();
        }
      }();
    }).toJS,
  );
  try {
    input.click();
  } catch (error, stack) {
    input.remove();
    if (!done.isCompleted) done.completeError(error, stack);
  }
  return done.future;
}

void downloadDraftFile(Uint8List bytes, String name, String mime) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  try {
    web.document.body!.append(anchor);
    anchor.click();
  } finally {
    anchor.remove();
    // Keep the URL alive while the browser starts the asynchronous download.
    Timer(const Duration(seconds: 2), () => web.URL.revokeObjectURL(url));
  }
}
