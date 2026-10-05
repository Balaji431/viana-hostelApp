import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api_service.dart';

class GenerateEBBillDialog extends StatefulWidget {
  final Map<String, dynamic> reading;
  final String adminUsername;
  final VoidCallback onBillGenerated;

  const GenerateEBBillDialog({
    super.key,
    required this.reading,
    required this.adminUsername,
    required this.onBillGenerated,
  });

  @override
  State<GenerateEBBillDialog> createState() => _GenerateEBBillDialogState();
}

class _GenerateEBBillDialogState extends State<GenerateEBBillDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _rateController = TextEditingController(text: '8.50');
  final TextEditingController _penaltyController = TextEditingController(text: '0.00');
  final TextEditingController _cycleController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  bool _isLoadingOccupants = true;
  bool _isSubmitting = false;
  List<dynamic> _occupants = [];

  @override
  void initState() {
    super.initState();
    _cycleController.text = DateFormat('MMMM yyyy').format(DateTime.now());
    final watts = double.tryParse(widget.reading['watts']?.toString() ?? '0') ?? 0.0;
    if (watts >= 1500) {
      // Suggest a penalty if high wattage/heater detected
      _penaltyController.text = '250.00';
    }
    _loadOccupants();
  }

  @override
  void dispose() {
    _rateController.dispose();
    _penaltyController.dispose();
    _cycleController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadOccupants() async {
    final roomNo = widget.reading['room_no']?.toString() ?? '';
    final hostelName = widget.reading['hostel_name']?.toString() ?? '';

    try {
      final res = await ApiService.getRoomMeterInfo(roomNo: roomNo, hostelName: hostelName);
      if (mounted && res['status'] == 'success') {
        setState(() {
          _occupants = res['data']['occupants'] ?? [];
          _isLoadingOccupants = false;
        });
        return;
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoadingOccupants = false);
  }

  double get _unitsConsumed {
    return double.tryParse(widget.reading['units_consumed']?.toString() ?? '0') ?? 0.0;
  }

  double get _ratePerUnit {
    return double.tryParse(_rateController.text.trim()) ?? 0.0;
  }

  double get _penaltyAmount {
    return double.tryParse(_penaltyController.text.trim()) ?? 0.0;
  }

  double get _baseAmount {
    return _unitsConsumed * _ratePerUnit;
  }

  double get _totalAmount {
    return _baseAmount + _penaltyAmount;
  }

  double get _perStudentAmount {
    final count = _occupants.isEmpty ? 1 : _occupants.length;
    return _totalAmount / count;
  }

  Future<void> _submitBill() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final payload = {
      'reading_id': widget.reading['id'],
      'rate_per_unit': _ratePerUnit,
      'penalty_amount': _penaltyAmount,
      'billing_cycle': _cycleController.text.trim(),
      'admin_username': widget.adminUsername,
      'admin_remarks': _remarksController.text.trim(),
      'students': _occupants.map((o) => {
        'student_username': o['reg_no'] ?? '',
        'student_name': o['full_name'] ?? '',
        'amount': double.parse(_perStudentAmount.toStringAsFixed(2)),
      }).toList(),
    };

    final res = await ApiService.generateEBBill(payload);

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (res['status'] == 'success') {
        Navigator.pop(context);
        widget.onBillGenerated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('EB Bill issued successfully!'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Failed to issue bill'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final roomNo = widget.reading['room_no'] ?? '-';
    final hostelName = widget.reading['hostel_name'] ?? '-';
    final watts = double.tryParse(widget.reading['watts']?.toString() ?? '0') ?? 0.0;
    final isHighLoad = watts >= 1500;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF131D2E) : Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFC5A358).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.receipt_long, color: Color(0xFFC5A358), size: 24),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Generate EB Bill',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF1B2B48),
                              ),
                            ),
                            Text(
                              'Room $roomNo ($hostelName)',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Inspection Summary Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFFBF9F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFC5A358).withOpacity(0.25)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryMetric('Units Consumed', '${_unitsConsumed.toStringAsFixed(1)} kWh', const Color(0xFFC5A358)),
                      _buildSummaryMetric('Measured Load', '${watts.toStringAsFixed(0)} W', isHighLoad ? Colors.redAccent : Colors.teal),
                      _buildSummaryMetric('Inspector', widget.reading['inspector_name'] ?? 'Staff', Colors.blueAccent),
                    ],
                  ),
                ),

                if (isHighLoad) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning, color: Colors.redAccent, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Notice: Room logged high active load (>= 1500W). Heavy appliance penalty suggested.',
                            style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Billing Inputs
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _rateController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                        decoration: _inputDecoration('Rate per Unit (₹)', '8.50', isDark),
                        onChanged: (_) => setState(() {}),
                        validator: (v) => (v == null || double.tryParse(v.trim()) == null) ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _penaltyController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                        decoration: _inputDecoration('Penalty / Fine (₹)', '0.00', isDark),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cycleController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: _inputDecoration('Billing Cycle / Month', 'e.g. September 2026', isDark),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _remarksController,
                  maxLines: 2,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: _inputDecoration('Admin Remarks (Optional)', 'Notes for room occupants...', isDark),
                ),

                const SizedBox(height: 16),

                // Occupants & Split Preview
                Text(
                  'Room Occupants & Bill Split (${_occupants.length} students):',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? Colors.white70 : const Color(0xFF1B2B48),
                  ),
                ),
                const SizedBox(height: 8),
                _isLoadingOccupants
                    ? const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
                    : _occupants.isEmpty
                        ? Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('No students currently mapped. The bill will be charged to the room inventory directly.', style: TextStyle(fontSize: 11)),
                          )
                        : Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0B132B).withOpacity(0.5) : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                            ),
                            child: Column(
                              children: _occupants.map((stu) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${stu['full_name'] ?? 'Student'} (${stu['reg_no'] ?? '-'})',
                                        style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87),
                                      ),
                                      Text(
                                        '₹${_perStudentAmount.toStringAsFixed(2)}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFC5A358)),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                const SizedBox(height: 16),

                // Calculation Summary Box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC5A358).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFC5A358)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Base Energy Charge:', style: TextStyle(fontSize: 13)),
                          Text('₹${_baseAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      if (_penaltyAmount > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Excess Load / Anomaly Penalty:', style: TextStyle(fontSize: 13, color: Colors.redAccent)),
                            Text('+ ₹${_penaltyAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.redAccent)),
                          ],
                        ),
                      ],
                      const Divider(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Room Bill:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          Text(
                            '₹${_totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFC5A358)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC5A358),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isSubmitting ? null : _submitBill,
                      icon: _isSubmitting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.check_circle, size: 18),
                      label: Text(_isSubmitting ? 'Issuing...' : 'Approve & Issue Bill'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryMetric(String title, String val, Color color) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 2),
        Text(val, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  InputDecoration _inputDecoration(String label, String hint, bool isDark) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13),
      hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38, fontSize: 13),
      filled: true,
      fillColor: isDark ? const Color(0xFF0F172A).withOpacity(0.5) : const Color(0xFFFBF9F5),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFC5A358), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}
