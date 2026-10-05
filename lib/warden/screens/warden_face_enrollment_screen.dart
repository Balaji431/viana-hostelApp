import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/api_service.dart';
import '../../core/styles.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../widgets/warden_widgets.dart' show LinenBackground;
import '../../student/face_attendance/controllers/face_attendance_controller.dart';
import '../../student/face_attendance/models/face_attendance_models.dart';
import '../../student/face_attendance/models/face_attendance_state_config.dart';
import '../../student/face_attendance/services/attendance_punch_service.dart';
import '../../student/face_attendance/theme/face_attendance_theme.dart';
import '../../student/face_attendance/widgets/face_camera_frame.dart';

enum EnrollmentStep { lookup, cameraCapture, success }

class WardenFaceEnrollmentScreen extends StatefulWidget {
  final String? prefillRegNo;
  const WardenFaceEnrollmentScreen({super.key, this.prefillRegNo});

  @override
  State<WardenFaceEnrollmentScreen> createState() => _WardenFaceEnrollmentScreenState();
}

class _WardenFaceEnrollmentScreenState extends State<WardenFaceEnrollmentScreen> {
  final TextEditingController _regNoController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;

  EnrollmentStep _step = EnrollmentStep.lookup;
  bool _isVerifying = false;
  String? _errorMessage;
  String? _errorCode;
  Map<String, dynamic>? _verifiedStudent;
  Map<String, dynamic>? _enrollmentResult;

  FaceAttendanceController? _faceController;

  // Floor students autocomplete/dropdown state
  List<Map<String, dynamic>> _floorStudents = [];
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoadingFloorStudents = false;
  bool _isLoadingSuggestions = false;
  bool _showSuggestionsDropdown = false;

  @override
  void initState() {
    super.initState();
    if (widget.prefillRegNo != null && widget.prefillRegNo!.isNotEmpty) {
      _regNoController.text = widget.prefillRegNo!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _verifyStudent();
      });
    }

    _regNoController.addListener(_onControllerChanged);
    _searchFocusNode.addListener(_onFocusChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFloorStudents();
    });
  }

  void _onControllerChanged() {
    final query = _regNoController.text.trim();
    if (query.isEmpty) {
      if (_showSuggestionsDropdown && _suggestions.isNotEmpty) {
        setState(() {
          _suggestions = [];
          _showSuggestionsDropdown = false;
        });
      }
      return;
    }
    _onSearchChanged(query);
  }

  void _onFocusChanged() {
    if (_searchFocusNode.hasFocus && _regNoController.text.trim().isNotEmpty) {
      _onSearchChanged(_regNoController.text.trim());
    }
  }

  Future<void> _loadFloorStudents() async {
    final warden = context.read<UserProvider>();
    final wardenId = warden.username.isNotEmpty ? warden.username : warden.userName;
    if (wardenId.isEmpty) return;

    setState(() => _isLoadingFloorStudents = true);
    try {
      final res = await ApiService.searchFloorStudentsForEnrollment(
        query: '',
        wardenUsername: wardenId,
      );

      if (mounted && res['success'] == true && res['students'] != null) {
        final list = List<Map<String, dynamic>>.from(res['students']);
        setState(() {
          _floorStudents = list;
          _isLoadingFloorStudents = false;
        });
        return;
      }

      // Fallback
      final fallbackRes = await ApiService.getStudents(wardenUsername: wardenId);
      if (mounted && fallbackRes['success'] == true && fallbackRes['data'] != null) {
        final rawList = List<Map<String, dynamic>>.from(fallbackRes['data']);
        final converted = rawList.map((s) => {
          'reg_no': s['register_number'] ?? s['reg_no'] ?? '',
          'register_number': s['register_number'] ?? s['reg_no'] ?? '',
          'full_name': s['full_name'] ?? 'Student',
          'room_no': s['room_no'] ?? s['room_code'] ?? '',
          'floor_name': s['floor'] ?? 'Assigned Floor',
          'hostel_name': s['hostel_name'] ?? '',
          'is_allocated': true,
          'is_assigned_to_you': true,
          'is_face_enrolled': false,
        }).toList();

        setState(() {
          _floorStudents = converted;
          _isLoadingFloorStudents = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingFloorStudents = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingFloorStudents = false);
    }
  }

  void _onSearchChanged(String query) {
    final clean = query.trim();
    if (clean.isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestionsDropdown = false;
        _errorMessage = null;
      });
      return;
    }

    // 1. Instant client-side filtering on all preloaded floor students
    final q = clean.toLowerCase();
    final localMatches = _floorStudents.where((s) {
      final reg = (s['reg_no'] ?? s['register_number'] ?? '').toString().toLowerCase();
      final name = (s['full_name'] ?? '').toString().toLowerCase();
      final room = (s['room_no'] ?? '').toString().toLowerCase();
      return reg.contains(q) || name.contains(q) || room.contains(q);
    }).toList();

    setState(() {
      _suggestions = localMatches;
      _showSuggestionsDropdown = true;
      _errorMessage = null;
    });

    // 2. Debounced API search to fetch any server-side updates
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () async {
      final warden = context.read<UserProvider>();
      final wardenId = warden.username.isNotEmpty ? warden.username : warden.userName;
      try {
        final res = await ApiService.searchFloorStudentsForEnrollment(
          query: clean,
          wardenUsername: wardenId,
        );
        if (!mounted) return;
        if (res['success'] == true && res['students'] != null) {
          final serverStudents = List<Map<String, dynamic>>.from(res['students']);
          if (_regNoController.text.trim() == clean) {
            setState(() {
              _suggestions = serverStudents;
              // Also merge into _floorStudents cache
              for (final s in serverStudents) {
                final reg = s['reg_no'] ?? s['register_number'];
                if (!_floorStudents.any((existing) => (existing['reg_no'] ?? existing['register_number']) == reg)) {
                  _floorStudents.add(s);
                }
              }
            });
          }
        }
      } catch (_) {}
    });
  }

  void _selectStudentFromDropdown(Map<String, dynamic> student) {
    final reg = (student['reg_no'] ?? student['register_number'] ?? '').toString();
    _regNoController.text = reg;
    _searchFocusNode.unfocus();
    setState(() {
      _showSuggestionsDropdown = false;
      _errorMessage = null;
      _errorCode = null;
      _verifiedStudent = {
        'reg_no': reg,
        'full_name': student['full_name'] ?? 'Student',
        'room_no': student['room_no'] ?? 'Room',
        'floor_name': student['floor_name'] ?? 'Assigned Floor',
        'hostel_name': student['hostel_name'] ?? 'Hostel',
        'is_allocated': true,
        'is_assigned_to_you': true,
        'assigned_warden': context.read<UserProvider>().userName,
      };
    });

    _verifyStudent();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _regNoController.removeListener(_onControllerChanged);
    _searchFocusNode.removeListener(_onFocusChanged);
    _searchFocusNode.dispose();
    _regNoController.dispose();
    _faceController?.dispose();
    super.dispose();
  }

  Future<void> _verifyStudent() async {
    final regNo = _regNoController.text.trim();
    if (regNo.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a student Register Number.';
        _errorCode = 'EMPTY_REG';
        _verifiedStudent = null;
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
      _errorCode = null;
      _verifiedStudent = null;
    });

    final warden = context.read<UserProvider>();
    try {
      final res = await ApiService.verifyStudentForFaceEnrollment(
        regNo: regNo,
        wardenUsername: warden.username,
      );

      if (!mounted) return;

      final bool isSuccess = res['success'] == true;
      if (isSuccess) {
        setState(() {
          _isVerifying = false;
          _verifiedStudent = res['student'] as Map<String, dynamic>? ?? {};
          _errorMessage = null;
          _errorCode = null;
        });
      } else {
        setState(() {
          _isVerifying = false;
          _errorMessage = res['message'] ?? 'Could not verify student.';
          _errorCode = res['error_code'] ?? 'VERIFICATION_FAILED';
          _verifiedStudent = res['student'] as Map<String, dynamic>?;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _errorMessage = 'Connection error while checking student allocation: $e';
          _errorCode = 'NETWORK_ERROR';
        });
      }
    }
  }

  void _startCameraEnrollment() {
    if (_verifiedStudent == null) return;

    final studentReg = _verifiedStudent!['reg_no']?.toString() ?? _regNoController.text.trim();
    final studentName = _verifiedStudent!['full_name']?.toString() ?? 'Student';

    _faceController = FaceAttendanceController(
      initialMode: FaceScanMode.registration,
      preferredLens: CameraLensDirection.back,
    );

    _faceController!.setStudentInfo(
      username: studentReg,
      name: studentName,
      registerNumber: studentReg,
    );

    setState(() {
      _step = EnrollmentStep.cameraCapture;
    });

    _faceController!.initialize();

    // Listen to controller status for registration completion
    _faceController!.addListener(_handleFaceControllerUpdate);
  }

  void _handleFaceControllerUpdate() {
    if (_faceController == null || !mounted) return;

    if (_faceController!.status == FaceAttendanceStatus.faceRegistered ||
        _faceController!.isSessionCompleted) {
      _completeEnrollmentSuccess();
    }
  }

  Future<void> _completeEnrollmentSuccess() async {
    final warden = context.read<UserProvider>();
    final studentReg = _verifiedStudent!['reg_no']?.toString() ?? _regNoController.text.trim();
    final studentName = _verifiedStudent!['full_name']?.toString() ?? 'Student';

    // Mark locally
    await AttendancePunchService.setFaceEnrolled(studentReg);

    // Save to backend
    final res = await ApiService.enrollStudentBiometricFace(
      regNo: studentReg,
      studentName: studentName,
      wardenUsername: warden.username,
    );

    if (mounted) {
      setState(() {
        _enrollmentResult = {
          'reference_id': res['reference_id'] ?? 'BIO-ENR-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}',
          'enrolled_at': res['enrolled_at'] ?? DateFormat('dd MMM yyyy, h:mm a').format(DateTime.now()),
          'student_name': studentName,
          'reg_no': studentReg,
          'room_no': _verifiedStudent!['room_no'] ?? 'N/A',
          'floor_name': _verifiedStudent!['floor_name'] ?? 'Assigned Floor',
        };
        _step = EnrollmentStep.success;
      });
    }
  }

  void _resetToLookup() {
    setState(() {
      _regNoController.clear();
      _verifiedStudent = null;
      _errorMessage = null;
      _errorCode = null;
      _enrollmentResult = null;
      _suggestions = [];
      _showSuggestionsDropdown = false;
      _step = EnrollmentStep.lookup;
    });
    _faceController?.removeListener(_handleFaceControllerUpdate);
    _faceController?.dispose();
    _faceController = null;
  }

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1522) : const Color(0xFFF4F6F9),
      appBar: SkeuomorphicNavBar(
        title: _step == EnrollmentStep.cameraCapture
            ? 'Camera Face Capture'
            : (_step == EnrollmentStep.success ? 'Enrollment Complete' : 'Enroll Student Face'),
        onBack: () {
          if (_step == EnrollmentStep.cameraCapture) {
            setState(() => _step = EnrollmentStep.lookup);
            _faceController?.dispose();
            _faceController = null;
          } else {
            Navigator.of(context).pop();
          }
        },
      ),
      body: LinenBackground(
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _buildCurrentStep(isDark),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep(bool isDark) {
    switch (_step) {
      case EnrollmentStep.lookup:
        return _buildLookupView(isDark);
      case EnrollmentStep.cameraCapture:
        return _buildCameraCaptureView(isDark);
      case EnrollmentStep.success:
        return _buildSuccessView(isDark);
    }
  }

  // ==================== STEP 1: LOOKUP & ALLOCATION CHECK ====================

  Widget _buildLookupView(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Instructions Card
          _buildWardenBanner(isDark),
          const SizedBox(height: 18),

          // Register Number Input Card
          _buildSearchCard(isDark),
          const SizedBox(height: 18),

          // Error / Allocation Warning Card
          if (_errorMessage != null)
            _buildErrorWarningCard(isDark),

          // Verified Student Card
          if (_verifiedStudent != null && _errorMessage == null)
            _buildVerifiedStudentCard(isDark),
        ],
      ),
    );
  }

  Widget _buildWardenBanner(bool isDark) {
    final user = context.watch<UserProvider>();
    final wardenName = user.userName.isNotEmpty ? user.userName : 'Floor Warden';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                colors: [Color(0xFF162032), Color(0xFF0F172A)],
              )
            : const LinearGradient(
                colors: [Color(0xFF1E2F5E), Color(0xFF152244)],
              ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.45),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFD4AF37), width: 1.2),
            ),
            child: const Icon(
              Icons.how_to_reg_rounded,
              color: Color(0xFFD4AF37),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'IN-PERSON FACE ENROLLMENT',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD4AF37),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Register Assigned Students',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontFamily: 'Playfair',
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Logged in as $wardenName. Students must be allocated to your assigned floor to be enrolled.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.75),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF162032) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'STUDENT REGISTER NUMBER',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : const Color(0xFF1B2B48),
                  letterSpacing: 0.6,
                ),
              ),
              if (_floorStudents.isNotEmpty)
                Text(
                  '${_floorStudents.length} Students on Floor',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFD4AF37),
                    letterSpacing: 0.4,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.4),
                      width: 1.2,
                    ),
                  ),
                  child: TextField(
                    controller: _regNoController,
                    focusNode: _searchFocusNode,
                    textCapitalization: TextCapitalization.characters,
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1B2B48),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter student Reg No (e.g. 192211...)',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white38 : Colors.grey.shade400,
                        fontSize: 13,
                        fontWeight: FontWeight.normal,
                      ),
                      prefixIcon: const Icon(
                        Icons.badge_outlined,
                        color: Color(0xFFD4AF37),
                        size: 20,
                      ),
                      suffixIcon: _regNoController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.grey),
                              onPressed: () {
                                _regNoController.clear();
                                setState(() {
                                  _errorMessage = null;
                                  _verifiedStudent = null;
                                  _suggestions = [];
                                  _showSuggestionsDropdown = false;
                                });
                              },
                            )
                          : IconButton(
                              icon: Icon(
                                _showSuggestionsDropdown ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                                color: const Color(0xFFD4AF37),
                                size: 26,
                              ),
                              onPressed: () {
                                setState(() {
                                  _showSuggestionsDropdown = !_showSuggestionsDropdown;
                                  if (_showSuggestionsDropdown && _suggestions.isEmpty) {
                                    _suggestions = List.from(_floorStudents);
                                  }
                                });
                              },
                            ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                    ),
                    onSubmitted: (_) {
                      setState(() => _showSuggestionsDropdown = false);
                      _verifyStudent();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: const Color(0xFF1B2B48),
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  onPressed: _isVerifying
                      ? null
                      : () {
                          setState(() => _showSuggestionsDropdown = false);
                          _verifyStudent();
                        },
                  child: _isVerifying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1B2B48)),
                          ),
                        )
                      : const Row(
                          children: [
                            Icon(Icons.search_rounded, size: 18),
                            SizedBox(width: 6),
                            Text('Verify', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                ),
              ),
            ],
          ),
          if (_showSuggestionsDropdown) ...[
            const SizedBox(height: 12),
            _buildDropdownSuggestions(isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildDropdownSuggestions(bool isDark) {
    final query = _regNoController.text.trim();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.45),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF162032) : const Color(0xFFEDF2F7),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white10 : Colors.grey.shade300,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.groups_rounded,
                        size: 16,
                        color: Color(0xFFD4AF37),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'STUDENTS ON YOUR FLOOR',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white70 : const Color(0xFF1B2B48),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_suggestions.length} MATCH${_suggestions.length == 1 ? '' : 'ES'}',
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFD4AF37),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Suggestion Items or Empty View
          if (_suggestions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 32,
                    color: isDark ? Colors.white30 : Colors.grey.shade400,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    query.isNotEmpty
                        ? 'No students found on your floor matching "$query"'
                        : 'No students currently allocated to this floor',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Only students assigned to your floor can be enrolled.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _suggestions.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200,
                  indent: 14,
                  endIndent: 14,
                ),
                itemBuilder: (context, index) {
                  final student = _suggestions[index];
                  final name = student['full_name']?.toString() ?? 'Student';
                  final reg = (student['reg_no'] ?? student['register_number'] ?? '').toString();
                  final room = student['room_no']?.toString() ?? '';
                  final floor = student['floor_name']?.toString() ?? '';

                  return InkWell(
                    onTap: () => _selectStudentFromDropdown(student),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      child: Row(
                        children: [
                          // Student Avatar (Unified Gold Gradient)
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFD4AF37), Color(0xFFA68019)],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : 'S',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Name and Reg No + Room
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : const Color(0xFF1B2B48),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      reg,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFD4AF37),
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    if (room.isNotEmpty) ...[
                                      Text(
                                        ' • ',
                                        style: TextStyle(
                                          color: isDark ? Colors.white38 : Colors.grey.shade400,
                                        ),
                                      ),
                                      Flexible(
                                        child: Text(
                                          floor.isNotEmpty ? 'Room $room ($floor)' : 'Room $room',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w500,
                                            color: isDark ? Colors.white70 : Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Ready Tag Pill (All students ready for enrollment)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFFF59E0B),
                                width: 0.8,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.camera_alt_outlined,
                                  size: 11,
                                  color: Color(0xFFF59E0B),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Ready',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFF59E0B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: isDark ? Colors.white30 : Colors.grey.shade400,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorWarningCard(bool isDark) {
    final isNotAllocated = _errorCode == 'NOT_ALLOCATED';
    final isOtherWarden = _errorCode == 'ALLOCATED_TO_OTHER_WARDEN';

    final Color cardColor = isNotAllocated
        ? const Color(0xFFEF4444)
        : (isOtherWarden ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

    final IconData icon = isNotAllocated
        ? Icons.cancel_outlined
        : (isOtherWarden ? Icons.warning_amber_rounded : Icons.error_outline_rounded);

    final String title = isNotAllocated
        ? 'ROOM ALLOCATION REQUIRED'
        : (isOtherWarden ? 'UNAUTHORIZED FLOOR ALLOCATION' : 'STUDENT LOOKUP FAILED');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cardColor.withValues(alpha: 0.6),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: cardColor.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: cardColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: cardColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _errorMessage ?? 'Verification failed',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1B2B48),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isOtherWarden && _verifiedStudent != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cardColor.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  _buildDetailRow('Student Name', _verifiedStudent!['full_name'] ?? 'N/A', isDark),
                  _buildDetailRow('Allocated Room', _verifiedStudent!['room_no'] ?? 'N/A', isDark),
                  _buildDetailRow('Assigned Floor', _verifiedStudent!['floor_name'] ?? 'N/A', isDark),
                  _buildDetailRow('Authorized Warden', _verifiedStudent!['assigned_warden'] ?? 'Other Warden', isDark, isHighlight: true),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVerifiedStudentCard(bool isDark) {
    final name = _verifiedStudent!['full_name'] ?? 'Student Name';
    final regNo = _verifiedStudent!['reg_no'] ?? _regNoController.text.trim();
    final roomNo = _verifiedStudent!['room_no'] ?? 'Room';
    final floorName = _verifiedStudent!['floor_name'] ?? 'Floor';
    final hostelName = _verifiedStudent!['hostel_name'] ?? 'Hostel';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF162032) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with Verified Pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF10B981), width: 1),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_rounded, size: 14, color: Color(0xFF10B981)),
                    SizedBox(width: 5),
                    Text(
                      'ALLOCATION VERIFIED',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'YOUR FLOOR',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFD4AF37),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Student Info Row
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: SkeuomorphicColors.goldGlossyGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'S',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1B2B48),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF1B2B48),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Reg No: $regNo',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Allocation Details Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
            ),
            child: Column(
              children: [
                _buildDetailRow('Room Number', roomNo, isDark),
                _buildDetailRow('Floor Assigned', floorName, isDark),
                _buildDetailRow('Hostel Block', hostelName, isDark),
                _buildDetailRow('Warden Match', '✓ Assigned to Your Floor', isDark, isHighlight: true),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Action Button: Start Camera Face Capture
          SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: const Color(0xFF1B2B48),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _startCameraEnrollment,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt_rounded, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Proceed to Face Biometric Capture',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.grey.shade600,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: isHighlight
                    ? const Color(0xFF10B981)
                    : (isDark ? Colors.white : const Color(0xFF1B2B48)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== STEP 2: CAMERA CAPTURE & LIVENESS ====================

  Widget _buildCameraCaptureView(bool isDark) {
    if (_faceController == null) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
    }

    return ChangeNotifierProvider<FaceAttendanceController>.value(
      value: _faceController!,
      child: Consumer<FaceAttendanceController>(
        builder: (context, controller, child) {
          final config = controller.currentConfig;
          final studentName = _verifiedStudent!['full_name'] ?? 'Student';
          final regNo = _verifiedStudent!['reg_no'] ?? _regNoController.text.trim();
          final roomNo = _verifiedStudent!['room_no'] ?? '';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                // Top Info Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF162032) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person_pin_rounded, color: Color(0xFFD4AF37), size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Enrolling: $studentName ($regNo) · Room $roomNo',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF1B2B48),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Warden Direction Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4AF37).withValues(alpha: isDark ? 0.15 : 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.6),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.camera_rear_rounded, color: Color(0xFFD4AF37), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Point back camera at student standing opposite you. Guide student: 1. Turn Left  2. Turn Right  3. Blink Eyes',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Camera Viewfinder Box
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380, maxHeight: 440),
                  child: FaceCameraFrame(
                    cameraController: controller.detectionService.controller,
                    isSimulated: controller.detectionService.isSimulated,
                    status: controller.status,
                    config: config,
                    currentChallenge: controller.currentChallenge,
                    challengeIndex: controller.currentChallengeIndex,
                    challengesDone: controller.challengesDone,
                    challenges: controller.challenges,
                  ),
                ),
                const SizedBox(height: 14),

                // Liveness Instructions Banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF162032) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        config.guideText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1B2B48),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        config.guideHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Manual Capture / Force Register Button (If needed)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      foregroundColor: const Color(0xFF1B2B48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      controller.registerFace();
                    },
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.fingerprint_rounded, size: 20),
                        SizedBox(width: 8),
                        Text('Complete Face Registration', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ==================== STEP 3: ENROLLMENT SUCCESS ====================

  Widget _buildSuccessView(bool isDark) {
    final result = _enrollmentResult ?? {};
    final studentName = result['student_name'] ?? 'Student';
    final regNo = result['reg_no'] ?? '';
    final roomNo = result['room_no'] ?? '';
    final floorName = result['floor_name'] ?? '';
    final refId = result['reference_id'] ?? 'BIO-ENR-SUCCESS';
    final timeStr = result['enrolled_at'] ?? DateFormat('dd MMM yyyy, h:mm a').format(DateTime.now());

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Celebration Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF162032), Color(0xFF0F172A)],
                    )
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFFFFFF), Color(0xFFF9FAFB)],
                    ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.7),
                width: 1.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                // Big Checkmark
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF34D399), Color(0xFF059669)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.check_rounded, color: Colors.white, size: 44),
                  ),
                ),
                const SizedBox(height: 16),

                // Title
                Text(
                  'Face Registered Successfully',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Playfair',
                    color: isDark ? Colors.white : const Color(0xFF1B2B48),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Biometric profile has been linked and activated in the hostel attendance database.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? Colors.white70 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 20),

                // Record Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow('Resident Name', studentName, isDark),
                      _buildDetailRow('Register Number', regNo, isDark),
                      _buildDetailRow('Room & Floor', '$roomNo ($floorName)', isDark),
                      _buildDetailRow('Timestamp', timeStr, isDark),
                      _buildDetailRow('Reference ID', refId, isDark, isHighlight: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Action Buttons
          SizedBox(
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: const Color(0xFF1B2B48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 3,
              ),
              onPressed: _resetToLookup,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_add_rounded, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Enroll Another Student',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? Colors.white : const Color(0xFF1B2B48),
                side: BorderSide(
                  color: isDark ? Colors.white24 : Colors.grey.shade400,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to Dashboard'),
            ),
          ),
        ],
      ),
    );
  }
}
