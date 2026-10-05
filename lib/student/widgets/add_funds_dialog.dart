import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api_service.dart';
import '../../core/razorpay_checkout_helper_web.dart'
    if (dart.library.io) '../../core/razorpay_checkout_helper_stub.dart';
import '../../core/top_notification.dart';
import '../../shared/user_provider.dart';

class AddFundsDialog extends StatefulWidget {
  final double currentBalance;
  final double? defaultAmount;
  final VoidCallback? onFundsAdded;

  const AddFundsDialog({
    super.key,
    required this.currentBalance,
    this.defaultAmount,
    this.onFundsAdded,
  });

  static Future<void> show(
    BuildContext context, {
    required double currentBalance,
    double? defaultAmount,
    VoidCallback? onFundsAdded,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AddFundsDialog(
        currentBalance: currentBalance,
        defaultAmount: defaultAmount,
        onFundsAdded: onFundsAdded,
      ),
    );
  }

  @override
  State<AddFundsDialog> createState() => _AddFundsDialogState();
}

class _AddFundsDialogState extends State<AddFundsDialog> {
  late TextEditingController _amountController;
  bool _isProcessing = false;
  double _enteredAmount = 0.0;

  @override
  void initState() {
    super.initState();
    final initial = widget.defaultAmount != null && widget.defaultAmount! > 0
        ? widget.defaultAmount!.toStringAsFixed(2)
        : '0.00';
    _amountController = TextEditingController(text: initial);
    _enteredAmount = double.tryParse(initial) ?? 0.0;

    _amountController.addListener(() {
      final val = double.tryParse(_amountController.text.trim()) ?? 0.0;
      if (val != _enteredAmount) {
        setState(() {
          _enteredAmount = val;
        });
      }
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _stepAmount(double delta) {
    double current = double.tryParse(_amountController.text.trim()) ?? 0.0;
    double next = current + delta;
    if (next < 0) next = 0;
    _amountController.text = next.toStringAsFixed(2);
  }

  String _numberToWords(double amount) {
    try {
      final int val = amount.toInt();
      if (val <= 0) return 'zero';

      final units = [
        '', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
        'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
        'sixteen', 'seventeen', 'eighteen', 'nineteen'
      ];
      final tens = [
        '', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy',
        'eighty', 'ninety'
      ];

      String convertChunk(int n) {
        if (n <= 0) return '';
        if (n < 20) return units[n];
        if (n < 100) {
          final tenIdx = n ~/ 10;
          final unitIdx = n % 10;
          return tens[tenIdx] + (unitIdx != 0 ? ' ' + units[unitIdx] : '');
        }
        final hundredIdx = (n ~/ 100);
        final hundredPrefix = (hundredIdx < units.length) ? units[hundredIdx] : convertChunk(hundredIdx);
        return hundredPrefix +
            ' hundred' +
            (n % 100 != 0 ? ' and ' + convertChunk(n % 100) : '');
      }

      String res = '';
      int rem = val;

      if (rem >= 10000000) {
        res += convertChunk(rem ~/ 10000000) + ' crore ';
        rem %= 10000000;
      }
      if (rem >= 100000) {
        res += convertChunk(rem ~/ 100000) + ' lakh ';
        rem %= 100000;
      }
      if (rem >= 1000) {
        res += convertChunk(rem ~/ 1000) + ' thousand ';
        rem %= 1000;
      }
      if (rem > 0) {
        res += convertChunk(rem);
      }
      return res.trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _showTermsAndConditions() async {
    final String pdfUrl = '${ApiService.baseUrl}simats_policies.pdf';
    final Uri uri = Uri.parse(pdfUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(Uri.parse('simats_policies.pdf'), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error opening simats_policies.pdf: $e');
      try {
        await launchUrl(Uri.parse('simats_policies.pdf'), mode: LaunchMode.platformDefault);
      } catch (_) {}
    }
  }

  Future<void> _handleDeposit() async {
    final amt = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amt <= 0) {
      TopNotification.show(
        context,
        type: TopNotificationType.error,
        title: 'Invalid Amount',
        message: 'Please enter a valid deposit amount greater than ₹0.',
      );
      return;
    }

    setState(() => _isProcessing = true);
    final user = Provider.of<UserProvider>(context, listen: false);
    final email = user.email.isNotEmpty
        ? user.email
        : (user.username.contains('@')
            ? user.username
            : '${user.username}.simats@saveetha.com');
    final fullName = user.userName.isNotEmpty ? user.userName : 'Student';

    try {
      final res = await ApiService.createRazorpayOrder(
        email: email,
        amount: amt,
        name: fullName,
      );

      if (!mounted) return;

      if (res['success'] != true || res['checkout_url'] == null) {
        setState(() => _isProcessing = false);
        TopNotification.show(
          context,
          type: TopNotificationType.error,
          title: 'Payment Error',
          message: res['message']?.toString() ?? 'Could not initiate Razorpay order.',
        );
        return;
      }

      final payRes = await RazorpayCheckoutHelper.openCheckout(
        orderId: res['order_id']?.toString() ?? '',
        keyId: res['key_id']?.toString() ?? '',
        amount: amt,
        name: fullName,
        email: email,
        checkoutUrl: res['checkout_url']?.toString(),
      );

      if (!mounted) return;
      setState(() => _isProcessing = false);

      if (payRes['launched'] == true) {
        Navigator.pop(context); // Close dialog
        TopNotification.show(
          context,
          type: TopNotificationType.info,
          title: 'Opening Payment Gateway...',
          message: 'Complete the payment in browser and tap Return to VStay.',
        );
      } else if (payRes['success'] == true) {
        Navigator.pop(context); // Close dialog
        TopNotification.show(
          context,
          type: TopNotificationType.success,
          title: 'Funds Deposited! 🎉',
          message: '₹${NumberFormat('#,##,##0.00').format(amt)} added to your wallet successfully.',
        );
        user.fetchWalletBalance();
        widget.onFundsAdded?.call();
      } else if (payRes['cancelled'] == true) {
        TopNotification.show(
          context,
          type: TopNotificationType.warning,
          title: 'Payment Cancelled',
          message: 'You cancelled the deposit transaction.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        TopNotification.show(
          context,
          type: TopNotificationType.error,
          title: 'Error',
          message: 'Deposit failed: $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final balanceFormatted = NumberFormat('#,##,###').format(widget.currentBalance.toInt());

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 360,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Slate Header with Title and Close 'X' ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFF63748A), // Slate Grey from Image 1
              child: Row(
                children: [
                  const SizedBox(width: 24), // Balance the 'X' button
                  Expanded(
                    child: Text(
                      'Add Funds',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.lato(
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ──
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── CURRENT BALANCE Box ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F4F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'CURRENT BALANCE',
                          style: GoogleFonts.lato(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF64748B),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₹$balanceFormatted',
                          style: GoogleFonts.lato(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Amount (₹) Label ──
                  Text(
                    'Amount (₹)',
                    style: GoogleFonts.lato(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),

                  const SizedBox(height: 6),

                  // ── Input Box with Blue Outline & Steppers ──
                  Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF3B82F6), width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: GoogleFonts.lato(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1E293B),
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: InputBorder.none,
                              hintText: '0.00',
                            ),
                          ),
                        ),
                        // Stepper Arrows
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            InkWell(
                              onTap: () => _stepAmount(100.0),
                              child: const Icon(Icons.arrow_drop_up, size: 18, color: Color(0xFF64748B)),
                            ),
                            InkWell(
                              onTap: () => _stepAmount(-100.0),
                              child: const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),

                  const SizedBox(height: 6),

                  // ── In Words Subtitle ──
                  Text(
                    '${_numberToWords(_enteredAmount)} rupees only',
                    style: GoogleFonts.lato(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: const Color(0xFF64748B),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── View Terms & Conditions Link ──
                  Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: _showTermsAndConditions,
                      child: Text(
                        'View Terms & Conditions',
                        style: GoogleFonts.lato(
                          fontSize: 11.5,
                          color: const Color(0xFF2563EB),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Action Buttons (Cancel & Deposit) ──
                  Row(
                    children: [
                      // Cancel Button
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF1E293B),
                            side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.lato(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Deposit Button (Glossy Blue Gradient)
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF5B93F7), Color(0xFF2563EB)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2563EB).withOpacity(0.35),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isProcessing ? null : _handleDeposit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: _isProcessing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'Deposit',
                                    style: GoogleFonts.lato(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
