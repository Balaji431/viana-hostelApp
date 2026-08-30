import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api_service.dart';
import '../../core/razorpay_checkout_helper.dart';
import '../../core/styles.dart';
import '../../core/top_notification.dart';
import '../../shared/main_layout.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../widgets/add_funds_dialog.dart';
import 'student_wallet_screen.dart';

class NoDuePage extends StatefulWidget {
  const NoDuePage({super.key});

  @override
  State<NoDuePage> createState() => _NoDuePageState();
}

class _NoDuePageState extends State<NoDuePage> {
  bool _isLoading = true;
  bool _isAddingFunds = false;
  bool _showWalletErrorOnCard = false;
  bool _isWalletGridView = true; // Toggle between Grid View and Table View for Wallet
  List<Map<String, dynamic>> _requests = [];
  double _walletBalance = 0.0;
  List<Map<String, dynamic>> _transactions = [];

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

  Future<void> _launchRazorpayCheckout(double amount) async {
    if (!mounted) return;
    setState(() => _isAddingFunds = true);

    try {
      final user = Provider.of<UserProvider>(context, listen: false);
      final email = _getEffectiveEmail(user);
      final fullName = user.userName.isNotEmpty ? user.userName : 'Student';

      final res = await ApiService.createRazorpayOrder(
        email: email,
        amount: amount,
        name: fullName,
      );

      if (!mounted) return;

      if (res['success'] != true || res['checkout_url'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not initiate payment: ${res['message'] ?? 'Unknown error'}'),
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
            content: Text('₹${amount.toStringAsFixed(2)} added to wallet successfully!'),
            backgroundColor: Colors.green.shade700,
          ),
        );
        _loadData();
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
          SnackBar(content: Text('Payment error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isAddingFunds = false);
    }
  }

  final List<Map<String, dynamic>> _walletFeeItems = [
    {
      'title': 'TECH STAR SUMMIT 2026',
      'cycle': '-',
      'dueDate': '16 Jul 2026',
      'totalFee': '₹2,200',
      'scholarship': 'N/A',
      'totalPayable': '₹2,200',
      'status': 'Paid',
      'isPaid': true,
      'amountNum': 2200,
    },
    {
      'title': 'Culturals Simmam 2026',
      'cycle': '-',
      'dueDate': '05 Jun 2026',
      'totalFee': '₹2,800',
      'scholarship': 'N/A',
      'totalPayable': '₹2,800',
      'status': 'Paid',
      'isPaid': true,
      'amountNum': 2800,
    },
  ];

  @override
  void initState() {
    super.initState();
    final user = context.read<UserProvider>();
    _walletBalance = user.walletBalance;
    _loadData();
  }

  Future<void> _loadData() async {
    if (_walletBalance == 0.0 && _requests.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final user = context.read<UserProvider>();
      final email = _getEffectiveEmail(user);
      final studentId = user.dbId ?? 1;

      // Fetch live wallet balance and room change requests in parallel
      final results = await Future.wait([
        ApiService.fetchWalletInfo(
          email: email,
          regNo: user.username,
          studentId: user.dbId,
        ),
        ApiService.getRoomChangeRequests(
          status: 'all',
          studentId: studentId,
        ),
      ]);

      final walletRes = results[0];
      final res = results[1];

      if (walletRes['success'] == true) {
        _walletBalance = double.tryParse(walletRes['balance']?.toString() ?? '0') ?? 0.0;
        user.setWalletBalance(_walletBalance);
        final txns = (walletRes['transactions'] as List<dynamic>?) ?? [];
        _transactions = txns.map((e) => Map<String, dynamic>.from(e)).toList();
      }

      if (res['status'] == 'success' && res['data'] != null) {
        final list = (res['data'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        setState(() {
          _requests = list;
        });
      }
    } catch (e) {
      debugPrint("Error loading no due status: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddFundsDialog({double defaultAmount = 0}) {
    AddFundsDialog.show(
      context,
      currentBalance: _walletBalance,
      defaultAmount: defaultAmount > 0 ? defaultAmount : null,
      onFundsAdded: () => _loadData(),
    );
  }

  void _showTransactionsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Wallet Transactions',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1B2B48),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_transactions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No transaction history found.',
                      style: GoogleFonts.inter(color: Colors.grey),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _transactions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final t = _transactions[i];
                      final isCredit = (t['txn_type'] ?? 'credit') == 'credit';
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

  String _convertAmountToWords(num amount) {
    final int intVal = amount.toInt();
    if (intVal <= 0) return 'zero rupees only';

    final units = [
      '', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine',
      'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen',
      'seventeen', 'eighteen', 'nineteen'
    ];

    final tens = [
      '', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'
    ];

    String convert(int n) {
      if (n < 20) return units[n];
      if (n < 100) return tens[n ~/ 10] + (n % 10 != 0 ? ' ${units[n % 10]}' : '');
      if (n < 1000) return '${units[n ~/ 100]} hundred${n % 100 != 0 ? ' ${convert(n % 100)}' : ''}';
      if (n < 100000) return '${convert(n ~/ 1000)} thousand${n % 1000 != 0 ? ' ${convert(n % 1000)}' : ''}';
      if (n < 10000000) return '${convert(n ~/ 100000)} lakh${n % 100000 != 0 ? ' ${convert(n % 100000)}' : ''}';
      return '${convert(n ~/ 10000000)} crore${n % 10000000 != 0 ? ' ${convert(n % 10000000)}' : ''}';
    }

    return '${convert(intVal).trim()} rupees only';
  }

  Future<void> _openSimatsPoliciesPdf() async {
    final String pdfUrl = '${ApiService.baseUrl}simats_policies.pdf';
    final Uri uri = Uri.parse(pdfUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Error opening simats_policies.pdf: $e');
      try {
        await launchUrl(uri);
      } catch (_) {}
    }
  }

  Map<String, dynamic>? get _latestRenewalTxn {
    for (final t in _transactions) {
      final desc = (t['description'] ?? '').toString().toLowerCase();
      if (desc.contains('renewal') || desc.contains('renew')) {
        return t;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>();
    final latestRequest = _requests.isNotEmpty ? _requests.first : <String, dynamic>{};
    final renewalTxn = _latestRenewalTxn;

    return LinenGridBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const SkeuomorphicNavBar(
          title: 'Wallet',
        ),
        body: RefreshIndicator(
          onRefresh: _loadData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // WALLET SECTION AT TOP (Screenshot 1)
                _buildWalletSection(),

                const SizedBox(height: 20),

                // RENEWED HOSTEL BOOKING CARD (If student has completed renewal)
                if (renewalTxn != null) ...[
                  _buildRenewedHostelCard(user, renewalTxn),
                  const SizedBox(height: 20),
                ],

                // STUDENT ROOM ALLOCATION CARD
                _buildExistingRoomCard(user),

                // REQUESTED ROOM TRANSFER CARD (If student submitted a transfer request)
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
                    ),
                  )
                else if (latestRequest.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _buildRequestedTransferCard(latestRequest),
                ],

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // WALLET SECTION COMPONENT (Screenshot 1)
  Widget _buildWalletSection() {
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

  // CARD: Renewed Hostel Booking Card (Displayed when student has completed renewal)
  Widget _buildRenewedHostelCard(UserProvider user, Map<String, dynamic> renewalTxn) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    final hostel = user.hostelName.isNotEmpty ? user.hostelName : "Vaigai Hostel";
    final roomNo = user.roomNumber.isNotEmpty ? user.roomNumber : "T-32 F02- W0-R16";
    final renewalDateStr = DateFormat('dd MMM yyyy').format(user.renewalDate);
    final amtNum = double.tryParse(renewalTxn['amount']?.toString() ?? '120000') ?? 120000.0;
    final refId = renewalTxn['reference_id'] ?? 'REF-RENEWAL';
    final datePaid = renewalTxn['created_at'] != null ? renewalTxn['created_at'].toString().split(' ')[0] : 'Confirmed';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.85) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF10B981),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withOpacity(isDark ? 0.2 : 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Icon + RENEWED HOSTEL BOOKING + Green Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'HOSTEL RENEWAL',
                  style: GoogleFonts.lato(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF1A2744),
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'RENEWED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Subtitle
          Row(
            children: [
              Icon(Icons.location_on_outlined, color: isDark ? Colors.white60 : Colors.grey, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$hostel · Thandalam Campus',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Room No & Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'Room No: ',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1A2744),
                    ),
                  ),
                  Text(
                    roomNo,
                    style: GoogleFonts.lato(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
              Text(
                'Paid: $datePaid',
                style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.grey.shade600, fontWeight: FontWeight.w500),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Renewal Fee & Period
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Renewal Paid',
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₹${NumberFormat('#,##,###').format(amtNum.toInt())}',
                      style: GoogleFonts.lato(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Extended Validity',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    renewalDateStr,
                    style: GoogleFonts.lato(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1A2744),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 3 Info Boxes: Rent, Food, Duration (+1 Year)
          Row(
            children: [
              Expanded(child: _buildInfoBox('Room Rent', '₹${NumberFormat('#,##,###').format((user.roomAmount > 0 ? user.roomAmount : 70000).toInt())}', isDark)),
              const SizedBox(width: 8),
              Expanded(child: _buildInfoBox('Food', '₹${NumberFormat('#,##,###').format((user.roomFood > 0 ? user.roomFood : 50000).toInt())}', isDark)),
              const SizedBox(width: 8),
              Expanded(child: _buildInfoBox('Stay Extended', '+1 Year', isDark)),
            ],
          ),

          const SizedBox(height: 12),

          // Ref ID Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(isDark ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.receipt_long_outlined, size: 16, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ref ID: $refId · Paid via Institutional Wallet',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : const Color(0xFF065F46),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // CARD 1: Existing Room Allotted Card (Image 1 Layout with Paid light green badge)
  Widget _buildExistingRoomCard(UserProvider user) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    final roomType = user.roomType.isNotEmpty ? user.roomType : (user.roomTypeDisplay.isNotEmpty ? user.roomTypeDisplay : "Standard Room");
    final hostel = user.hostelName.isNotEmpty ? user.hostelName : "Vaigai Hostel";
    final roomNo = user.roomNumber.isNotEmpty ? user.roomNumber : "T-32 F02- W0-R16";
    final renewalDateStr = DateFormat('dd MMM yyyy').format(user.renewalDate);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.75) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.14) : const Color(0xFFD4AF37).withOpacity(0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Icon + Room Type + Paid Badge (Image 1)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.king_bed_outlined, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  roomType,
                  style: GoogleFonts.lato(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1A2744),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Light Green "Paid" Badge (Image 1)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Active',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Subtitle
          Row(
            children: [
              Icon(Icons.location_on_outlined, color: isDark ? Colors.white60 : Colors.grey, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$hostel · Thandalam Campus',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Room No
          Row(
            children: [
              Text(
                'Room No: ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1A2744),
                ),
              ),
              Expanded(
                child: Text(
                  roomNo,
                  style: GoogleFonts.lato(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF10B981),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Total Fee & Additional EB Charges
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Fee',
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₹${NumberFormat('#,##,###').format(user.totalFee.toInt())}',
                      style: GoogleFonts.lato(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFFDE047) : const Color(0xFF1A2744),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Additional EB Charges',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Yes',
                    style: GoogleFonts.lato(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1A2744),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Renewal Date
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Renewal Date',
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                renewalDateStr,
                style: GoogleFonts.lato(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1A2744),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Three Info Boxes: Amount, Food, Caution
          Row(
            children: [
              Expanded(child: _buildInfoBox('Amount', '₹${NumberFormat('#,##,###').format(user.roomAmount.toInt())}', isDark)),
              const SizedBox(width: 8),
              Expanded(child: _buildInfoBox('Food', '₹${NumberFormat('#,##,###').format(user.roomFood.toInt())}', isDark)),
              const SizedBox(width: 8),
              Expanded(child: _buildInfoBox('Caution', '₹${NumberFormat('#,##,###').format(user.roomCaution.toInt())}', isDark)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox(String label, String amount, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFF9F6F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount,
              style: GoogleFonts.lato(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1A2744),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // CARD 2: Requested Room Transfer Card (Displayed if student submitted a request)
  Widget _buildRequestedTransferCard(Map<String, dynamic> request) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    final status = (request['status'] ?? 'pending').toString().toLowerCase();
    String requestedRoom = (request['requested_room'] ?? '').toString();
    final requestedType = (request['requested_room_type'] ?? 'Standard').toString();
    if (requestedRoom.isEmpty || requestedRoom == '0' || requestedRoom == 'null') {
      requestedRoom = requestedType.isNotEmpty ? requestedType : 'Pending Assignment';
    }
    final currentRoom = request['current_room'] ?? 'N/A';
    final amountToPay = request['amount_to_pay'] ?? request['amount'] ?? 0;
    final remarks = request['remarks'] ?? request['rejection_reason'] ?? '';
    final reason = request['reason'] ?? '';

    Color badgeColor;
    Color badgeTextColor;
    String statusLabel;

    if (status == 'approved' || status == 'completed') {
      badgeColor = isDark ? const Color(0xFF059669).withOpacity(0.25) : const Color(0xFFDCFCE7);
      badgeTextColor = const Color(0xFF10B981);
      statusLabel = 'APPROVED';
    } else if (status == 'pre_approved') {
      badgeColor = isDark ? const Color(0xFFD97706).withOpacity(0.25) : const Color(0xFFFEF3C7);
      badgeTextColor = const Color(0xFFF59E0B);
      statusLabel = 'PRE-APPROVED';
    } else if (status == 'rejected') {
      badgeColor = isDark ? const Color(0xFFDC2626).withOpacity(0.25) : const Color(0xFFFEE2E2);
      badgeTextColor = const Color(0xFFEF4444);
      statusLabel = 'REJECTED';
    } else {
      badgeColor = isDark ? const Color(0xFFD97706).withOpacity(0.25) : const Color(0xFFFEF3C7);
      badgeTextColor = const Color(0xFFF59E0B);
      statusLabel = 'PENDING';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.75) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: badgeTextColor.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Icon(Icons.sync_outlined, color: badgeTextColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ROOM TRANSFER REQUEST',
                  style: GoogleFonts.lato(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1A2744),
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: badgeTextColor,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(color: isDark ? Colors.white12 : Colors.grey.shade200),
          const SizedBox(height: 12),

          // Transfer Movement Details
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FROM ROOM',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isDark ? Colors.white60 : Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currentRoom,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A2744)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Color(0xFF3B82F6), size: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'TARGET ROOM',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isDark ? Colors.white60 : Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      requestedRoom,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF3B82F6)),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Requested Room Category & Upgrade Fee
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Category', style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey)),
                    const SizedBox(height: 2),
                    Text(
                      requestedType,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A2744)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Upgrade Fee', style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey)),
                  const SizedBox(height: 2),
                  Text(
                    '₹$amountToPay',
                    style: GoogleFonts.lato(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF3B82F6)),
                  ),
                ],
              ),
            ],
          ),

          if (reason.toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Reason: $reason',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: isDark ? Colors.white70 : Colors.grey.shade700),
            ),
          ],

          if (remarks.toString().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: status == 'rejected'
                    ? (isDark ? Colors.red.shade900.withOpacity(0.3) : Colors.red.shade50)
                    : (isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: status == 'rejected'
                      ? (isDark ? Colors.red.shade700 : Colors.red.shade200)
                      : (isDark ? Colors.white.withOpacity(0.14) : Colors.grey.shade300),
                ),
              ),
              child: Text(
                status == 'rejected' ? 'Rejection Reason: $remarks' : 'Warden Remark: $remarks',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: status == 'rejected'
                      ? (isDark ? const Color(0xFFF87171) : Colors.red.shade800)
                      : (isDark ? Colors.white70 : Colors.grey.shade800),
                ),
              ),
            ),
          ],

          // Upgrade Fee / Confirmed Allocation Status
          if (status == 'approved' || status == 'pre_approved' || status == 'completed') ...[
            if (double.tryParse(amountToPay.toString()) != null && (double.tryParse(amountToPay.toString()) ?? 0.0) > 0 && (request['payment_status'] ?? '').toString().toLowerCase() != 'paid' && status != 'completed') ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () => _handleRoomTransferPayment(request, double.tryParse(amountToPay.toString()) ?? 0.0),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                    elevation: 2,
                    shadowColor: const Color(0xFF1D4ED8).withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Pay Now',
                    style: GoogleFonts.lato(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ] else ...[
              // Downgrade / Free room transfer / Already Completed
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF059669).withOpacity(0.2) : const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF10B981).withOpacity(0.6)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Room Transfer Approved & Allocated!',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46),
                            ),
                          ),
                          Text(
                            'You have been transferred to $requestedRoom. No additional fee required.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? Colors.white70 : const Color(0xFF047857),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ] else if (status == 'pending') ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFFD97706).withOpacity(0.18) : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_empty_rounded, color: Color(0xFFF59E0B), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pay Now option will enable after Warden approves the request.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Inline Error Notification Banner directly ON THIS CARD
          if (_showWalletErrorOnCard) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.red.shade900.withOpacity(0.3) : const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEF4444), width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '⚠️ Insufficient balance',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _showWalletErrorOnCard = false),
                    child: Icon(Icons.close, size: 18, color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleRoomTransferPayment(Map<String, dynamic> request, double fee) async {
    final user = Provider.of<UserProvider>(context, listen: false);
    final targetRoom = request['requested_room'] ?? request['target_room'] ?? 'New Room';

    // 1. Check wallet balance
    if (user.walletBalance < fee) {
      setState(() {
        _showWalletErrorOnCard = true;
      });
      TopNotification.showInsufficientBalance(
        context,
        currentBalance: user.walletBalance,
        requiredAmount: fee,
        onTopUp: () {
          final mainResponsive = context.findAncestorStateOfType<MainResponsiveLayoutState>();
          if (mainResponsive != null) {
            mainResponsive.setSelectedIndex(2);
          } else {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentWalletScreen()));
          }
        },
      );
      return;
    }

    // 2. Balance is sufficient — Show Confirmation Dialog
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF0288D1), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Confirm Room Transfer',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: isDark ? Colors.white : const Color(0xFF1B2B48),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pay ₹${NumberFormat('#,##,###').format(fee.toInt())} upgrade fee from your wallet to finalize transfer to $targetRoom?',
              style: GoogleFonts.inter(fontSize: 13, color: isDark ? Colors.white70 : Colors.grey.shade700, height: 1.35),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Wallet Balance:', style: GoogleFonts.inter(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600)),
                  Text('₹${NumberFormat('#,##,###.00').format(user.walletBalance)}', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF10B981))),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white60 : Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pay from Wallet'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // 3. Process payment
    try {
      final res = await ApiService.processPayment(
        studentId: user.dbId ?? 0,
        amount: fee,
        paymentType: 'Room Change Upgrade Fee',
        paymentMethod: 'Wallet',
        requestId: request['request_id']?.toString(),
      );

      if (res['message'] == 'Payment processed successfully' || res['status'] == 'Success' || res['success'] == true) {
        await user.refreshUserData();
        await user.fetchWalletBalance();
        if (mounted) {
          setState(() {
            _showWalletErrorOnCard = false;
          });
          TopNotification.showSuccess(
            context,
            title: 'Room Transfer Confirmed! 🎉',
            message: 'You have been successfully allocated to $targetRoom.',
          );
        }
      } else {
        if (mounted) {
          TopNotification.showError(
            context,
            title: 'Payment Failed',
            message: res['message'] ?? 'Unable to complete room transfer payment.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        TopNotification.showError(context, title: 'Error', message: 'Payment error: $e');
      }
    }
  }
}
