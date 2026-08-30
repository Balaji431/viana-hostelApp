import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/api_service.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';

class StudentRoomTransferModal extends StatefulWidget {
  final VoidCallback onSubmitted;
  final int initialStep;

  const StudentRoomTransferModal({
    super.key,
    required this.onSubmitted,
    this.initialStep = 2,
  });

  static void show(
    BuildContext context, {
    required VoidCallback onSubmitted,
    int initialStep = 2,
  }) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StudentRoomTransferModal(
        onSubmitted: onSubmitted,
        initialStep: initialStep,
      ),
    );
  }

  @override
  State<StudentRoomTransferModal> createState() => _StudentRoomTransferModalState();
}

class _StudentRoomTransferModalState extends State<StudentRoomTransferModal> {
  late int _currentStep;
  bool _isSubmitting = false;
  bool _isLoadingHostels = false;
  bool _isLoadingRoomTypes = false;
  String? _hostelLoadError;

  // Selection state
  Map<String, dynamic>? _selectedHostel;
  Map<String, dynamic>? _selectedRoomType;
  Map<String, dynamic>? _selectedRoom;
  final TextEditingController _reasonController = TextEditingController();

  // Hostels & room options matched by gender (loaded from live API)
  List<Map<String, dynamic>> _hostelOptions = [];
  List<Map<String, dynamic>> _roomTypeOptions = [];
  List<Map<String, dynamic>> _roomOptions = [];

  @override
  void initState() {
    super.initState();
    _currentStep = widget.initialStep;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHostelsFromApi();
    });
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadHostelsFromApi() async {
    final user = context.read<UserProvider>();
    final reg = user.registerNo;
    if (reg.isEmpty) return;

    setState(() {
      _isLoadingHostels = true;
      _hostelLoadError = null;
      _hostelOptions = [];
    });

    try {
      final res = await ApiService.getRequest('student/get_hostels.php?username=$reg');
      final data = res['data'];
      final List raw = data['all_hostels'] ?? [];
      final hostels = raw
          .map((h) => Map<String, dynamic>.from(h as Map))
          .where((h) => (h['available_rooms'] ?? 0) > 0)
          .toList();
      if (mounted) setState(() => _hostelOptions = hostels);
    } catch (e) {
      if (mounted) setState(() => _hostelLoadError = e.toString());
    } finally {
      if (mounted) setState(() => _isLoadingHostels = false);
    }
  }

  Future<void> _loadRoomTypesForHostel(Map<String, dynamic> hostel) async {
    final hostelName = (hostel['hostel_name'] ?? hostel['name'] ?? '').toString();
    final user = context.read<UserProvider>();
    final reg  = user.registerNo;

    setState(() {
      _isLoadingRoomTypes = true;
      _roomTypeOptions = [];
      _selectedRoomType = null;
    });

    try {
      final res = await ApiService.getRequest('student/get_available_rooms.php?vacant_only=true&hostel_name=${Uri.encodeComponent(hostelName)}&register_no=${Uri.encodeComponent(reg)}');

      // Build room-type list grouped from the rooms data
      final List rawRooms = res['data'] ?? res['rooms'] ?? [];
      // Group by room_type
      final Map<String, Map<String, dynamic>> byType = {};
      for (final r in rawRooms) {
        final rm = Map<String, dynamic>.from(r as Map);
        final typeName = rm['room_type']?.toString() ?? rm['type']?.toString() ?? 'Standard';
        final vacant   = int.tryParse(rm['available_beds']?.toString() ?? rm['available_rooms']?.toString() ?? '0') ?? 0;
        final amount   = num.tryParse(rm['amount']?.toString() ?? '0') ?? 0;
        if (!byType.containsKey(typeName)) {
          byType[typeName] = {
            'name': typeName,
            'room_type': typeName,
            'beds_free': 0,
            'fee': amount,
            'rooms': <Map<String, dynamic>>[],
          };
        }
        byType[typeName]!['beds_free'] = (byType[typeName]!['beds_free'] as int) + vacant;
        (byType[typeName]!['rooms'] as List).add({
          'room_code': rm['room_number']?.toString() ?? rm['room_code']?.toString() ?? '',
          'beds_free': vacant,
          'floor':     rm['floor']?.toString() ?? '',
          'room_id':   rm['id']?.toString() ?? '',
        });
      }

      final types = byType.values.where((t) => (t['beds_free'] as int) > 0).toList();
      if (mounted) setState(() => _roomTypeOptions = types);
    } catch (e) {
      debugPrint('Error loading room types for $hostelName: $e');
      if (mounted) setState(() => _roomTypeOptions = []);
    } finally {
      if (mounted) setState(() => _isLoadingRoomTypes = false);
    }
  }


  Future<void> _submitTransferRequest() async {
    final user = context.read<UserProvider>();
    if (_selectedHostel == null || _selectedRoomType == null) return;

    setState(() => _isSubmitting = true);

    try {
      final destHostel = (_selectedHostel!['hostel_name'] ?? _selectedHostel!['name'] ?? '').toString();
      final requestedRoomType = (_selectedRoomType!['room_type'] ?? _selectedRoomType!['name'] ?? '').toString();
      String allocatedRoom = _selectedRoom?['room_code']?.toString() ??
          _selectedRoom?['room_number']?.toString() ??
          _selectedRoomType!['allocated_room']?.toString() ??
          '';
      if (allocatedRoom.isEmpty || allocatedRoom == '0' || allocatedRoom == 'null') {
        allocatedRoom = requestedRoomType;
      }
      
      final double currentPaidAmount = user.roomAmount > 0 ? user.roomAmount : 70000.0;
      final num newRoomAmount = (_selectedRoomType?['amount'] ?? _selectedRoomType?['fee'] ?? 0) as num;
      final double extraFee = (newRoomAmount > currentPaidAmount) ? (newRoomAmount - currentPaidAmount).toDouble() : 0.0;

      final reason = _reasonController.text.trim().isNotEmpty
          ? _reasonController.text.trim()
          : "Hostel Room Transfer Request";

      final currentRoomStr = user.roomNumber.isNotEmpty ? user.roomNumber : (user.roomAllocation.isNotEmpty ? user.roomAllocation : "N/A");
      final studentId = user.dbId ?? 1;

      final res = await ApiService.submitRoomChangeRequest(
        studentId: studentId,
        currentRoom: currentRoomStr,
        requestedRoom: allocatedRoom,
        reason: "Transfer to $destHostel ($requestedRoomType) - $reason",
        requestedRoomType: requestedRoomType,
        destinationHostel: destHostel,
        amountToPay: extraFee,
      );

      if (res['success'] == true || res['status'] == 'success') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✓ Room transfer request submitted! Pending warden approval."),
              backgroundColor: Color(0xFF43A047),
              duration: Duration(seconds: 4),
            ),
          );
          Navigator.pop(context);
          widget.onSubmitted();
        }
      } else {
        throw Exception(res['message'] ?? "Submission failed");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Submission Error: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    WallpaperProvider? wallpaper;
    try {
      wallpaper = context.watch<WallpaperProvider>();
    } catch (_) {}
    final isDark = wallpaper?.isDarkTheme ?? false;

    final user = context.watch<UserProvider>();
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final bottomPadding = mediaQuery.padding.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: mediaQuery.size.height * 0.90,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE8E4DB),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
            border: isDark ? Border.all(color: Colors.white.withOpacity(0.14)) : null,
          ),
          child: SafeArea(
            top: false,
            bottom: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFE0D8CC),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        color: isDark ? const Color(0xFFEBC15B) : const Color(0xFF1A2744),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Hostel Room Transfer',
                        style: GoogleFonts.lato(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1A2744),
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close, size: 18, color: isDark ? Colors.white70 : Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),

                // Content Area
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + (bottomPadding > 0 ? bottomPadding : 16)),
                    child: _buildCurrentStepView(user, isDark),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStepView(UserProvider user, bool isDark) {
    switch (_currentStep) {
      case 1:
        return _buildStep1CurrentRoomView(user, isDark);
      case 2:
        return _buildStep2HostelSelectionView(isDark);
      case 3:
        return _buildStep3RoomTypeSelectionView(isDark);
      case 4:
        return _buildStep4RoomSelectionView(isDark);
      case 5:
        return _buildStep5ReviewAndSubmitView(user, isDark);
      default:
        return _buildStep2HostelSelectionView(isDark);
    }
  }

  // STEP 1: Current Room View
  Widget _buildStep1CurrentRoomView(UserProvider user, bool isDark) {
    final currentRoomNo = user.roomNumber.isNotEmpty ? user.roomNumber : "T-32 F02- W0-R16";
    final currentRoomType = user.roomTypeDisplay.isNotEmpty ? user.roomTypeDisplay : "4 IN 1 AC";
    final currentHostel = user.hostelName.isNotEmpty ? user.hostelName : "Vaigai Hostel";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'YOUR CURRENT ROOM',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color: isDark ? Colors.white60 : Colors.grey,
          ),
        ),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: isDark ? Border.all(color: Colors.white.withOpacity(0.14)) : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.king_bed_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentRoomType,
                          style: GoogleFonts.lato(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF1A2744),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$currentHostel · Thandalam Campus',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white70 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: isDark ? Colors.white.withOpacity(0.12) : Colors.grey.shade200),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Room No',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white60 : Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    currentRoomNo,
                    style: GoogleFonts.lato(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFF34D399) : const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () {
              setState(() => _currentStep = 2);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.sync, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Request a Room Transfer',
                  style: GoogleFonts.lato(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // STEP 2: Choose Destination Hostel (Image 2)
  Widget _buildStep2HostelSelectionView(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back Button
        InkWell(
          onTap: () {
            if (widget.initialStep == 2) {
              Navigator.pop(context);
            } else {
              setState(() => _currentStep = 1);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.14) : Colors.grey.shade300,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chevron_left, size: 18, color: isDark ? Colors.white : const Color(0xFF1A2744)),
                const SizedBox(width: 4),
                Text(
                  'Back',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1A2744),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Choose a destination hostel',
          style: GoogleFonts.lato(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF1A2744),
          ),
        ),
        const SizedBox(height: 16),

        // ── Loading / error / empty states ───────────────────────────────
        if (_isLoadingHostels)
          const Center(child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ))
        else if (_hostelLoadError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Column(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 40),
                const SizedBox(height: 8),
                Text('Could not load hostels', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: _loadHostelsFromApi,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            )),
          )
        else if (_hostelOptions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('No eligible hostels with available rooms.',
                style: TextStyle(color: isDark ? Colors.white60 : Colors.grey))),
          )
        else
          // ── Hostels List (live data) ─────────────────────────────────────
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _hostelOptions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final hostel = _hostelOptions[index];
              final name          = (hostel['hostel_name'] ?? hostel['name'] ?? '').toString();
              final bedsFree      = hostel['available_rooms'] ?? 0;
              final roomTypeCount = hostel['room_type_count'] ?? hostel['room_types_count'] ?? 0;

              return InkWell(
                onTap: () async {
                  setState(() {
                    _selectedHostel = hostel;
                    _currentStep = 3;
                  });
                  await _loadRoomTypesForHostel(hostel);
                },
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: isDark ? Border.all(color: Colors.white.withOpacity(0.14)) : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: GoogleFonts.lato(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF1A2744),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  '$bedsFree beds free',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? const Color(0xFF34D399) : const Color(0xFF10B981),
                                  ),
                                ),
                                if (roomTypeCount > 0)
                                  Text(
                                    '  ·  $roomTypeCount room types',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? Colors.white70 : Colors.grey.shade600,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: isDark ? Colors.white60 : Colors.grey, size: 22),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // STEP 3: Choose Room Type in Hostel
  Widget _buildStep3RoomTypeSelectionView(bool isDark) {
    final hostelName = _selectedHostel?['hostel_name'] ?? _selectedHostel?['name'] ?? 'Hostel';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back Button
        InkWell(
          onTap: () => setState(() => _currentStep = 2),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white.withOpacity(0.14) : Colors.grey.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chevron_left, size: 18, color: isDark ? Colors.white : const Color(0xFF1A2744)),
                const SizedBox(width: 4),
                Text(
                  'Back',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1A2744),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Choose a room type in $hostelName',
          style: GoogleFonts.lato(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF1A2744),
          ),
        ),
        const SizedBox(height: 16),

        // ── Loading state while room types are fetched ───────────────────
        if (_isLoadingRoomTypes)
          const Center(child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ))
        else if (_roomTypeOptions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No available room types found.',
                style: TextStyle(color: isDark ? Colors.white60 : Colors.grey))),
          )
        else
        // Room Types List
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _roomTypeOptions.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final user = context.read<UserProvider>();
            final roomType = _roomTypeOptions[index];
            final typeName = (roomType['room_type'] ?? roomType['name'] ?? '').toString();
            final bedsFree = roomType['beds_free'] ?? 0;
            final num newAmount = (roomType['amount'] ?? roomType['fee'] ?? 0) as num;
            final double currentPaidAmount = user.roomAmount > 0 ? user.roomAmount : 70000.0;

            final bool isUpgrade = newAmount > currentPaidAmount;
            final num extraFee = isUpgrade ? (newAmount - currentPaidAmount) : 0;
            final String feeFormatted = NumberFormat('#,##,###').format(extraFee.toInt());

            return InkWell(
              onTap: () {
                setState(() {
                  _selectedRoomType = roomType;
                  _roomOptions = List<Map<String, dynamic>>.from(roomType['rooms'] ?? []);
                  _currentStep = 4;
                });
              },
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isUpgrade
                        ? const Color(0xFF3B82F6).withOpacity(0.5)
                        : (isDark ? Colors.white.withOpacity(0.14) : Colors.grey.shade200),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            typeName,
                            style: GoogleFonts.lato(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF1A2744),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$bedsFree ${bedsFree == 1 ? 'bed' : 'beds'} free',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFF34D399) : const Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (isUpgrade) ...[
                          Text(
                            'Upgrade',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white60 : Colors.grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '+₹$feeFormatted',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF3B82F6),
                            ),
                          ),
                        ] else ...[
                          const Text(
                            'No additional fee',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // STEP 4: Choose Room in Hostel · Room Type
  Widget _buildStep4RoomSelectionView(bool isDark) {
    final hostelName = _selectedHostel?['hostel_name'] ?? _selectedHostel?['name'] ?? 'Hostel';
    final typeName = _selectedRoomType?['room_type'] ?? _selectedRoomType?['name'] ?? 'Room Type';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back Button
        InkWell(
          onTap: () => setState(() => _currentStep = 3),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white.withOpacity(0.14) : Colors.grey.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chevron_left, size: 18, color: isDark ? Colors.white : const Color(0xFF1A2744)),
                const SizedBox(width: 4),
                Text(
                  'Back',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1A2744),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Choose a room in $hostelName · $typeName',
          style: GoogleFonts.lato(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white70 : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 16),

        // Specific Rooms List
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _roomOptions.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final room = _roomOptions[index];
            final roomCode = (room['room_code'] ?? room['room_number'] ?? '').toString();
            final bedsFree = room['beds_free'] ?? 1;

            return InkWell(
              onTap: () {
                setState(() {
                  _selectedRoom = room;
                  _currentStep = 5;
                });
              },
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF3B82F6).withOpacity(isDark ? 0.4 : 0.2), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      roomCode,
                      style: GoogleFonts.lato(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF1A2744),
                      ),
                    ),
                    Text(
                      '$bedsFree ${bedsFree == 1 ? 'bed' : 'beds'} free',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFF34D399) : const Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // STEP 5: Review and Submit
  Widget _buildStep5ReviewAndSubmitView(UserProvider user, bool isDark) {
    final currentRoomNo = user.roomNumber.isNotEmpty ? user.roomNumber : "T-32 F02- W0-R16";
    final currentRoomType = user.roomTypeDisplay.isNotEmpty ? user.roomTypeDisplay : "4 IN 1 AC";
    final currentHostel = user.hostelName.isNotEmpty ? user.hostelName : "Vaigai Hostel";
    final double currentPaidAmount = user.roomAmount > 0 ? user.roomAmount : 70000.0;

    final destHostelName = _selectedHostel?['hostel_name'] ?? _selectedHostel?['name'] ?? "Hostel";
    final destTypeName = _selectedRoomType?['room_type'] ?? _selectedRoomType?['name'] ?? "Room Type";
    final destAllocatedRoom = (_selectedRoom?['room_code'] ?? _selectedRoom?['room_number'] ?? _selectedRoomType?['allocated_room'] ?? "T19-F04-W01-R13").toString();
    final num newRoomAmount = (_selectedRoomType?['amount'] ?? _selectedRoomType?['fee'] ?? 0) as num;

    final bool isUpgrade = newRoomAmount > currentPaidAmount;
    final num extraFee = isUpgrade ? (newRoomAmount - currentPaidAmount) : 0;
    final String currentPaidFormatted = NumberFormat('#,##,###').format(currentPaidAmount.toInt());
    final String newAmountFormatted = NumberFormat('#,##,###').format(newRoomAmount.toInt());
    final String extraFeeFormatted = NumberFormat('#,##,###').format(extraFee.toInt());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back Button
        InkWell(
          onTap: () => setState(() => _currentStep = 4),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white.withOpacity(0.14) : Colors.grey.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chevron_left, size: 18, color: isDark ? Colors.white : const Color(0xFF1A2744)),
                const SizedBox(width: 4),
                Text(
                  'Back',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1A2744),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Transfer Summary Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: isDark ? Border.all(color: Colors.white.withOpacity(0.14)) : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // FROM SECTION
              Text(
                'CURRENT ROOM',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white60 : Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$currentHostel · Room $currentRoomNo',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1A2744),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$currentRoomType (Paid: ₹$currentPaidFormatted)',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
              ),

              const SizedBox(height: 12),
              Icon(Icons.arrow_downward_rounded, color: isDark ? Colors.white60 : Colors.grey, size: 20),
              const SizedBox(height: 12),

              // TO SECTION
              const Text(
                'REQUESTED ROOM',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3B82F6),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$destHostelName · Room $destAllocatedRoom',
                style: GoogleFonts.lato(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1A2744),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$destTypeName (Rate: ₹$newAmountFormatted)',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
              ),

              const SizedBox(height: 16),
              Divider(color: isDark ? Colors.white.withOpacity(0.12) : Colors.grey.shade200),
              const SizedBox(height: 12),

              // UPGRADE / ADDITIONAL FEE
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Additional Amount',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF1A2744)),
                  ),
                  if (isUpgrade)
                    Text(
                      '₹$extraFeeFormatted',
                      style: GoogleFonts.lato(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF3B82F6),
                      ),
                    )
                  else
                    const Text(
                      'No additional fee',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Reason Input Field
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.14) : Colors.grey.shade300),
          ),
          child: TextField(
            controller: _reasonController,
            maxLines: 3,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: 'Reason for transfer (optional)',
              hintStyle: TextStyle(color: isDark ? Colors.white60 : Colors.grey, fontSize: 14),
              border: InputBorder.none,
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Submit Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submitTransferRequest,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check, size: 20, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        'Submit Transfer Request',
                        style: GoogleFonts.lato(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
