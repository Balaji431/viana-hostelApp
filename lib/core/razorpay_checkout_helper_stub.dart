import 'package:url_launcher/url_launcher.dart';
import 'api_service.dart';

class RazorpayCheckoutHelper {
  static bool get isWebModalSupported => false;

  static Future<Map<String, dynamic>> openCheckout({
    required String orderId,
    required String keyId,
    required double amount,
    required String name,
    required String email,
    String? contact,
    String? checkoutUrl,
  }) async {
    if (checkoutUrl == null || checkoutUrl.isEmpty) {
      return {'success': false, 'message': 'No checkout URL available.'};
    }

    Uri uri = Uri.parse(checkoutUrl);
    if (uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == 'backend' || uri.host.isEmpty) {
      final baseUri = ApiService.buildUri('');
      uri = uri.replace(
        scheme: baseUri.scheme.isNotEmpty ? baseUri.scheme : 'https',
        host: baseUri.host.isNotEmpty ? baseUri.host : 'vstay.saveetha.com',
        port: baseUri.hasPort ? baseUri.port : null,
      );
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return {'success': true, 'launched': true};
    } else {
      await launchUrl(uri);
      return {'success': true, 'launched': true};
    }
  }
}
