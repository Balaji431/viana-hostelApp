import 'package:flutter/material.dart';
import '../core/api_service.dart';
import '../core/app_logger.dart';
import '../shared/widgets/skeuomorphic_navbar.dart';
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
      final response = await ApiService.getRenewFees(hostelId: widget.hostelId);
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

  @override
  Widget build(BuildContext context) {
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
                      Icon(Icons.money_off, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('No fee structures found', 
                           style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _showFeeDialog(),
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text('Add First Fee Type', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD4AF37),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          elevation: 4,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _fees.length,
                  itemBuilder: (context, index) {
                    final fee = _fees[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: SkeuomorphicStyles.skeuomorphicCard,
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(fee['room_type'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1A2744), fontFamily: 'Lato')),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.hotel, size: 14, color: Colors.blueAccent),
                                const SizedBox(width: 4),
                                Text('Hostel: ₹${fee['hostel_fee'] ?? fee['six_month_amount'] ?? '-'}',
                                    style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            Row(
                              children: [
                                const Icon(Icons.restaurant, size: 14, color: Colors.orange),
                                const SizedBox(width: 4),
                                Text('Food: ₹${fee['food_fee'] ?? 50000}',
                                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            Row(
                              children: [
                                const Icon(Icons.calculate, size: 14, color: Colors.green),
                                const SizedBox(width: 4),
                                Text('Total: ₹${fee['total_fee'] ?? ((fee['hostel_fee'] ?? 0) + (fee['food_fee'] ?? 50000))}',
                                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(fee['facility_description'] ?? '',
                                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showFeeDialog(fee: fee)),
                            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _deleteFee(fee['id'])),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showFeeDialog(),
          backgroundColor: const Color(0xFFD4AF37),
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }
}
