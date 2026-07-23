// ignore_for_file: avoid_print
import 'package:flutter/foundation.dart';

class AppLogger {
  static String? _currentUserEmail;
  static bool _isProduction = false;

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

  static bool get _shouldLog {
    if (kDebugMode || !_isProduction) {
      // Always allow terminal logs in debug mode and dev environment
      return true;
    }
    // Production environment: only allow logs for the developer's email
    return _currentUserEmail?.trim().toLowerCase() == 'dasettisribalu@gmail.com';
  }

  static void _updateDebugPrint() {
    if (_shouldLog) {
      // Restore standard Flutter debugPrint
      debugPrint = debugPrintThrottled;
    } else {
      // Silence debugPrint in production for users other than the developer
      debugPrint = (String? message, {int? wrapWidth}) {};
    }
  }

  static void info(String message) {
    if (_shouldLog) {
      print("[INFO] $message");
    }
  }

  static void warning(String message) {
    if (_shouldLog) {
      print("[WARNING] $message");
    }
  }

  static void error(String message) {
    if (_shouldLog) {
      print("[ERROR] $message");
    }
  }

  static void api(String message) {
    if (_shouldLog) {
      print("[API] $message");
    }
  }

  static void request(String message) {
    if (_shouldLog) {
      print("[REQUEST] $message");
    }
  }

  static void response(String message) {
    if (_shouldLog) {
      print("[RESPONSE] $message");
    }
  }
}
