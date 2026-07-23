class ApiSession {
  static String? currentUserId;
  static String? currentUsername;
  static String? currentUserRole;
  static String? currentToken;

  static void clear() {
    currentUserId = null;
    currentUsername = null;
    currentUserRole = null;
    currentToken = null;
  }
}
