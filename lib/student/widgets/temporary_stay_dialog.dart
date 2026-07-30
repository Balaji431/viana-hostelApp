import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/api_service.dart';
import '../../core/notification_service.dart';

class TemporaryStayDialog extends StatefulWidget {
  final String googleEmail;
  final String googleName;
  final Map<String, dynamic>? existingRequest;

  const TemporaryStayDialog({
    super.key,
    required this.googleEmail,
    required this.googleName,
    this.existingRequest,
  });

  @override
  State<TemporaryStayDialog> createState() => _TemporaryStayDialogState();
}

class _TemporaryStayDialogState extends State<TemporaryStayDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _emailController;
  final _phoneController = TextEditingController();
  final _purposeController = TextEditingController();
  final _docNumberController = TextEditingController();
  final _durationValueController = TextEditingController(text: '1');

  Map<String, dynamic>? _activeExistingRequest;
  bool _isProcessingPayment = false;

  String _gender = 'Male';
  String _docType = 'Aadhaar Card';
  String _durationType = 'days'; // 'days' or 'months'
  DateTime _fromDate = DateTime.now();

  // Document Upload & Verification State
  PlatformFile? _uploadedDocFile;
  bool _isVerifyingDoc = false;
  bool _isDocVerified = false;
  String? _uploadedDocPath;
  String? _docMatchError;

  // Location / Room state
  List<String> _hostels = [];
  String? _selectedHostel;

  List<String> _roomTypes = [];
  String? _selectedRoomType;

  List<Map<String, dynamic>> _rooms = [];
  Map<String, dynamic>? _selectedRoom;

  bool _isLoadingOptions = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _successRequestId;

  final List<String> _docTypes = [
    'Aadhaar Card',
    'PAN Card',
    'Driving License',
    'Passport',
    'Govt ID Card'
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.googleName);
    _emailController = TextEditingController(text: widget.googleEmail);
    _activeExistingRequest = widget.existingRequest != null ? Map<String, dynamic>.from(widget.existingRequest!) : null;
    _loadHostelOptions();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _purposeController.dispose();
    _docNumberController.dispose();
    _durationValueController.dispose();
    super.dispose();
  }

  Future<void> _loadHostelOptions() async {
    setState(() {
      _isLoadingOptions = true;
      _errorMessage = null;
      _hostels = [];
      _selectedHostel = null;
      _roomTypes = [];
      _selectedRoomType = null;
      _rooms = [];
      _selectedRoom = null;
    });

    try {
      final res = await ApiService.fetchTemporaryStayOptions(gender: _gender);
      if (res['success'] == true) {
        final List<dynamic> hList = res['hostels'] ?? [];
        setState(() {
          _hostels = hList.map((e) => e.toString()).toList();
          if (_hostels.isNotEmpty) {
            _selectedHostel = _hostels.first;
            _loadRoomTypes();
          } else {
            _isLoadingOptions = false;
          }
        });
      } else {
        setState(() {
          _errorMessage = res['message'] ?? 'Failed to load hostels';
          _isLoadingOptions = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error: $e';
        _isLoadingOptions = false;
      });
    }
  }

  Future<void> _loadRoomTypes() async {
    if (_selectedHostel == null) return;
    setState(() {
      _isLoadingOptions = true;
      _roomTypes = [];
      _selectedRoomType = null;
      _rooms = [];
      _selectedRoom = null;
    });

    try {
      final res = await ApiService.fetchTemporaryStayOptions(
        gender: _gender,
        hostelName: _selectedHostel,
      );
      if (res['success'] == true) {
        final List<dynamic> rList = res['room_types'] ?? [];
        setState(() {
          _roomTypes = rList.map((e) => e.toString()).toList();
          if (_roomTypes.isNotEmpty) {
            _selectedRoomType = _roomTypes.first;
            _loadRooms();
          } else {
            _isLoadingOptions = false;
          }
        });
      } else {
        setState(() => _isLoadingOptions = false);
      }
    } catch (e) {
      setState(() => _isLoadingOptions = false);
    }
  }

  Future<void> _loadRooms() async {
    if (_selectedHostel == null || _selectedRoomType == null) return;
    setState(() {
      _isLoadingOptions = true;
      _rooms = [];
      _selectedRoom = null;
    });

    try {
      final res = await ApiService.fetchTemporaryStayOptions(
        gender: _gender,
        hostelName: _selectedHostel,
        roomType: _selectedRoomType,
      );
      if (res['success'] == true) {
        final List<dynamic> rmList = res['rooms'] ?? [];
        setState(() {
          _rooms = rmList.map((e) => Map<String, dynamic>.from(e)).toList();
          if (_rooms.isNotEmpty) {
            _selectedRoom = _rooms.first;
          }
          _isLoadingOptions = false;
        });
      } else {
        setState(() => _isLoadingOptions = false);
      }
    } catch (e) {
      setState(() => _isLoadingOptions = false);
    }
  }

  Future<void> _pickAndVerifyDocument() async {
    final docNum = _docNumberController.text.trim();
    if (docNum.isEmpty) {
      setState(() {
        _docMatchError = 'Please type your Document ID Number first before uploading.';
      });
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) {
        setState(() => _docMatchError = 'Could not read document file bytes.');
        return;
      }

      setState(() {
        _uploadedDocFile = file;
        _isVerifyingDoc = true;
        _docMatchError = null;
        _isDocVerified = false;
      });

      final res = await ApiService.uploadAndVerifyTemporaryStayDoc(
        docNumber: docNum,
        fileBytes: file.bytes!,
        fileName: file.name,
      );

      if (res['success'] == true) {
        setState(() {
          _isVerifyingDoc = false;
          _isDocVerified = true;
          _uploadedDocPath = res['file_path'] ?? 'uploads/temp_stay_docs/${file.name}';
          _docMatchError = null;
        });
      } else {
        setState(() {
          _isVerifyingDoc = false;
          _isDocVerified = false;
          _uploadedDocPath = null;
          _docMatchError = res['message'] ?? 'Failed to attach document file. Please upload a valid PDF or Image.';
        });
      }
    } catch (e) {
      setState(() {
        _isVerifyingDoc = false;
        _isDocVerified = false;
        _docMatchError = 'Error uploading document: $e';
      });
    }
  }

  DateTime get _calculatedToDate {
    int val = int.tryParse(_durationValueController.text.trim()) ?? 1;
    if (val < 1) val = 1;
    if (_durationType == 'months') {
      return DateTime(_fromDate.year, _fromDate.month + val, _fromDate.day);
    } else {
      return _fromDate.add(Duration(days: val));
    }
  }

  void _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isDocVerified || _uploadedDocFile == null) {
      setState(() => _errorMessage = 'Please upload your ID document (PDF/Image) and verify matching ID number.');
      return;
    }
    if (_selectedHostel == null || _selectedRoomType == null || _selectedRoom == null) {
      setState(() => _errorMessage = 'Please select a hostel, room type, and room code.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final String fcmToken = await NotificationService.getToken() ?? '';

    final payload = {
      'full_name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim(),
      'gender': _gender,
      'institution_purpose': _purposeController.text.trim(),
      'doc_type': _docType,
      'doc_number': _docNumberController.text.trim(),
      'doc_file_path': _uploadedDocPath ?? '',
      'hostel_name': _selectedHostel,
      'room_type': _selectedRoomType,
      'room_no': _selectedRoom!['room_no'],
      'room_code': _selectedRoom!['room_code'] ?? _selectedRoom!['room_no'],
      'room_id': _selectedRoom!['id'],
      'from_date': DateFormat('yyyy-MM-dd').format(_fromDate),
      'duration_type': _durationType,
      'duration_value': int.tryParse(_durationValueController.text.trim()) ?? 1,
      'fcm_token': fcmToken,
    };

    try {
      final res = await ApiService.submitTemporaryStayRequest(payload);
      if (res['success'] == true) {
        setState(() {
          _isSubmitting = false;
          _successRequestId = res['request_id'] ?? 'TEMP-SUCCESS';
        });
      } else {
        setState(() {
          _isSubmitting = false;
          _errorMessage = res['message'] ?? 'Failed to submit request';
        });
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Connection error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 550;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: isMobile ? 16 : 24,
      ),
      child: Container(
        width: isMobile ? screenWidth * 0.96 : 560,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          children: [
            // Header Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1B2B48), Color(0xFF0F1520)],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.hotel,
                      color: Color(0xFFD4AF37),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Temporary Stay Booking',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: isMobile ? 16 : 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Google Auth: ${widget.googleEmail}',
                          style: GoogleFonts.inter(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Body Content
            Expanded(
              child: _activeExistingRequest != null
                  ? _buildExistingRequestView(_activeExistingRequest!)
                  : SingleChildScrollView(
                      padding: EdgeInsets.all(isMobile ? 14 : 20),
                      child: _successRequestId != null
                          ? _buildSuccessView()
                          : Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_errorMessage != null) _buildErrorBanner(_errorMessage!),

                            _buildSectionHeader('1. Personal & Contact Details'),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _nameController,
                              decoration: _inputDecoration('Full Name', Icons.person),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _emailController,
                              readOnly: true,
                              decoration: _inputDecoration('Google Verified Email', Icons.verified_user)
                                  .copyWith(fillColor: Colors.grey.shade100),
                            ),
                            const SizedBox(height: 12),
                            if (isMobile) ...[
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
                                decoration: _inputDecoration('Phone Number (10 Digits)', Icons.phone),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Phone number is required';
                                  final trimmed = v.trim();
                                  if (trimmed.length != 10) return 'Must be exactly 10 digits';
                                  if (!RegExp(r'^[6-9]\d{9}$').hasMatch(trimmed)) return 'Enter valid 10-digit phone';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _gender,
                                decoration: _inputDecoration('Gender', Icons.wc),
                                items: ['Male', 'Female'].map((g) {
                                  return DropdownMenuItem(value: g, child: Text(g));
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null && val != _gender) {
                                    setState(() => _gender = val);
                                    _loadHostelOptions();
                                  }
                                },
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _phoneController,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(10),
                                      ],
                                      decoration: _inputDecoration('Phone Number (10 Digits)', Icons.phone),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) return 'Phone number is required';
                                        final trimmed = v.trim();
                                        if (trimmed.length != 10) return 'Must be exactly 10 digits';
                                        if (!RegExp(r'^[6-9]\d{9}$').hasMatch(trimmed)) return 'Enter valid 10-digit phone';
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _gender,
                                      decoration: _inputDecoration('Gender', Icons.wc),
                                      items: ['Male', 'Female'].map((g) {
                                        return DropdownMenuItem(value: g, child: Text(g));
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null && val != _gender) {
                                          setState(() => _gender = val);
                                          _loadHostelOptions();
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _purposeController,
                              decoration: _inputDecoration('Institution / Purpose of Stay', Icons.business),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                            ),

                            const SizedBox(height: 20),
                            _buildSectionHeader('2. Government Document Verification'),
                            const SizedBox(height: 10),
                            if (isMobile) ...[
                              DropdownButtonFormField<String>(
                                initialValue: _docType,
                                decoration: _inputDecoration('ID Document Type', Icons.badge),
                                items: _docTypes.map((d) {
                                  return DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 13)));
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _docType = val);
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _docNumberController,
                                decoration: _inputDecoration('Document ID Number', Icons.numbers),
                                onChanged: (_) {
                                  if (_isDocVerified) {
                                    setState(() => _isDocVerified = false);
                                  }
                                },
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _docType,
                                      decoration: _inputDecoration('ID Document Type', Icons.badge),
                                      items: _docTypes.map((d) {
                                        return DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 13)));
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) setState(() => _docType = val);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      controller: _docNumberController,
                                      decoration: _inputDecoration('Document ID Number', Icons.numbers),
                                      onChanged: (_) {
                                        if (_isDocVerified) {
                                          setState(() => _isDocVerified = false);
                                        }
                                      },
                                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            // Document File Upload & Matching Verification Box
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _isDocVerified ? const Color(0xFFE8F5E9) : const Color(0xFFF8F9FA),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _isDocVerified ? Colors.green : (_docMatchError != null ? Colors.red : Colors.grey.shade300),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (isMobile) ...[
                                    Row(
                                      children: [
                                        Icon(
                                          _isDocVerified ? Icons.check_circle : Icons.upload_file,
                                          color: _isDocVerified ? Colors.green : const Color(0xFF1B2B48),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _uploadedDocFile != null
                                                ? 'Attached: ${_uploadedDocFile!.name}'
                                                : 'Upload Document (PDF / Image)',
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: _isDocVerified ? Colors.green.shade800 : const Color(0xFF1B2B48),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _isDocVerified ? Colors.green : const Color(0xFF1B2B48),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onPressed: _isVerifyingDoc ? null : _pickAndVerifyDocument,
                                        icon: _isVerifyingDoc
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                              )
                                            : Icon(_isDocVerified ? Icons.check_circle : Icons.file_upload, size: 16),
                                        label: Text(_isDocVerified ? 'Change Document File' : 'Upload Document'),
                                      ),
                                    ),
                                  ] else ...[
                                    Row(
                                      children: [
                                        Icon(
                                          _isDocVerified ? Icons.check_circle : Icons.upload_file,
                                          color: _isDocVerified ? Colors.green : const Color(0xFF1B2B48),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            _uploadedDocFile != null
                                                ? 'Attached File: ${_uploadedDocFile!.name}'
                                                : 'Upload Document File (PDF / Image)',
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: _isDocVerified ? Colors.green.shade800 : const Color(0xFF1B2B48),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _isDocVerified ? Colors.green : const Color(0xFF1B2B48),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onPressed: _isVerifyingDoc ? null : _pickAndVerifyDocument,
                                          icon: _isVerifyingDoc
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                                )
                                              : Icon(_isDocVerified ? Icons.check_circle : Icons.file_upload, size: 16),
                                          label: Text(_isDocVerified ? 'Change File' : 'Upload Document'),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (_isDocVerified) ...[
                                    const SizedBox(height: 8),
                                    const Row(
                                      children: [
                                        Icon(Icons.verified, color: Colors.green, size: 16),
                                        SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Verified Match: Document ID matches the uploaded file.',
                                            style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (_docMatchError != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      _docMatchError!,
                                      style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(height: 20),
                            _buildSectionHeader('3. Stay Duration & Dates'),
                            const SizedBox(height: 10),
                            if (isMobile) ...[
                              InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _fromDate,
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now().add(const Duration(days: 365)),
                                  );
                                  if (picked != null) {
                                    setState(() => _fromDate = picked);
                                  }
                                },
                                child: InputDecorator(
                                  decoration: _inputDecoration('Start Date (From)', Icons.calendar_today),
                                  child: Text(
                                    DateFormat('dd MMM yyyy').format(_fromDate),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _durationValueController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: _inputDecoration('Number of Stay Units (e.g. 1, 2, 5)', Icons.timer),
                                onChanged: (_) => setState(() {}),
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _durationType,
                                decoration: _inputDecoration('Duration Unit', Icons.schedule),
                                items: const [
                                  DropdownMenuItem(value: 'days', child: Text('Days')),
                                  DropdownMenuItem(value: 'months', child: Text('Months')),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() => _durationType = val);
                                },
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: _fromDate,
                                          firstDate: DateTime.now(),
                                          lastDate: DateTime.now().add(const Duration(days: 365)),
                                        );
                                        if (picked != null) {
                                          setState(() => _fromDate = picked);
                                        }
                                      },
                                      child: InputDecorator(
                                        decoration: _inputDecoration('Start Date (From)', Icons.calendar_today),
                                        child: Text(
                                          DateFormat('dd MMM yyyy').format(_fromDate),
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: _durationValueController,
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                            decoration: _inputDecoration('Duration Number', Icons.timer),
                                            onChanged: (_) => setState(() {}),
                                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Req' : null,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        DropdownButton<String>(
                                          value: _durationType,
                                          items: const [
                                            DropdownMenuItem(value: 'days', child: Text('Days')),
                                            DropdownMenuItem(value: 'months', child: Text('Months')),
                                          ],
                                          onChanged: (val) {
                                            if (val != null) setState(() => _durationType = val);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF8E1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFFE082)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.event_available, color: Color(0xFFD4AF37), size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Valid Stay Until: ${DateFormat('dd MMM yyyy').format(_calculatedToDate)}',
                                      style: TextStyle(color: Colors.amber.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 20),
                            _buildSectionHeader('4. Hostel & Room Selection'),
                            const SizedBox(height: 10),
                            if (_isLoadingOptions)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            else ...[
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _selectedHostel,
                                decoration: _inputDecoration('Gender Hostel (${_gender == 'Female' ? 'Girls' : 'Boys'})', Icons.apartment),
                                items: _hostels.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedHostel = val);
                                    _loadRoomTypes();
                                  }
                                },
                              ),
                              const SizedBox(height: 12),
                              if (_roomTypes.isNotEmpty)
                                DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: _selectedRoomType,
                                  decoration: _inputDecoration('Room Type', Icons.meeting_room),
                                  items: _roomTypes.map((rt) => DropdownMenuItem(value: rt, child: Text(rt))).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _selectedRoomType = val);
                                      _loadRooms();
                                    }
                                  },
                                ),
                              const SizedBox(height: 12),
                              if (_rooms.isNotEmpty)
                                DropdownButtonFormField<Map<String, dynamic>>(
                                  isExpanded: true,
                                  initialValue: _selectedRoom,
                                  decoration: _inputDecoration('Full Room Code & Free Beds', Icons.bed),
                                  items: _rooms.map((rm) {
                                    final String fullCode = rm['room_code'] ?? rm['room_no'];
                                    final int vac = (rm['vacancies'] is int) ? rm['vacancies'] : (int.tryParse(rm['vacancies']?.toString() ?? '1') ?? 1);
                                    final String bedText = vac == 1 ? '1 bed available' : '$vac beds available';
                                    final String label = '$fullCode ($bedText)';
                                    return DropdownMenuItem<Map<String, dynamic>>(
                                      value: rm,
                                      child: Text(
                                        label,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _selectedRoom = val);
                                  },
                                )
                              else if (_selectedRoomType != null)
                                const Text(
                                  'No vacant rooms available for selected room type.',
                                  style: TextStyle(color: Colors.red, fontSize: 12),
                                ),
                            ],
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isDocVerified ? const Color(0xFFD4AF37) : Colors.grey.shade400,
                                  foregroundColor: const Color(0xFF1B2B48),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  elevation: 3,
                                ),
                                onPressed: (_isSubmitting || !_isDocVerified) ? null : _handleSubmit,
                                child: _isSubmitting
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(color: Color(0xFF1B2B48), strokeWidth: 2.5),
                                      )
                                    : Text(
                                        _isDocVerified ? 'Verify & Submit Application' : 'Attach Document to Submit',
                                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: const Color(0xFF1B2B48),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 11, color: Colors.grey.shade700),
      prefixIcon: Icon(icon, size: 16, color: const Color(0xFF1B2B48)),
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5)),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Color(0xFFE8F5E9),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle, color: Colors.green, size: 50),
          ),
          const SizedBox(height: 16),
          Text(
            'Request Submitted!',
            style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1B2B48)),
          ),
          const SizedBox(height: 8),
          Text(
            'Request ID: $_successRequestId',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFD4AF37)),
          ),
          const SizedBox(height: 14),
          const Text(
            'Your temporary stay request and verified ID document have been transmitted to the Hostel Admin. Push notifications have been sent to staff for review and approval.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B2B48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePayment(String requestId) async {
    setState(() {
      _isProcessingPayment = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiService.payTemporaryStayRequest(requestId);
      if (res['success'] == true) {
        setState(() {
          _isProcessingPayment = false;
          if (_activeExistingRequest != null) {
            _activeExistingRequest!['status'] = 'allocated';
            _activeExistingRequest!['payment_status'] = 'paid';
            _activeExistingRequest!['payment_txn_id'] = res['payment_txn_id'] ?? 'TXN-CONFIRMED';
          }
        });
      } else {
        setState(() {
          _isProcessingPayment = false;
          _errorMessage = res['message'] ?? 'Payment failed';
        });
      }
    } catch (e) {
      setState(() {
        _isProcessingPayment = false;
        _errorMessage = 'Payment error: $e';
      });
    }
  }

  Widget _buildExistingRequestView(Map<String, dynamic> req) {
    final status = req['status'] ?? 'pending';
    final paymentStatus = req['payment_status'] ?? 'unpaid';
    final double amount = (req['amount'] != null) ? double.tryParse(req['amount'].toString()) ?? 0.0 : 0.0;
    final String amountStr = amount > 0 ? '₹${amount.toStringAsFixed(2)}' : 'Calculating...';
    final String roomCodeDisplay = (req['room_code'] != null && req['room_code'].toString().isNotEmpty)
        ? req['room_code']
        : (req['room_no'] ?? 'N/A');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (status == 'approved' && paymentStatus != 'paid') ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Temporary Stay Request Approved! 🎉',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green.shade900),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Your application has been approved by admin. Please complete your payment below to allocate your room.',
                          style: TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else if (status == 'allocated' || paymentStatus == 'paid') ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.vpn_key_rounded, color: Color(0xFF1B2B48), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Room Allocated & Confirmed! 🔑',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: const Color(0xFF1B2B48)),
                        ),
                        Text(
                          'Transaction ID: ${req['payment_txn_id'] ?? 'TXN-CONFIRMED'}',
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else if (status == 'rejected') ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cancel_rounded, color: Colors.red, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Application Rejected',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.red.shade900),
                        ),
                        Text(
                          'Reason: ${req['admin_notes'] ?? 'Administrative decision'}',
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade400),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top_rounded, color: Colors.amber, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Application Under Admin Review',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.amber.shade900),
                        ),
                        const Text(
                          'Your booking is currently under review by hostel administration. You will receive a push notification once approved with payment details.',
                          style: TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Request Details Summary Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(Icons.pin, 'Request ID', req['request_id'] ?? 'N/A'),
                const Divider(height: 12),
                _infoRow(Icons.person, 'Applicant Name', req['full_name'] ?? 'N/A'),
                const Divider(height: 12),
                _infoRow(Icons.email, 'Email Address', req['email'] ?? 'N/A'),
                const Divider(height: 12),
                _infoRow(Icons.hotel, 'Hostel & Room', '${req['hostel_name']} - $roomCodeDisplay'),
                const Divider(height: 12),
                _infoRow(Icons.calendar_month, 'Stay Duration', '${req['duration_value']} ${req['duration_type']} (${req['from_date']} to ${req['to_date']})'),
                const Divider(height: 12),
                _infoRow(Icons.payments, 'Calculated Payment Fee', '$amountStr (Annual/365 x days)'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (status == 'approved' && paymentStatus != 'paid') ...[
            if (_errorMessage != null) ...[
              Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isProcessingPayment
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.payment, size: 20),
                label: Text(
                  _isProcessingPayment ? 'Processing Payment...' : 'Pay Now & Allocate Room ($amountStr)',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                onPressed: _isProcessingPayment ? null : () => _handlePayment(req['request_id']),
              ),
            ),
          ] else if (status == 'rejected') ...[
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _activeExistingRequest = null;
                  });
                },
                child: const Text('Submit New Booking Request', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFFD4AF37)),
        const SizedBox(width: 8),
        SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))),
        const Text(' : ', style: TextStyle(fontWeight: FontWeight.bold)),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
      ],
    );
  }
}
