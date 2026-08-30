import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../core/api_service.dart';
import '../../core/razorpay_checkout_helper.dart';
import '../../core/styles.dart';
import '../../core/top_notification.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../widgets/add_funds_dialog.dart';

class StudentWalletScreen extends StatefulWidget {
  const StudentWalletScreen({super.key});

  @override
  State<StudentWalletScreen> createState() => _StudentWalletScreenState();
}

class _StudentWalletScreenState extends State<StudentWalletScreen> {
  double _walletBalance = 0.0;
  List<Map<String, dynamic>> _transactions = [];
  Map<String, dynamic>? _stayRequest;
  bool _isLoading = true;
  bool _isAddingFunds = false; // true while creating Razorpay order
  int _holdSecondsLeft = 0;
  Timer? _countdownTimer;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    final user = Provider.of<UserProvider>(context, listen: false);
    _walletBalance = user.walletBalance;
    _isLoading = (_walletBalance == 0.0 && _transactions.isEmpty);
    _loadWalletData(silent: _walletBalance > 0);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _holdSecondsLeft > 0) {
        setState(() => _holdSecondsLeft--);
      }
    });
    // Periodic refresh every 15s
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _loadWalletData(silent: true);
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollingTimer?.cancel();
    super.dispose();
  }

  String _getEffectiveEmail(UserProvider user) {
    if (user.email.trim().isNotEmpty && user.email.contains('@')) {
      return user.email.trim();
    }
    final raw = user.email.trim().isNotEmpty
        ? user.email.trim()
        : (user.username.trim().isNotEmpty
            ? user.username.trim()
            : user.studentId.trim());
    if (raw.isNotEmpty) {
      return raw.contains('@') ? raw : '$raw.simats@saveetha.com';
    }
    return 'student@saveetha.com';
  }

  Future<void> _loadWalletData({bool silent = false}) async {
    if (!silent && _walletBalance == 0.0 && _transactions.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final user = Provider.of<UserProvider>(context, listen: false);
      final email = _getEffectiveEmail(user);

      final res = await ApiService.fetchWalletInfo(
        email: email,
        regNo: user.username,
        studentId: user.dbId,
      );
      if (mounted) {
        if (res['success'] == true) {
          final txns = (res['transactions'] as List<dynamic>?) ?? [];
          final stay = res['stay_request'] as Map<String, dynamic>?;
          final balance = double.tryParse(res['balance']?.toString() ?? '0') ?? 0.0;
          user.setWalletBalance(balance);
          setState(() {
            _walletBalance = balance;
            _transactions = txns.map((e) => Map<String, dynamic>.from(e)).toList();
            _stayRequest = stay;
            if (stay != null && stay['hold_remaining_seconds'] != null) {
              _holdSecondsLeft = int.tryParse(stay['hold_remaining_seconds'].toString()) ?? 0;
            }
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _payTemporaryStayFromWallet(String requestId, double amount) async {
    final user = Provider.of<UserProvider>(context, listen: false);
    final email = _getEffectiveEmail(user);

    if (_walletBalance < amount) {
      final shortage = amount - _walletBalance;
      TopNotification.showInsufficientBalance(
        context,
        currentBalance: _walletBalance,
        requiredAmount: amount,
        onTopUp: () => _showAddFundsDialog(
          defaultAmount: (shortage < 100 ? 100 : shortage.ceilToDouble()),
        ),
      );
      return;
    }

    final double balanceAfter = _walletBalance - amount;
    final String roomName = (_stayRequest?['room_code'] != null && _stayRequest!['room_code'].toString().isNotEmpty)
        ? _stayRequest!['room_code']
        : (_stayRequest?['room_no'] ?? 'N/A');

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.account_balance_wallet, color: Color(0xFF0288D1), size: 22),
            ),
            const SizedBox(width: 10),
            Text('Confirm Payment', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: const Color(0xFF1B2B48))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to debit the fee from your wallet to confirm your room allocation?',
              style: GoogleFonts.inter(fontSize: 12.5, color: Colors.grey.shade700, height: 1.3),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  _confirmRow('Room Allocation', roomName),
                  const Divider(height: 12),
                  _confirmRow('Stay Amount', '₹${amount.toStringAsFixed(2)}', isBold: true, valueColor: const Color(0xFF1B2B48)),
                  const Divider(height: 12),
                  _confirmRow('Current Wallet', '₹${_walletBalance.toStringAsFixed(2)}'),
                  const Divider(height: 12),
                  _confirmRow('Balance After Pay', '₹${balanceAfter.toStringAsFixed(2)}', valueColor: const Color(0xFF0288D1), isBold: true),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Confirm & Pay', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13.5)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final res = await ApiService.payStayFromWallet(email: email, requestId: requestId);
      if (mounted) {
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment successful! Your room has been allocated.'),
              backgroundColor: Color(0xFF2E7D32),
            ),
          );
          await user.refreshUserData();
          _loadWalletData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Payment failed'), backgroundColor: Colors.red),
          );
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  static Widget _confirmRow(String label, String value, {bool isBold = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade600)),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: valueColor ?? const Color(0xFF334155),
          ),
        ),
      ],
    );
  }

  void _showAddFundsDialog({double? defaultAmount}) {
    AddFundsDialog.show(
      context,
      currentBalance: _walletBalance,
      defaultAmount: defaultAmount,
      onFundsAdded: () => _loadWalletData(silent: false),
    );
  }

  Future<void> _launchRazorpayCheckout(double amount, {UserProvider? user}) async {
    if (!mounted) return;
    setState(() => _isAddingFunds = true);

    try {
      final activeUser = user ?? Provider.of<UserProvider>(context, listen: false);
      final email = _getEffectiveEmail(activeUser);
      final fullName = activeUser.userName.isNotEmpty ? activeUser.userName : 'Student';

      final res = await ApiService.createRazorpayOrder(
        email: email,
        amount: amount,
        name: fullName,
      );

      if (!mounted) return;

      if (res['success'] != true || res['checkout_url'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Could not initiate payment: ${res['message'] ?? 'Unknown error'}'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final payRes = await RazorpayCheckoutHelper.openCheckout(
        orderId: res['order_id']?.toString() ?? '',
        keyId: res['key_id']?.toString() ?? '',
        amount: amount,
        name: fullName,
        email: email,
        checkoutUrl: res['checkout_url']?.toString(),
      );

      if (!mounted) return;

      if (payRes['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '₹${amount.toStringAsFixed(2)} added to your wallet successfully!'),
            backgroundColor: Colors.green.shade700,
          ),
        );
        _loadWalletData(silent: false);
      } else if (payRes['cancelled'] != true && payRes['launched'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(payRes['message'] ?? 'Payment was not completed.'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAddingFunds = false);
    }
  }

  void _showTransactionsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Wallet Transactions', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Divider(),
              Expanded(
                child: _transactions.isEmpty
                    ? Center(child: Text('No transactions yet', style: GoogleFonts.inter(color: Colors.grey)))
                    : ListView.separated(
                        itemCount: _transactions.length,
                        separatorBuilder: (_, __) => const Divider(height: 12),
                        itemBuilder: (ctx, idx) {
                          final t = _transactions[idx];
                          final isCredit = (t['txn_type'] ?? '') == 'credit';
                          final amt = double.tryParse(t['amount']?.toString() ?? '0') ?? 0.0;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: isCredit ? Colors.green.shade50 : Colors.red.shade50,
                              child: Icon(
                                isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                                size: 16,
                                color: isCredit ? Colors.green : Colors.red,
                              ),
                            ),
                            title: Text(t['description'] ?? 'Transaction', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                            subtitle: Text(t['created_at'] ?? '', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey)),
                            trailing: Text(
                              '${isCredit ? '+' : '-'}₹${amt.toStringAsFixed(2)}',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isCredit ? Colors.green.shade700 : Colors.red.shade700,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatHoldCountdown(int seconds) {
    if (seconds <= 0) return 'Expired';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _convertAmountToWords(int n) {
    if (n <= 0) return '';
    if (n >= 10000000) return '${(n / 10000000).toStringAsFixed(1)} Crore Rupees';
    if (n >= 100000) return '${(n / 100000).toStringAsFixed(1)} Lakh Rupees';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)} Thousand Rupees';
    return '$n Rupees';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const SkeuomorphicNavBar(
        title: 'Wallet & Fees',
      ),
      body: LinenGridBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF1B2B48)))
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Wallet Pill Bar
                    _buildWalletHeaderBar(),
                    const SizedBox(height: 18),

                    // Approved Temporary Stay Request Card (with 24h Hold Timer)
                    if (_stayRequest != null) _buildTemporaryStayCard(),

                    const SizedBox(height: 18),
                    // Other Fee Items Card
                    _buildStandardFeeCards(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildWalletHeaderBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF427DF6), Color(0xFF2366EB)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Wallet Icon + Label + Amount
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.35)),
                ),
                child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                'WALLET',
                style: GoogleFonts.lato(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '₹${NumberFormat('#,##,##0.00').format(_walletBalance)}',
                style: GoogleFonts.outfit(
                  fontSize: 16.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),

          // Right: History + Add Button
          Row(
            children: [
              InkWell(
                onTap: _showTransactionsDialog,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.35)),
                  ),
                  child: const Icon(Icons.history_rounded, color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: () => _showAddFundsDialog(defaultAmount: 0),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.add, color: Colors.white, size: 15),
                      SizedBox(width: 4),
                      Text(
                        'Add',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTemporaryStayCard() {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    final req = _stayRequest!;
    final status = (req['status'] ?? 'pending').toString().toLowerCase();
    final paymentStatus = (req['payment_status'] ?? 'unpaid').toString().toLowerCase();
    final amount = double.tryParse(req['amount']?.toString() ?? '0') ?? 0.0;
    final isApproved = status == 'approved' && paymentStatus != 'paid';
    final isPaid = status == 'allocated' || paymentStatus == 'paid';
    final hasEnoughFunds = _walletBalance >= amount;
    final double shortage = (amount - _walletBalance) > 0 ? (amount - _walletBalance) : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.75) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isApproved ? const Color(0xFF0288D1) : const Color(0xFF10B981),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isApproved
                      ? (isDark ? const Color(0xFF0288D1).withOpacity(0.2) : const Color(0xFFE0F2FE))
                      : (isDark ? const Color(0xFF10B981).withOpacity(0.2) : const Color(0xFFD1FAE5)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isApproved ? Icons.hourglass_top_rounded : Icons.check_circle_rounded,
                  color: isApproved ? const Color(0xFF38BDF8) : const Color(0xFF10B981),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isApproved ? 'Short Stay Approved — Room on 24h Hold' : 'Short Stay Confirmed & Allocated',
                  style: GoogleFonts.outfit(
                    color: isDark ? Colors.white : const Color(0xFF1B2B48),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isApproved && _holdSecondsLeft > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE65100),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        _formatHoldCountdown(_holdSecondsLeft),
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${req['hostel_name'] ?? 'Hostel'} • Room ${req['room_no'] ?? req['room_code'] ?? ''} (${req['room_type'] ?? ''})',
                  style: GoogleFonts.inter(
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Duration: ${req['from_date'] ?? ''} to ${req['to_date'] ?? ''} (${req['duration_value'] ?? 1} ${req['duration_type'] ?? 'days'})',
                  style: GoogleFonts.inter(
                    color: isDark ? Colors.white70 : const Color(0xFF64748B),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Stay Fee',
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    '₹${amount.toStringAsFixed(2)}',
                    style: GoogleFonts.outfit(
                      color: isDark ? const Color(0xFFFDE047) : const Color(0xFF1B2B48),
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (isApproved)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasEnoughFunds ? const Color(0xFF0288D1) : const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 2,
                  ),
                  icon: Icon(hasEnoughFunds ? Icons.payment : Icons.add_card, size: 16),
                  label: Text(
                    hasEnoughFunds ? 'Pay from Wallet' : '+ Add ₹${shortage.toStringAsFixed(2)}',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: () {
                    if (hasEnoughFunds) {
                      _payTemporaryStayFromWallet(req['request_id'], amount);
                    } else {
                      _showAddFundsDialog(defaultAmount: (shortage < 100 ? 100 : shortage.ceilToDouble()));
                    }
                  },
                )
              else if (isPaid)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF10B981).withOpacity(0.2) : const Color(0xFFD1FAE5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF10B981)),
                  ),
                  child: const Text(
                    'PAID & ACTIVE',
                    style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStandardFeeCards() {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.75) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.14) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFFD4AF37).withOpacity(0.2) : const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF0288D1),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'VStay In-App Dedicated Wallet',
                  style: GoogleFonts.outfit(
                    color: isDark ? Colors.white : const Color(0xFF1B2B48),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'This is your dedicated VStay in-app digital wallet. Add funds directly to your wallet to seamlessly pay for hostel stay renewals, room changes, short/temporary stays, and all in-app hostel services with instant confirmation.',
            style: GoogleFonts.inter(
              color: isDark ? Colors.white70 : const Color(0xFF475569),
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          // Feature Highlights
          _buildWalletFeatureRow(
            icon: Icons.flash_on_rounded,
            title: 'Instant In-App Payments',
            desc: 'Renew stay and confirm room allocations with one click.',
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          _buildWalletFeatureRow(
            icon: Icons.add_card_rounded,
            title: 'Multiple Payment Methods',
            desc: 'Add funds securely via UPI, Debit/Credit Cards & Netbanking.',
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          _buildWalletFeatureRow(
            icon: Icons.receipt_long_rounded,
            title: 'Real-Time Transaction Ledger',
            desc: 'View comprehensive history of deposits and fee deductions.',
            isDark: isDark,
          ),
          const SizedBox(height: 16),
          // Add Funds Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48),
                foregroundColor: isDark ? const Color(0xFF1B2B48) : Colors.white,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
              label: Text(
                'Add Funds to Wallet',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              onPressed: () => _showAddFundsDialog(defaultAmount: 1000),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletFeatureRow({
    required IconData icon,
    required String title,
    required String desc,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF2563EB)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
              Text(
                desc,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
