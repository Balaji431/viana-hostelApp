// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:js' as js;
import 'package:flutter/foundation.dart';
import 'api_service.dart';

class RazorpayCheckoutHelper {
  static bool get isWebModalSupported => kIsWeb;

  static Future<Map<String, dynamic>> openCheckout({
    required String orderId,
    required String keyId,
    required double amount,
    required String name,
    required String email,
    String? contact,
    String? checkoutUrl,
  }) async {
    final completer = Completer<Map<String, dynamic>>();

    final options = {
      'key': keyId,
      'amount': (amount * 100).round(),
      'currency': 'INR',
      'name': 'VStay',
      'description': 'Wallet Top-up',
      'order_id': orderId,
      'prefill': {
        'email': email,
        'name': name,
        if (contact != null && contact.isNotEmpty) 'contact': contact,
      },
      'theme': {
        'color': '#1B2B48',
      },
    };

    final optionsJson = jsonEncode(options);

    void onSuccess(dynamic responseStr) async {
      try {
        final Map<String, dynamic> res = jsonDecode(responseStr.toString());
        final paymentId = res['razorpay_payment_id']?.toString() ?? '';
        final resOrderId = res['razorpay_order_id']?.toString() ?? orderId;
        final signature = res['razorpay_signature']?.toString() ?? '';

        final verifyRes = await ApiService.verifyRazorpayPayment(
          paymentId: paymentId,
          orderId: resOrderId,
          signature: signature,
          email: email,
          amount: amount,
        );

        if (!completer.isCompleted) {
          completer.complete(verifyRes);
        }
      } catch (e) {
        if (!completer.isCompleted) {
          completer.complete({
            'success': false,
            'message': 'Error completing payment verification: $e',
          });
        }
      }
    }

    void onFailure(dynamic errorMsg) {
      if (!completer.isCompleted) {
        final msg = errorMsg?.toString() ?? 'Payment cancelled';
        completer.complete({
          'success': false,
          'cancelled': msg.toLowerCase().contains('cancel'),
          'message': msg,
        });
      }
    }

    try {
      js.context.callMethod('openRazorpayModal', [
        optionsJson,
        js.allowInterop(onSuccess),
        js.allowInterop(onFailure),
      ]);
    } catch (e) {
      debugPrint('Error invoking openRazorpayModal: $e');
      if (!completer.isCompleted) {
        completer.complete({
          'success': false,
          'message': 'Could not open payment window: $e',
        });
      }
    }

    return completer.future;
  }
}
