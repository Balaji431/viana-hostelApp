// ignore_for_file: avoid_print
import 'package:flutter/foundation.dart';

/// Centralised application logger.
///
/// Log categories printed to the console:
///   [INFO]     — general lifecycle events
///   [WARNING]  — non-fatal unexpected conditions
///   [ERROR]    — failures that may affect the user
///   [API]      — API-layer messages (FCM token, auth calls)
///   [REQUEST]  — every outgoing HTTP request (method + URL)
///   [RESPONSE] — every HTTP response (status + truncated body)
///   [NAV]      — screen / route navigation events
///   [AUTH]     — login, logout, session restore
///   [STATE]    — provider / state-machine transitions
///   [NOTIF]    — push-notification / FCM events
class AppLogger {
  static String? _currentUserEmail;
  static bool _isProduction = false;

  /// Max chars logged for a response body before truncation.
  static const int _maxBodyLength = 400;

  static String? get currentUserEmail => _currentUserEmail;

  static set currentUserEmail(String? email) {
    _currentUserEmail = email;
    _updateDebugPrint();
  }

  static bool get isProduction => _isProduction;

  static set isProduction(bool value) {
    _isProduction = value;
    _updateDebugPrint();
  }

  static bool get _shouldLog => kDebugMode;


  static void _updateDebugPrint() {
    if (_shouldLog) {
      // Restore standard Flutter debugPrint
      debugPrint = debugPrintThrottled;
    } else {
      // Silence debugPrint in production for users other than the developer
      debugPrint = (String? message, {int? wrapWidth}) {};
    }
  }

  /// Truncate long strings so the console stays readable.
  static String _truncate(String s) =>
      s.length > _maxBodyLength ? '${s.substring(0, _maxBodyLength)}…' : s;

  // ── Core levels ─────────────────────────────────────────────────────────────

  static void info(String message) {
    if (_shouldLog) print('[INFO] $message');
  }

  static void warning(String message) {
    if (_shouldLog) print('[WARNING] $message');
  }

  static void error(String message) {
    if (_shouldLog) print('[ERROR] $message');
  }

  // ── HTTP ────────────────────────────────────────────────────────────────────

  static void api(String message) {
    if (_shouldLog) print('[API] $message');
  }

  static void request(String message) {
    if (_shouldLog) print('[REQUEST] $message');
  }

  /// Log an HTTP response. Optionally include [body] for a truncated preview.
  static void response(String message, {String? body}) {
    if (!_shouldLog) return;
    if (body != null && body.isNotEmpty) {
      print('[RESPONSE] $message  body=${_truncate(body)}');
    } else {
      print('[RESPONSE] $message');
    }
  }

  // ── Navigation ───────────────────────────────────────────────────────────────

  /// Call when navigating to a new screen or route.
  static void nav(String message) {
    if (_shouldLog) print('[NAV] $message');
  }

  // ── Auth ────────────────────────────────────────────────────────────────────

  /// Call on login, logout, session restore, token events.
  static void auth(String message) {
    if (_shouldLog) print('[AUTH] $message');
  }

  // ── State ────────────────────────────────────────────────────────────────────

  /// Call when a provider or state-machine value changes.
  static void state(String message) {
    if (_shouldLog) print('[STATE] $message');
  }

  // ── Notifications ────────────────────────────────────────────────────────────

  /// Call for FCM / push-notification events.
  static void notif(String message) {
    if (_shouldLog) print('[NOTIF] $message');
  }
}

