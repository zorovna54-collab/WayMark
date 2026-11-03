import 'package:flutter/services.dart';

const _channel = MethodChannel('waymark/ai_preferences');
Future<int?> readTimeout(String scope) async {
  try {
    return await _channel.invokeMethod<int>('readTimeout', {'scope': scope});
  } on MissingPluginException {
    return null;
  }
}

Future<bool> writeTimeout(String scope, int seconds) async {
  try {
    return await _channel.invokeMethod<bool>('writeTimeout', {
          'scope': scope,
          'seconds': seconds,
        }) ??
        false;
  } on MissingPluginException {
    return false; // Unsupported platforms retain a session-only choice, visibly.
  }
}
