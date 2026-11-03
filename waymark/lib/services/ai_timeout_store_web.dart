import 'package:web/web.dart' as web;

String _key(String scope) => 'waymark.ai.timeout.v1.$scope';
Future<int?> readTimeout(String scope) async {
  try {
    return int.tryParse(web.window.localStorage.getItem(_key(scope)) ?? '');
  } catch (_) {
    return null;
  }
}

Future<bool> writeTimeout(String scope, int seconds) async {
  try {
    web.window.localStorage.setItem(_key(scope), seconds.toString());
    return true;
  } catch (_) {
    return false;
  }
}
