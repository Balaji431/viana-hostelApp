// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

class HistoryHelper {
  static StreamSubscription? _popStateSubscription;

  static void addPopStateListener(VoidCallback onPop) {
    removePopStateListener(); // Avoid duplicate listeners if called multiple times

    try {
      _popStateSubscription = html.window.onPopState.listen((event) {
        onPop();
      });
    } catch (e) {
      debugPrint('Error adding popstate listener: $e');
    }
  }

  static void removePopStateListener() {
    if (_popStateSubscription != null) {
      try {
        _popStateSubscription!.cancel();
      } catch (e) {
        debugPrint('Error removing popstate listener: $e');
      }
      _popStateSubscription = null;
    }
  }

  static void pushState() {
    try {
      html.window.history.pushState({'nested': true}, '', html.window.location.href);
    } catch (e) {
      debugPrint('Error pushing history state: $e');
    }
  }
}
