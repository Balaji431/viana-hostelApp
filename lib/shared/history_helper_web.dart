import 'dart:js' as js;
import 'package:flutter/foundation.dart';

class HistoryHelper {
  static js.JsFunction? _popStateListener;

  static void addPopStateListener(VoidCallback onPop) {
    removePopStateListener(); // Avoid duplicate listeners if called multiple times

    _popStateListener = js.JsFunction.withThis((dynamic self, dynamic event) {
      onPop();
    });
    
    try {
      js.context['window'].callMethod('addEventListener', [
        'popstate',
        _popStateListener,
      ]);
    } catch (e) {
      debugPrint('Error adding popstate listener: $e');
    }
  }

  static void removePopStateListener() {
    if (_popStateListener != null) {
      try {
        js.context['window'].callMethod('removeEventListener', [
          'popstate',
          _popStateListener,
        ]);
      } catch (e) {
        debugPrint('Error removing popstate listener: $e');
      }
      _popStateListener = null;
    }
  }

  static void pushState() {
    try {
      js.context['history'].callMethod('pushState', [
        js.JsObject.jsify({'nested': true}),
        '',
        js.context['location']['href'],
      ]);
    } catch (e) {
      debugPrint('Error pushing history state: $e');
    }
  }
}
