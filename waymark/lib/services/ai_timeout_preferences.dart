import 'ai_timeout_store.dart' as platform;

/// Only an integer timeout is persisted. Never URL, model, token or AuthSession.
class AiTimeoutPreferences {
  const AiTimeoutPreferences();
  static const presets = [30, 60, 120, 180, 300];
  static String scope(bool graph) =>
      graph ? 'openai-compatible-graph-v2' : 'openai-compatible-nodes-v1';
  static bool valid(Object? seconds) =>
      seconds is int && seconds >= 10 && seconds <= 600;
  static int? parse(String input) {
    if (!RegExp(r'^\d{1,3}$').hasMatch(input.trim())) return null;
    final seconds = int.tryParse(input.trim());
    return valid(seconds) ? seconds : null;
  }

  Future<int?> read(String scope) async {
    final value = await platform.readTimeout(scope);
    return valid(value) ? value : null;
  }

  Future<bool> write(String scope, int seconds) {
    if (!valid(seconds)) {
      throw const FormatException('Thời gian chờ cần 10–600 giây.');
    }
    return platform.writeTimeout(scope, seconds);
  }
}
