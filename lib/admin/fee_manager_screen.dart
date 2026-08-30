import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_service.dart';
import '../core/app_logger.dart';
import '../shared/widgets/skeuomorphic_navbar.dart';
import '../shared/wallpaper_provider.dart';
import '../core/styles.dart';

class FeeManagerScreen extends StatefulWidget {
  final int hostelId;
  final String hostelName;

  const FeeManagerScreen({
    super.key,
    required this.hostelId,
    required this.hostelName,
  });

  @override
  State<FeeManagerScreen> createState() => _FeeManagerScreenState();
}

class _FeeManagerScreenState extends State<FeeManagerScreen> {
  List<dynamic> _fees = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFees();
  }

  Future<void> _loadFees() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.getExternalFees(widget.hostelName);
      if (response['success']) {
        setState(() => _fees = response['data']);
      }
    } catch (e) {
      AppLogger.error("Load fees error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showFeeDialog({Map<String, dynamic>? fee}) {
    final bool isEdit = fee != null;
    final hostelFeeController = TextEditingController(
        text: isEdit ? (fee['hostel_fee'] ?? fee['six_month_amount'] ?? '').toString() : '');
    final foodFeeController = TextEditingController(
        text: isEdit ? (fee['food_fee'] ?? 50000).toString() : '50000');
    final roomTypeController =
        TextEditingController(text: isEdit ? fee['room_type'] : '');
    final facilityController = TextEditingController(
        text: isEdit ? fee['facility_description'] : '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? 'Edit Fee Type' : 'Add New Fee Type'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: roomTypeController,
                decoration: const InputDecoration(
                    labelText: 'Room Type (e.g. 4 IN 1 AC)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: hostelFeeController,
                decoration: const InputDecoration(
                    labelText: 'Hostel Fee / year (₹)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: foodFeeController,
                decoration: const InputDecoration(
                    labelText: 'Food Fee / year (₹)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: facilityController,
                decoration:
                    const InputDecoration(labelText: 'Facility Description'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (roomTypeController.text.isEmpty) return;

              final data = {
                if (isEdit) 'id': fee['id'],
                'room_type': roomTypeController.text,
                'hostel_fee': double.tryParse(hostelFeeController.text) ?? 0.0,
                'food_fee': double.tryParse(foodFeeController.text) ?? 50000.0,
                'monthly_amount': 2000.0,
                'facility_description': facilityController.text,
              };
              
              try {
                final res = isEdit
                    ? await ApiService.updateRenewFee(data)
                    : await ApiService.addRenewFee(data);
                
                if (!context.mounted) return;
                if (res['success']) {
                  Navigator.pop(context);
                  _loadFees();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(isEdit ? 'Fee updated' : 'Fee added')),
                  );
                }
              } catch (e) {
                AppLogger.error("Save fee error: $e");
              }
            },
            child: Text(isEdit ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }

  void _deleteFee(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Fee Type'),
        content: const Text('Are you sure you want to remove this room type?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              try {
                final res = await ApiService.deleteRenewFee(id);
                if (!context.mounted) return;
                if (res['success']) {
                  Navigator.pop(context);
                  _loadFees();
                }
              } catch (e) {
                AppLogger.error("Delete error: $e");
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _formatAmount(dynamic amount) {
    if (amount == null) return '—';
    final num = (amount is int) ? amount : (amount is double ? amount : double.tryParse(amount.toString()) ?? 0);
    if (num >= 100000) {
      return '₹${(num / 100000).toStringAsFixed(1)}L';
    } else if (num >= 1000) {
      return '₹${(num / 1000).toStringAsFixed(0)}K';
    }
    return '₹$num';
  }

  @override
  Widget build(BuildContext context) {
    WallpaperProvider? wallpaper;
    try {
      wallpaper = context.watch<WallpaperProvider>();
    } catch (_) {}
    final isDark = wallpaper?.isDarkTheme ?? false;

    return LinenGridBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: SkeuomorphicNavBar(
          title: 'Fees: ${widget.hostelName}',
          onBack: () => Navigator.pop(context),
          rightAction: IconButton(
            onPressed: _loadFees,
            icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _fees.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4AF37).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.money_off, size: 56, color: Color(0xFFD4AF37)),
                      ),
                      const SizedBox(height: 16),
                      Text('No fee structures found', 
                           style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600], fontSize: 16, fontFamily: 'Lato')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Summary header
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF131D2E).withOpacity(0.85) : const Color(0xFF2A4A8C),
                        borderRadius: BorderRadius.circular(14),
                        border: isDark ? Border.all(color: Colors.white.withOpacity(0.14)) : null,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.apartment, color: Color(0xFFD4AF37), size: 20),
                          const SizedBox(width: 10),
                          Text(
                            '${_fees.length} Room Types Available',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              fontFamily: 'Lato',
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Fee list
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                        itemCount: _fees.length,
                        itemBuilder: (context, index) => _buildFeeCard(_fees[index], index, isDark),
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  Widget _buildFeeCard(Map<String, dynamic> fee, int index, bool isDark) {
    final hostelFee = fee['hostel_fee'] ?? 0;
    final foodFee = fee['food_fee'] ?? 50000;
    final total = (hostelFee is num ? hostelFee : 0) + (foodFee is num ? foodFee : 0);
    final occupancy = fee['occupancy']?.toString() ?? '';
    final cautionDeposit = fee['caution_deposit'] ?? 0;

    final accent = isDark ? const Color(0xFF1E3A8A).withOpacity(0.9) : const Color(0xFF3D7CC9);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.75) : const Color(0xFFFAF6EE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.14) : const Color(0xFFE8E0D5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header strip
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.bed, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    fee['room_type'] ?? '—',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.white,
                      fontFamily: 'Lato',
                    ),
                  ),
                ),
                if (occupancy.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$occupancy Sharing',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),

          // Fee grid
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    _buildFeeChip(Icons.apartment, 'Hostel', _formatAmount(hostelFee), const Color(0xFF2A4A8C), isDark: isDark),
                    const SizedBox(width: 8),
                    _buildFeeChip(Icons.restaurant, 'Food', _formatAmount(foodFee), const Color(0xFF1B4D3E), isDark: isDark),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildFeeChip(Icons.calculate_rounded, 'Total / Year', _formatAmount(total), const Color(0xFFD4AF37), highlight: true, isDark: isDark),
                    if (cautionDeposit > 0) ...[
                      const SizedBox(width: 8),
                      _buildFeeChip(Icons.security, 'Caution', _formatAmount(cautionDeposit), Colors.grey.shade600, isDark: isDark),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeeChip(IconData icon, String label, String amount, Color color, {bool highlight = false, bool isDark = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? (highlight ? const Color(0xFFD4AF37).withOpacity(0.18) : Colors.white.withOpacity(0.08))
              : (highlight ? const Color(0xFFE8F0FB) : const Color(0xFFF0F4FA)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark
                ? (highlight ? const Color(0xFFD4AF37).withOpacity(0.4) : Colors.white.withOpacity(0.12))
                : const Color(0xFFD0DDED),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isDark
                  ? (highlight ? const Color(0xFFEBC15B) : Colors.white70)
                  : color,
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    color: isDark
                        ? (highlight ? const Color(0xFFEBC15B) : Colors.white70)
                        : color.withOpacity(0.8),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  amount,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Lato',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
