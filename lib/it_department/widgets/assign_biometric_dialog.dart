import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';

class AssignBiometricDialog extends StatefulWidget {
  final String registerNo;
  final String fullName;
  final String hostelName;
  final String roomAllocation;
  final String currentBiometricId;
  final VoidCallback? onAssigned;

  const AssignBiometricDialog({
    super.key,
    required this.registerNo,
    required this.fullName,
    required this.hostelName,
    required this.roomAllocation,
    this.currentBiometricId = '',
    this.onAssigned,
  });

  @override
  State<AssignBiometricDialog> createState() => _AssignBiometricDialogState();
}

class _AssignBiometricDialogState extends State<AssignBiometricDialog> {
  late TextEditingController _bioIdController;
  late TextEditingController _notesController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _bioIdController = TextEditingController(
      text: widget.currentBiometricId.isNotEmpty
          ? widget.currentBiometricId
          : widget.registerNo,
    );
    _notesController = TextEditingController(
      text: 'Biometric punch profile assigned by IT Department.',
    );
  }

  @override
  void dispose() {
    _bioIdController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submitAssignment() async {
    final bioId = _bioIdController.text.trim();
    if (bioId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFD4AF37),
          content: Text(
            'Please sync the fingerprint or enter a valid biometric machine ID first.',
            style: TextStyle(color: Color(0xFF1B2B48), fontWeight: FontWeight.bold),
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = Provider.of<UserProvider>(context, listen: false);
      final res = await ApiService.assignBiometricTicket(
        registerNo: widget.registerNo,
        biometricId: bioId,
        notes: _notesController.text.trim(),
        createdBy: user.userName.isNotEmpty ? user.userName : 'IT Staff',
      );

      if (mounted) {
        setState(() => _isLoading = false);
        if (res['success'] == true) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 4),
              content: Text(
                res['message'] ?? 'Biometric Profile Activated for ${widget.fullName}! Notification sent to student.',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          );
          widget.onAssigned?.call();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFDC2626),
              duration: const Duration(seconds: 6),
              content: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      res['message'] ?? 'No records found. Please enroll the student fingerprint on the machine first.',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFD4AF37),
            content: Text(
              'Failed to assign: $e',
              style: const TextStyle(color: Color(0xFF1B2B48), fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<WallpaperProvider>().isDarkTheme;
    final bgColor = isDark ? const Color(0xFF131D2E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1B2B48);
    final mutedColor = isDark ? Colors.white60 : Colors.grey.shade600;
    final cardBorder = isDark ? Colors.white12 : Colors.grey.shade200;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: bgColor,
      child: Container(
        padding: const EdgeInsets.all(22),
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4AF37).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fingerprint_rounded,
                    color: Color(0xFFD4AF37),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assign Biometric ID',
                        style: TextStyle(
                          fontFamily: 'Lato',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      Text(
                        widget.fullName,
                        style: TextStyle(
                          fontSize: 13,
                          color: mutedColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: mutedColor, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Register No', style: TextStyle(fontSize: 11, color: mutedColor)),
                        Text(
                          widget.registerNo,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hostel / Room', style: TextStyle(fontSize: 11, color: mutedColor)),
                        Text(
                          '${widget.hostelName} • ${widget.roomAllocation}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Biometric Machine ID',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _bioIdController,
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Enter machine punch ID',
                hintStyle: TextStyle(color: mutedColor, fontSize: 13),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
                prefixIcon: const Icon(Icons.badge_outlined, size: 18, color: Color(0xFFD4AF37)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFD4AF37)),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Notes & Instructions',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _notesController,
              maxLines: 2,
              style: TextStyle(color: textColor, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Instructions for student / warden...',
                hintStyle: TextStyle(color: mutedColor, fontSize: 12),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFD4AF37)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                  child: Text('Cancel', style: TextStyle(color: mutedColor)),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submitAssignment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.check_circle_outline, size: 16),
                            SizedBox(width: 6),
                            Text('Assign & Notify', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
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
