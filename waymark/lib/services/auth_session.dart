import '../models/account_profile.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

class AuthSession {
  static final _workflowKey = Object();
  static void checkWorkflow() =>
      (Zone.current[_workflowKey] as void Function()?)?.call();
  static bool expired = false;
  static void rejectUnauthorized(String? token, int revision) {
    if (token == null || expired || !isCurrent(token, revision)) return;
    expired = true;
    profile = null;
    changes.value++;
  }

  // Only an equality key for local recovery, never an authorization decision.
  static String? get ownerKey {
    try {
      final parts = _accessToken!.split('.');
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map;
      final sub =
          claims['sub'] ??
          claims['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'];
      if (sub is String && sub.isNotEmpty) {
        return jsonEncode([claims['iss'], sub]);
      }
    } catch (_) {
      /* Opaque test/session tokens can use server username. */
    }
    final name = username;
    return name == null || name.isEmpty
        ? null
        : 'username:${name.toLowerCase()}';
  }

  static final changes = ValueNotifier<int>(0);
  static String? _accessToken;
  static String? get accessToken => _accessToken;
  static int get revision => changes.value;
  static bool isCurrent(String? token, int revision) =>
      token == _accessToken && revision == AuthSession.revision;
  static set accessToken(String? value) {
    if (value == _accessToken) return;
    _accessToken = value;
    expired = false;
    username = null;
    profile = null;
    changes.value++;
  }

  static String? username;
  static AccountProfile? profile;

  static void clear() {
    _accessToken = null;
    expired = false;
    username = null;
    profile = null;
    // Explicit logout also invalidates pending anonymous sign-in attempts.
    changes.value++;
  }

  static void establish(String token, String name) {
    _accessToken = token;
    expired = false;
    username = name;
    profile = null;
    changes.value++;
  }
}

class AuthWorkflowException implements Exception {
  const AuthWorkflowException();
  @override
  String toString() =>
      'Phiên làm việc đã thay đổi. Bản nháp được giữ; đăng nhập đúng tài khoản rồi đối chiếu server. Không tự gửi lại thao tác.';
}

/// Pins a retained workflow, including every continuation, to one session.
/// Rebinding requires explicit recovery; it never retries a mutation.
class OwnerWorkflow extends ChangeNotifier {
  OwnerWorkflow()
    : _token = AuthSession.accessToken,
      _revision = AuthSession.revision,
      ownerKey = AuthSession.ownerKey {
    AuthSession.changes.addListener(_changed);
  }
  final String? ownerKey;
  String? _token;
  int _revision;
  bool _closed = false;
  bool get current =>
      !_closed &&
      !AuthSession.expired &&
      AuthSession.isCurrent(_token, _revision);
  void _changed() => notifyListeners();
  void check() {
    if (!current) throw const AuthWorkflowException();
  }

  Future<T> wait<T>(Future<T> future) async {
    final revision = _revision;
    final result = await future;
    check();
    if (revision != _revision) throw const AuthWorkflowException();
    return result;
  }

  T run<T>(T Function() action) {
    check();
    final revision = _revision;
    return runZoned(
      action,
      zoneValues: {
        AuthSession._workflowKey: () {
          check();
          if (revision != _revision) throw const AuthWorkflowException();
        },
      },
    );
  }

  bool rebind() {
    if (_closed ||
        AuthSession.expired ||
        AuthSession.accessToken == null ||
        ownerKey == null ||
        ownerKey != AuthSession.ownerKey) {
      return false;
    }
    _token = AuthSession.accessToken;
    _revision = AuthSession.revision;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _closed = true;
    AuthSession.changes.removeListener(_changed);
    super.dispose();
  }
}
