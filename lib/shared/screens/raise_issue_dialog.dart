import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../user_provider.dart';
import '../../core/api_service.dart';

class RaiseIssueDialog extends StatefulWidget {
  const RaiseIssueDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const RaiseIssueDialog(),
    );
  }

  @override
  State<RaiseIssueDialog> createState() => _RaiseIssueDialogState();
}

class _RaiseIssueDialogState extends State<RaiseIssueDialog> {
  final TextEditingController _descriptionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  PlatformFile? _selectedFile;
  Uint8List? _fileBytes;
  String? _fileName;
  bool _isPdf = false;
  bool _isImage = false;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final ext = (file.extension ?? '').toLowerCase();
        setState(() {
          _selectedFile = file;
          _fileBytes = file.bytes;
          _fileName = file.name;
          _isPdf = ext == 'pdf';
          _isImage = ['jpg', 'jpeg', 'png', 'webp'].contains(ext);
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not pick file: $e';
      });
    }
  }

  void _removeAttachment() {
    setState(() {
      _selectedFile = null;
      _fileBytes = null;
      _fileName = null;
      _isPdf = false;
      _isImage = false;
    });
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = Provider.of<UserProvider>(context, listen: false);

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final roleStr = user.role.name;
      final res = await ApiService.submitIssue(
        issueDescription: _descriptionController.text.trim(),
        userRole: roleStr,
        username: user.username.isNotEmpty ? user.username : user.studentId,
        userName: user.userName,
        email: user.email,
        phone: user.phone,
        hostelName: user.hostelName,
        roomNo: user.roomNumber,
        userId: user.dbId,
        attachmentBytes: _fileBytes,
        attachmentName: _fileName,
      );

      if (res['success'] == true) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              content: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Issue raised successfully! Sent to Developer.',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      } else {
        setState(() {
          _isSubmitting = false;
          _errorMessage = res['message'] ?? 'Failed to submit issue. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Network error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>();
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 32,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF131D2E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFF59E0B).withOpacity(0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
              BoxShadow(
                color: const Color(0xFFF59E0B).withOpacity(0.15),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with Help Icon
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withOpacity(0.18),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFF59E0B).withOpacity(0.5),
                              width: 1.2,
                            ),
                          ),
                          child: Image.asset(
                            'assets/images/help_icon.png',
                            width: 28,
                            height: 28,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => const Icon(
                              Icons.help_outline_rounded,
                              color: Color(0xFFFBBF24),
                              size: 28,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Help & Support',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Lato',
                                  letterSpacing: 0.3,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Direct report to Developer',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 12,
                                  fontFamily: 'Lato',
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 16),

                    // User Identity Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _getRoleIcon(user.role),
                            size: 16,
                            color: const Color(0xFFD4AF37),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Reporting as: ${user.userName.isNotEmpty ? user.userName : user.username} • (${user.role.name.toUpperCase()})',
                              style: const TextStyle(
                                color: Color(0xFFE2E8F0),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (user.hostelName.isNotEmpty)
                            Text(
                              user.hostelName,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Issue Description label
                    const Text(
                      'Explain the Issue *',
                      style: TextStyle(
                        color: Color(0xFFF1F5F9),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Message text box
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 5,
                      minLines: 3,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Please describe the problem or issue you are facing in detail...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a description of the issue.';
                        }
                        if (value.trim().length < 5) {
                          return 'Please explain the issue in a little more detail.';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 18),

                    // Attachment Section Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Attach Screenshot or Document',
                          style: TextStyle(
                            color: Color(0xFFF1F5F9),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                        Text(
                          'Images or PDF',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Attachment Picker Button or Preview
                    if (_selectedFile == null) ...[
                      InkWell(
                        onTap: _isSubmitting ? null : _pickAttachment,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFFD4AF37).withOpacity(0.35),
                              width: 1.2,
                              style: BorderStyle.solid,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD4AF37).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.attach_file_rounded,
                                  color: Color(0xFFD4AF37),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Text(
                                    'Click to Attach Screenshot / PDF',
                                    style: TextStyle(
                                      color: Color(0xFFE2E8F0),
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Supports PNG, JPG, JPEG, WEBP or PDF',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      // File Preview Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            // Thumbnail / Icon
                            if (_isImage && _fileBytes != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  _fileBytes!,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                ),
                              )
                            else
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.picture_as_pdf_rounded,
                                  color: Color(0xFFF87171),
                                  size: 26,
                                ),
                              ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _fileName ?? 'Attachment',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${_isPdf ? 'PDF Document' : 'Image File'} • ${_formatFileSize(_fileBytes?.length ?? 0)}',
                                    style: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 22),
                              tooltip: 'Remove',
                              onPressed: _isSubmitting ? null : _removeAttachment,
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Color(0xFFF87171), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Color(0xFFF87171), fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white60,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _isSubmitting ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 4,
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.send_rounded, size: 16),
                                    SizedBox(width: 8),
                                    Text(
                                      'Submit Issue',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getRoleIcon(UserRole role) {
    switch (role) {
      case UserRole.student:
        return Icons.school_rounded;
      case UserRole.warden:
        return Icons.shield_rounded;
      case UserRole.admin:
        return Icons.admin_panel_settings_rounded;
      case UserRole.security:
        return Icons.security_rounded;
      case UserRole.maintenance:
        return Icons.build_rounded;
      case UserRole.it:
        return Icons.devices_other_rounded;
      default:
        return Icons.person_rounded;
    }
  }
}
