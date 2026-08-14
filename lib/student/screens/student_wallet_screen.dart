import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';

class StudentWalletScreen extends StatefulWidget {
  const StudentWalletScreen({super.key});

  @override
  State<StudentWalletScreen> createState() => _StudentWalletScreenState();
}

class _StudentWalletScreenState extends State<StudentWalletScreen> {
  bool _isGridView = true; // Toggle between Grid View (Image 1) and Table View (Image 2)
  bool _showWalletError = false;

  final List<Map<String, dynamic>> _feeItems = [
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
    {
      'title': 'Hostel Room Transfer Upgrade',
      'cycle': '-',
      'dueDate': '10 Aug 2026',
      'totalFee': '₹35,000',
      'scholarship': 'N/A',
      'totalPayable': '₹35,000',
      'status': 'Pending',
      'isPaid': false,
      'amountNum': 35000,
    },
  ];

  void _handlePayAction(Map<String, dynamic> item) {
    if (item['isPaid'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This fee has already been paid.'),
          backgroundColor: Color(0xFF059669),
        ),
      );
      return;
    }
    _showAddFundsDialog(defaultAmount: (item['amountNum'] ?? 35000).toDouble());
  }

  void _showAddFundsDialog({double defaultAmount = 70000}) {
    final controller = TextEditingController(text: defaultAmount.toInt().toString());

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

                          // Inline Error when clicking Deposit
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
    return Scaffold(
      backgroundColor: const Color(0xFF141414), // Dark Theme from Image 1 & 2
      appBar: const SkeuomorphicNavBar(
        title: 'Wallet & Fees',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Wallet & View Toggle Bar (Image 1 & 2 Header)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Blue Wallet Pill Card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
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
                ),

                // View Toggle Button (Grid View vs Table View)
                InkWell(
                  onTap: () {
                    setState(() {
                      _isGridView = !_isGridView;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF222222),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade800),
                    ),
                    child: Icon(
                      _isGridView ? Icons.table_rows_outlined : Icons.grid_view_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),

            if (_showWalletError) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF7F1D1D).withOpacity(0.8),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEF4444)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'The wallet is not added yet.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _showWalletError = false),
                      child: const Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // DUAL CARD VIEWS:
            // 1. Grid View Cards (Image 1)
            // 2. Table View (Image 2)
            _isGridView ? _buildGridViewCards() : _buildTableView(),
          ],
        ),
      ),
    );
  }

  // 1. GRID VIEW CARDS (Image 1)
  Widget _buildGridViewCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 768;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: _feeItems.map((item) {
            final double cardWidth = isDesktop ? (constraints.maxWidth - 16) / 2 : constraints.maxWidth;
            return SizedBox(
              width: cardWidth,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade800),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: Fee Title & Status Badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['title'],
                            style: GoogleFonts.lato(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: item['isPaid'] ? const Color(0xFF065F46) : const Color(0xFF78350F),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: item['isPaid'] ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                item['isPaid'] ? Icons.check_circle_outline : Icons.hourglass_top_rounded,
                                color: item['isPaid'] ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                item['status'],
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: item['isPaid'] ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Cycle & Due Date
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Cycle', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            const SizedBox(height: 2),
                            Text(item['cycle'], style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Due Date', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            const SizedBox(height: 2),
                            Text(item['dueDate'], style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Three Info Boxes: Total Fee, Scholarship Amount, Total Payable
                    Row(
                      children: [
                        Expanded(child: _buildGridInfoBox('Total Fee', item['totalFee'])),
                        const SizedBox(width: 8),
                        Expanded(child: _buildGridInfoBox('Scholarship Amount', item['scholarship'])),
                        const SizedBox(width: 8),
                        Expanded(child: _buildGridInfoBox('Total Payable', item['totalPayable'])),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Bottom Right Action Button
                    Align(
                      alignment: Alignment.centerRight,
                      child: InkWell(
                        onTap: () => _handlePayAction(item),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: item['isPaid'] ? const Color(0xFF2A2A2A) : const Color(0xFF3B82F6),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: item['isPaid'] ? Colors.grey.shade800 : const Color(0xFF60A5FA)),
                          ),
                          child: Text(
                            item['isPaid'] ? 'Paid' : 'Pay Now',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: item['isPaid'] ? Colors.white70 : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildGridInfoBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF262626),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.lato(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }

  // 2. TABLE VIEW (Image 2)
  Widget _buildTableView() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 50,
          dataRowHeight: 65,
          horizontalMargin: 20,
          columnSpacing: 25,
          headingRowColor: WidgetStateProperty.all(const Color(0xFF262626)),
          columns: const [
            DataColumn(label: Text('Cycle', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Fee Name', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Total Fee', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Scholarship Amount', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Total Payable', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Due Date', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Status', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Action', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
          ],
          rows: _feeItems.map((item) {
            return DataRow(
              cells: [
                DataCell(Text(item['cycle'], style: const TextStyle(color: Colors.white))),
                DataCell(Text(item['title'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                DataCell(Text(item['totalFee'], style: const TextStyle(color: Colors.white))),
                DataCell(Text(item['scholarship'], style: const TextStyle(color: Colors.white))),
                DataCell(Text(item['totalPayable'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                DataCell(Text(item['dueDate'], style: const TextStyle(color: Colors.white))),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: item['isPaid'] ? const Color(0xFF065F46) : const Color(0xFF78350F),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: item['isPaid'] ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item['isPaid'] ? Icons.check_circle_outline : Icons.hourglass_top_rounded,
                          color: item['isPaid'] ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item['status'],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: item['isPaid'] ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                DataCell(
                  InkWell(
                    onTap: () => _handlePayAction(item),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: item['isPaid'] ? const Color(0xFF2A2A2A) : const Color(0xFF3B82F6),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: item['isPaid'] ? Colors.grey.shade800 : const Color(0xFF60A5FA)),
                      ),
                      child: Text(
                        item['isPaid'] ? 'Paid' : 'Pay Now',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: item['isPaid'] ? Colors.white70 : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
