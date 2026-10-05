import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/api_service.dart';
import '../../shared/user_provider.dart';

class StudentVacateModal extends StatefulWidget {
  final UserProvider user;
  final VoidCallback? onSubmitted;

  const StudentVacateModal({
    super.key,
    required this.user,
    this.onSubmitted,
  });

  static Future<void> show(BuildContext context, UserProvider user, {VoidCallback? onSubmitted}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StudentVacateModal(user: user, onSubmitted: onSubmitted),
    );
  }

  @override
  State<StudentVacateModal> createState() => _StudentVacateModalState();
}

class _StudentVacateModalState extends State<StudentVacateModal> {
  DateTime _expectedVacateDate = DateTime.now();
  String _selectedReason = 'Course / Internship Completed';
  final TextEditingController _detailsController = TextEditingController();
  bool _acknowledgedChecklist = false;
  bool _isSubmitting = false;

  final List<String> _reasons = [
    'Course / Internship Completed',
    'Semester Completed',
    'Shifting to Day Scholar',
    'Medical / Personal Reasons',
    'Other',
  ];

  DateTime _calculateMaxVacateDate() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final userRenewal = widget.user.renewalDate;
    if (userRenewal == null) {
      return today.add(const Duration(days: 30));
    }
    final renewalDay = DateTime(userRenewal.year, userRenewal.month, userRenewal.day);

    // 1 day before renewal date (as requested: if renewal is 07 Aug 2027, max date is 06 Aug 2027)
    final oneDayBeforeRenewal = renewalDay.subtract(const Duration(days: 1));
    if (oneDayBeforeRenewal.isBefore(today)) {
      // If renewal date has already passed or is today, allow up to 30 days ahead
      return today.add(const Duration(days: 30));
    }
    return oneDayBeforeRenewal;
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final maxDate = _calculateMaxVacateDate();
    _expectedVacateDate = today.isAfter(maxDate) ? maxDate : today;
  }

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _pickVacateDate(bool isDark) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final maxDate = _calculateMaxVacateDate();

    // Ensure initialDate is clamped within [today, maxDate]
    DateTime initial = _expectedVacateDate;
    if (initial.isBefore(today)) {
      initial = today;
    } else if (initial.isAfter(maxDate)) {
      initial = maxDate;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: maxDate,
      helpText: 'SELECT EXPECTED VACATE DATE',
      builder: (context, child) {
        return Theme(
          data: isDark ? ThemeData.dark() : ThemeData.light(),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _expectedVacateDate = picked);
    }
  }

  Future<void> _submitRequest() async {
    if (!_acknowledgedChecklist) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please acknowledge the room inspection and handover checklist.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final maxDate = _calculateMaxVacateDate();
    final vacateDay = DateTime(_expectedVacateDate.year, _expectedVacateDate.month, _expectedVacateDate.day);
    if (vacateDay.isAfter(maxDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Expected vacate date cannot be after ${DateFormat('dd MMM yyyy').format(maxDate)} (before renewal date).'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final reasonFull = _selectedReason == 'Other' || _detailsController.text.trim().isNotEmpty
        ? '$_selectedReason: ${_detailsController.text.trim()}'
        : _selectedReason;

    setState(() => _isSubmitting = true);

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_expectedVacateDate);
      final res = await ApiService.submitVacateRequest(
        studentId: widget.user.dbId ?? 0,
        regNo: widget.user.username,
        expectedVacateDate: dateStr,
        reason: reasonFull,
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      if (res['success'] == true) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Vacate request submitted successfully!'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 4),
          ),
        );
        widget.onSubmitted?.call();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Failed to submit request.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = widget.user;

    final DateTime? renewalDate = user.renewalDate;
    final DateTime maxVacateDate = _calculateMaxVacateDate();
    final daysRemainingAtVacate = renewalDate != null
        ? renewalDate.difference(_expectedVacateDate).inDays
        : 0;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle Bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.exit_to_app_rounded, color: Color(0xFFEF4444), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vacate Room Request',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Submit clearance request to your Hostel Warden',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: isDark ? Colors.white60 : Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Room & Tenure Summary Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildInfoItem(
                        'Current Room',
                        user.roomNumber.isNotEmpty ? user.roomNumber : 'Allocated',
                        Icons.meeting_room_outlined,
                        isDark,
                      ),
                      _buildInfoItem(
                        'Hostel',
                        user.hostelName.isNotEmpty ? user.hostelName : 'Hostel',
                        Icons.apartment_rounded,
                        isDark,
                      ),
                    ],
                  ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildInfoItem(
                          'Paid Tenure Expiry',
                          renewalDate != null ? DateFormat('dd MMM yyyy').format(renewalDate) : 'N/A',
                          Icons.event_available_outlined,
                          isDark,
                        ),
                        _buildInfoItem(
                          'Early Vacate Diff',
                          renewalDate != null
                              ? (daysRemainingAtVacate > 0 ? '$daysRemainingAtVacate days early' : 'Standard vacate')
                              : 'N/A',
                          Icons.timelapse_rounded,
                          isDark,
                          valueColor: daysRemainingAtVacate > 0 ? const Color(0xFFF59E0B) : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // Expected Vacate Date Picker
            Text(
              'Expected Vacate Date *',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : const Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () => _pickVacateDate(isDark),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, color: Color(0xFF2563EB), size: 18),
                    const SizedBox(width: 10),
                    Text(
                      DateFormat('EEEE, dd MMMM yyyy').format(_expectedVacateDate),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Change',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 13,
                  color: isDark ? Colors.white54 : const Color(0xFF64748B),
                ),
                const SizedBox(width: 5),
                Text(
                  'Selectable up to 1 day before renewal (${DateFormat('dd MMM yyyy').format(maxVacateDate)})',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Reason Dropdown
            Text(
              'Reason for Vacating *',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : const Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedReason,
                  isExpanded: true,
                  dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                  items: _reasons.map((r) {
                    return DropdownMenuItem(
                      value: r,
                      child: Text(
                        r,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedReason = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Additional details
            TextField(
              controller: _detailsController,
              maxLines: 2,
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                filled: true,
                fillColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                hintText: 'Additional remarks / details (optional)...',
                hintStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2563EB)),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Handover Checklist Checkbox
            InkWell(
              onTap: () => setState(() => _acknowledgedChecklist = !_acknowledgedChecklist),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _acknowledgedChecklist,
                        activeColor: const Color(0xFF10B981),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (val) => setState(() => _acknowledgedChecklist = val ?? false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'I understand that upon Warden approval, my room will be inspected, keys must be handed over, and the bed will be freed for new allocations.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : const Color(0xFF475569),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade400,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.send_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Submit Vacate Request',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
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
  }

  Widget _buildInfoItem(String label, String value, IconData icon, bool isDark, {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: valueColor ?? (isDark ? Colors.white : const Color(0xFF0F172A)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
