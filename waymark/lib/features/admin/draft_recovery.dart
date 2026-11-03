import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dart:convert';

import '../../services/auth_session.dart';

/// App-private recovery only; never a server save or permission grant.
class DraftRecovery {
  const DraftRecovery();
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static const _channel = MethodChannel('waymark/draft_files');
  static String? ownerScope(String api) {
    final token = AuthSession.accessToken;
    if (token == null) return '$api|local';
    // This only partitions local files, never grants authorization. No JWT is
    // persisted. Server still verifies signature/ownership on every API call.
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
      ) as Map;
      final subject =
          payload['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'] ??
          payload['sub'];
      if (subject is String && subject.isNotEmpty) return '$api|$subject';
    } catch (_) {
      /* Never fall back to a shared scope for unknown signed-in users. */
    }
    final name = AuthSession.username ?? AuthSession.profile?.userName;
    return name == null ? null : '$api|user:$name';
  }

  Future<Uint8List?> read(String owner, String project) =>
      _channel.invokeMethod<Uint8List>('recoveryRead', {
        'owner': owner,
        'project': project,
      });
  Future<void> write(String owner, String project, Uint8List bytes) =>
      _channel.invokeMethod<void>('recoveryWrite', {
        'owner': owner,
        'project': project,
        'bytes': bytes,
      });
}
