import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/api_service.dart';
import '../../shared/user_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';

class NoDuePage extends StatefulWidget {
  const NoDuePage({super.key});

  @override
  State<NoDuePage> createState() => _NoDuePageState();
}

class _NoDuePageState extends State<NoDuePage> {
  bool _isLoading = true;
  bool _showWalletErrorOnCard = false;
  bool _isWalletGridView = true; // Toggle between Grid View and Table View for Wallet
  List<Map<String, dynamic>> _requests = [];

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
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = context.read<UserProvider>();
      if (user.dbId != null) {
        final res = await ApiService.getRoomChangeRequests(
          status: 'all',
          studentId: user.dbId,
        );
        if (res['status'] == 'success' && res['data'] != null) {
          final list = (res['data'] as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          setState(() {
            _requests = list;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading no due status: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddFundsDialog({double defaultAmount = 0}) {
    final controller = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (context) {
        bool showDepositError = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            final int amtVal = int.tryParse(controller.text) ?? 0;
            final String inWords = _convertAmountToWords(amtVal);

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header Bar (Matching Add Funds Screenshot)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF5A758D), Color(0xFF4A6278)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Spacer(),
                          Text(
                            'Add Funds',
                            style: GoogleFonts.lato(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 18),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Dialog Content
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // CURRENT BALANCE Box
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'CURRENT BALANCE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF64748B),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '₹0',
                                  style: GoogleFonts.lato(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Amount (₹) Field Label
                          const Text(
                            'Amount (₹)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Textfield with number stepper arrows
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF3B82F6), width: 1.5),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: controller,
                                    keyboardType: TextInputType.number,
                                    style: GoogleFonts.lato(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF1E293B),
                                    ),
                                    decoration: const InputDecoration(
                                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      border: InputBorder.none,
                                    ),
                                    onChanged: (val) {
                                      setModalState(() {});
                                    },
                                  ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        int cur = (int.tryParse(controller.text) ?? 0) + 1000;
                                        controller.text = cur.toString();
                                        setModalState(() {});
                                      },
                                      child: const Icon(Icons.arrow_drop_up, size: 20, color: Colors.grey),
                                    ),
                                    InkWell(
                                      onTap: () {
                                        int cur = (int.tryParse(controller.text) ?? 0) - 1000;
                                        if (cur < 0) cur = 0;
                                        controller.text = cur.toString();
                                        setModalState(() {});
                                      },
                                      child: const Icon(Icons.arrow_drop_down, size: 20, color: Colors.grey),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 8),
                              ],
                            ),
                          ),

                          const SizedBox(height: 6),

                          Text(
                            inWords,
                            style: const TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFF475569),
                            ),
                          ),

                          const SizedBox(height: 12),

                          Align(
                            alignment: Alignment.centerRight,
                            child: InkWell(
                              onTap: () => _showTermsAndConditionsDialog(context),
                              child: Text(
                                'View Terms & Conditions',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade600,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),

                          // Inline Error Notification Triggered on Deposit Click
                          if (showDepositError) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFEF4444)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 18),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'The wallet is not added yet.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF991B1B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 20),

                          // Action Buttons: Cancel and Deposit
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    setModalState(() {
                                      showDepositError = true;
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF3B82F6),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: const Text(
                                    'Deposit',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
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
          },
        );
      },
    );
  }

  String _convertAmountToWords(int amount) {
    if (amount <= 0) return '';

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

    return '${convert(amount)} rupees only';
  }

  void _showTermsAndConditionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF5A758D), Color(0xFF4A6278)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.gavel_outlined, color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'Terms & Conditions',
                        style: GoogleFonts.lato(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),

                // Content List
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.sync_alt_rounded, color: Color(0xFF2563EB), size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Shared Unified Wallet for VStudy & VStay Portals',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E40AF),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        _buildTermItem(
                          '1. Unified Multi-Portal Balance',
                          'Your wallet balance is unified and shared synchronously between VStudy (Academic Portal) and VStay (Hostel Management). Any funds added or deducted in one portal immediately reflect in both portals.',
                        ),
                        _buildTermItem(
                          '2. Cross-Portal Fee Payments',
                          'Wallet funds can be used for room upgrade fees, maintenance dues, academic tuition fees, exam fees, and campus event registrations seamlessly across VStudy and VStay.',
                        ),
                        _buildTermItem(
                          '3. Account Bound & Non-Transferable',
                          'The wallet is strictly tied to your student Registration ID. Wallet balances cannot be transferred to other students or withdrawn as cash unless authorized during official institution clearance.',
                        ),
                        _buildTermItem(
                          '4. Centralized Transaction Audit',
                          'All deposits, hostel fee payments, and academic fee transactions made via VStudy or VStay are logged in a single centralized transaction history accessible anytime.',
                        ),
                        _buildTermItem(
                          '5. Refunds & No Due Clearance Policy',
                          'Unutilized wallet balances at program completion or hostel checkout will be refunded according to institution financial policies upon successful No Due clearance verification.',
                        ),

                        const SizedBox(height: 16),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'I Understand & Accept',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTermItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            description,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>();
    final latestRequest = _requests.isNotEmpty ? _requests.first : <String, dynamic>{};

    return Scaffold(
      backgroundColor: const Color(0xFFE8E4DB),
      appBar: const SkeuomorphicNavBar(
        title: 'No Due',
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // WALLET SECTION (Temporarily hidden for production release)
              // _buildWalletSection(),

              const SizedBox(height: 20),

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
            ],
          ),
        ),
      ),
    );
  }

  // WALLET SECTION COMPONENT
  Widget _buildWalletSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF3B82F6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Text(
            'WALLET',
            style: GoogleFonts.lato(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '₹0.00',
            style: GoogleFonts.lato(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          // History Icon
          InkWell(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No transaction history found.')),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.history, color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 8),
          // + Add Button -> Opens Add Funds Dialog
          InkWell(
            onTap: () => _showAddFundsDialog(defaultAmount: 70000),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.4)),
              ),
              child: const Text(
                '+ Add',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // CARD 1: Existing Room Allotted Card (Image 1 Layout with Paid light green badge)
  Widget _buildExistingRoomCard(UserProvider user) {
    final roomType = user.roomType.isNotEmpty ? user.roomType : (user.roomTypeDisplay.isNotEmpty ? user.roomTypeDisplay : "Standard Room");
    final hostel = user.hostelName.isNotEmpty ? user.hostelName : "Vaigai Hostel";
    final roomNo = user.roomNumber.isNotEmpty ? user.roomNumber : "T-32 F02- W0-R16";
    final renewalDateStr = DateFormat('dd MMM yyyy').format(user.renewalDate);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
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
            children: [
              const Icon(Icons.king_bed_outlined, color: Color(0xFF1A2744), size: 22),
              const SizedBox(width: 8),
              Text(
                roomType,
                style: GoogleFonts.lato(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A2744),
                ),
              ),
              const Spacer(),
              // Light Green "Paid" Badge (Image 1)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
              const Icon(Icons.location_on_outlined, color: Colors.grey, size: 16),
              const SizedBox(width: 4),
              Text(
                '$hostel · Thandalam Campus',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Room No
          Row(
            children: [
              const Text(
                'Room No: ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A2744),
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

          const SizedBox(height: 16),

          // Total Fee & Additional EB Charges
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Fee',
                    style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '₹${NumberFormat('#,##,###').format(user.totalFee.toInt())}',
                    style: GoogleFonts.lato(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1A2744),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Additional EB Charges',
                    style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Yes',
                    style: GoogleFonts.lato(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1A2744),
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
              const Text(
                'Renewal Date',
                style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                renewalDateStr,
                style: GoogleFonts.lato(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A2744),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Three White Info Boxes: Amount, Food, Caution
          Row(
            children: [
              Expanded(child: _buildInfoBox('Amount', '₹${NumberFormat('#,##,###').format(user.roomAmount.toInt())}')),
              const SizedBox(width: 10),
              Expanded(child: _buildInfoBox('Food', '₹${NumberFormat('#,##,###').format(user.roomFood.toInt())}')),
              const SizedBox(width: 10),
              Expanded(child: _buildInfoBox('Caution', '₹${NumberFormat('#,##,###').format(user.roomCaution.toInt())}')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox(String label, String amount) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            amount,
            style: GoogleFonts.lato(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1A2744),
            ),
          ),
        ],
      ),
    );
  }

  // CARD 2: Requested Room Transfer Card (Displayed if student submitted a request)
  Widget _buildRequestedTransferCard(Map<String, dynamic> request) {
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
      badgeColor = const Color(0xFFDCFCE7);
      badgeTextColor = const Color(0xFF059669);
      statusLabel = 'APPROVED';
    } else if (status == 'pre_approved') {
      badgeColor = const Color(0xFFFEF3C7);
      badgeTextColor = const Color(0xFFD97706);
      statusLabel = 'PRE-APPROVED';
    } else if (status == 'rejected') {
      badgeColor = const Color(0xFFFEE2E2);
      badgeTextColor = const Color(0xFFDC2626);
      statusLabel = 'REJECTED';
    } else {
      badgeColor = const Color(0xFFFEF3C7);
      badgeTextColor = const Color(0xFFD97706);
      statusLabel = 'PENDING';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: badgeTextColor.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
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
                    color: const Color(0xFF1A2744),
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
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: 12),

          // Transfer Movement Details
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FROM ROOM',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currentRoom,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1A2744)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Color(0xFF3B82F6), size: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'TARGET ROOM',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
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
                    const Text('Category', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 2),
                    Text(
                      requestedType,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1A2744)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Upgrade Fee', style: TextStyle(fontSize: 11, color: Colors.grey)),
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
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey.shade700),
            ),
          ],

          if (remarks.toString().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: status == 'rejected' ? Colors.red.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: status == 'rejected' ? Colors.red.shade200 : Colors.grey.shade300),
              ),
              child: Text(
                status == 'rejected' ? 'Rejection Reason: $remarks' : 'Warden Remark: $remarks',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: status == 'rejected' ? Colors.red.shade800 : Colors.grey.shade800,
                ),
              ),
            ),
          ],

          // Pay Now button for Upgrade Fee on right side (thick vibrant blue, exact screenshot design)
          if (status == 'approved' || status == 'pre_approved') ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _showWalletErrorOnCard = true;
                  });
                },
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
          ] else if (status == 'pending') ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.5)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.hourglass_empty_rounded, color: Color(0xFFD97706), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pay Now option will enable after Warden approves the request.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB45309),
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
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEF4444), width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '⚠️ Insufficient balance',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF991B1B),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _showWalletErrorOnCard = false),
                    child: const Icon(Icons.close, size: 18, color: Color(0xFF991B1B)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
