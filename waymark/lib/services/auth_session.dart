class AuthSession {
  static String? accessToken;
  static String? username;

  static void clear() {
    accessToken = null;
    username = null;
  }
}
