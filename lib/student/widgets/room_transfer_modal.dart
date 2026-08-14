import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/api_service.dart';
import '../../shared/user_provider.dart';

class StudentRoomTransferModal extends StatefulWidget {
  final VoidCallback onSubmitted;

  const StudentRoomTransferModal({
    super.key,
    required this.onSubmitted,
  });

  static void show(BuildContext context, {required VoidCallback onSubmitted}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StudentRoomTransferModal(onSubmitted: onSubmitted),
    );
  }

  @override
  State<StudentRoomTransferModal> createState() => _StudentRoomTransferModalState();
}

class _StudentRoomTransferModalState extends State<StudentRoomTransferModal> {
  int _currentStep = 1; // Step 1: Current Room, Step 2: Destination Hostel, Step 3: Room Type, Step 4: Reason/Submit
  bool _isSubmitting = false;

  // Selection state
  Map<String, dynamic>? _selectedHostel;
  Map<String, dynamic>? _selectedRoomType;
  final TextEditingController _reasonController = TextEditingController();

  // Hardcoded hostel & room type options matched by gender
  List<Map<String, dynamic>> _hostelOptions = [];
  List<Map<String, dynamic>> _roomTypeOptions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initHostelsForGender();
    });
  }

  void _initHostelsForGender() {
    final user = context.read<UserProvider>();
    final isGirls = user.hostelType.toLowerCase().contains('female') ||
        user.hostelType.toLowerCase().contains('girl') ||
        user.hostelName.toLowerCase().contains('vaigai') ||
        user.hostelName.toLowerCase().contains('ponni') ||
        user.hostelName.toLowerCase().contains('porunai');

    if (isGirls) {
      _hostelOptions = [
        {
          'name': 'Porunai Hostel',
          'beds_free': 68,
          'room_types_count': 2,
          'types': [
            {
              'name': 'Super Deluxe 3 IN 1 Bath Attached AC',
              'beds_free': 4,
              'fee': 40000,
              'allocated_room': 'T19-F04-W01-R13',
            },
            {
              'name': 'Super Deluxe 4 IN 1 Bath Attached AC',
              'beds_free': 64,
              'fee': 25000,
              'allocated_room': 'T19-F03-W02-R08',
            },
          ]
        },
        {
          'name': 'Vaigai Hostel',
          'beds_free': 833,
          'room_types_count': 9,
          'types': [
            {
              'name': 'Super Deluxe 3 IN 1 Bath Attached AC',
              'beds_free': 18,
              'fee': 40000,
              'allocated_room': 'T-32 F04- W01-R05',
            },
            {
              'name': '4 IN 1 AC',
              'beds_free': 142,
              'fee': 0,
              'allocated_room': 'T-32 F03- W0-R12',
            },
            {
              'name': 'Standard 6 IN 1 AC',
              'beds_free': 210,
              'fee': -10000,
              'allocated_room': 'T-32 F01- W0-R02',
            },
          ]
        },
        {
          'name': 'Ponni Hostel',
          'beds_free': 145,
          'room_types_count': 3,
          'types': [
            {
              'name': 'Deluxe 4 IN 1 AC',
              'beds_free': 45,
              'fee': 15000,
              'allocated_room': 'P-02 F03- W01-R10',
            },
            {
              'name': 'Standard 4 IN 1 Non AC',
              'beds_free': 100,
              'fee': -20000,
              'allocated_room': 'P-02 F01- W01-R04',
            },
          ]
        },
        {
          'name': 'Radiance Inn',
          'beds_free': 88,
          'room_types_count': 2,
          'types': [
            {
              'name': 'Premium Suite 2 IN 1 AC',
              'beds_free': 12,
              'fee': 60000,
              'allocated_room': 'RAD-F02-R04',
            },
            {
              'name': 'Deluxe 3 IN 1 AC',
              'beds_free': 76,
              'fee': 35000,
              'allocated_room': 'RAD-F01-R10',
            },
          ]
        },
      ];
    } else {
      // Boys Hostels
      _hostelOptions = [
        {
          'name': 'Krishna Hostel',
          'beds_free': 240,
          'room_types_count': 4,
          'types': [
            {
              'name': '4 IN 1 AC',
              'beds_free': 42,
              'fee': 0,
              'allocated_room': 'T-30 F02-WA0-R04',
            },
            {
              'name': 'Super Deluxe 3 IN 1 Bath Attached AC',
              'beds_free': 14,
              'fee': 35000,
              'allocated_room': 'T-30 F03-WA1-R02',
            },
            {
              'name': 'Standard 6 IN 1 AC',
              'beds_free': 184,
              'fee': -10000,
              'allocated_room': 'T-30 F01-WA0-R08',
            },
          ]
        },
        {
          'name': 'Noyyal Hostel',
          'beds_free': 115,
          'room_types_count': 3,
          'types': [
            {
              'name': 'Deluxe 4 IN 1 AC',
              'beds_free': 35,
              'fee': 20000,
              'allocated_room': 'N-04 F05-W0-R12',
            },
            {
              'name': 'Standard 4 IN 1 Non AC',
              'beds_free': 80,
              'fee': -15000,
              'allocated_room': 'N-04 F04-W0-R06',
            },
          ]
        },
        {
          'name': 'Palar Hostel',
          'beds_free': 48,
          'room_types_count': 2,
          'types': [
            {
              'name': 'Executive 2 IN 1 AC',
              'beds_free': 8,
              'fee': 50000,
              'allocated_room': 'PAL-F03-R02',
            },
            {
              'name': 'Super Deluxe 3 IN 1 AC',
              'beds_free': 40,
              'fee': 30000,
              'allocated_room': 'PAL-F02-R07',
            },
          ]
        },
        {
          'name': 'Siruvani Hostel',
          'beds_free': 310,
          'room_types_count': 5,
          'types': [
            {
              'name': '4 IN 1 AC',
              'beds_free': 85,
              'fee': 0,
              'allocated_room': 'SIR-F02-WA0-R15',
            },
            {
              'name': 'Standard 6 IN 1 AC',
              'beds_free': 225,
              'fee': -10000,
              'allocated_room': 'SIR-F01-WB0-R04',
            },
          ]
        },
      ];
    }
    setState(() {});
  }

  Future<void> _submitTransferRequest() async {
    final user = context.read<UserProvider>();
    if (_selectedHostel == null || _selectedRoomType == null) return;

    setState(() => _isSubmitting = true);

    try {
      final destHostel = _selectedHostel!['name'].toString();
      final requestedRoomType = _selectedRoomType!['name'].toString();
      String allocatedRoom = _selectedRoomType!['allocated_room']?.toString() ?? '';
      if (allocatedRoom.isEmpty || allocatedRoom == '0' || allocatedRoom == 'null') {
        allocatedRoom = _selectedRoomType!['room_code']?.toString() ?? 'T-30 F02-WA0-R04';
      }
      final fee = _selectedRoomType!['fee'] ?? 0;
      final reason = _reasonController.text.trim().isNotEmpty
          ? _reasonController.text.trim()
          : "Hostel Room Transfer Request";

      final currentRoomStr = user.roomNumber.isNotEmpty ? user.roomNumber : "N/A";

      final res = await ApiService.submitRoomChangeRequest(
        studentId: user.dbId ?? 1,
        currentRoom: currentRoomStr,
        requestedRoom: allocatedRoom,
        reason: "Transfer to $destHostel ($requestedRoomType) - $reason",
        requestedRoomType: requestedRoomType,
        destinationHostel: destHostel,
        amountToPay: fee > 0 ? (fee as num).toDouble() : 0.0,
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
    final user = context.watch<UserProvider>();
    final mediaQuery = MediaQuery.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: mediaQuery.size.height * 0.88,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFE8E4DB),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
        ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
              border: Border(
                bottom: BorderSide(color: Color(0xFFE0D8CC), width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, color: Color(0xFF1A2744), size: 22),
                const SizedBox(width: 10),
                Text(
                  'Hostel Room Transfer',
                  style: GoogleFonts.lato(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A2744),
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, size: 18, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),

          // Content Area
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildCurrentStepView(user),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildCurrentStepView(UserProvider user) {
    switch (_currentStep) {
      case 1:
        return _buildStep1CurrentRoomView(user);
      case 2:
        return _buildStep2HostelSelectionView();
      case 3:
        return _buildStep3RoomTypeSelectionView();
      case 4:
        return _buildStep4ReviewAndSubmitView(user);
      default:
        return _buildStep1CurrentRoomView(user);
    }
  }

  // STEP 1: Current Room Card View (Image 1 & 2)
  Widget _buildStep1CurrentRoomView(UserProvider user) {
    final currentRoomNo = user.roomNumber.isNotEmpty ? user.roomNumber : "T-32 F02- W0-R16";
    final currentRoomType = user.roomTypeDisplay.isNotEmpty ? user.roomTypeDisplay : "4 IN 1 AC";
    final currentHostel = user.hostelName.isNotEmpty ? user.hostelName : "Vaigai Hostel";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'YOUR CURRENT ROOM',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 12),

        // Room Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
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
                            color: const Color(0xFF1A2744),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$currentHostel · Thandalam Campus',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: Colors.grey.shade200),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Room No',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    currentRoomNo,
                    style: GoogleFonts.lato(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        // Action Button: Request a Room Transfer
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

  // STEP 2: Choose Destination Hostel (Image 3)
  Widget _buildStep2HostelSelectionView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back Button
        InkWell(
          onTap: () => setState(() => _currentStep = 1),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chevron_left, size: 18, color: Color(0xFF1A2744)),
                SizedBox(width: 4),
                Text(
                  'Back',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2744),
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
            color: const Color(0xFF1A2744),
          ),
        ),
        const SizedBox(height: 16),

        // Hostels List
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _hostelOptions.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final hostel = _hostelOptions[index];
            final name = hostel['name'].toString();
            final bedsFree = hostel['beds_free'] ?? 0;
            final roomTypesCount = hostel['room_types_count'] ?? 1;

            return InkWell(
              onTap: () {
                setState(() {
                  _selectedHostel = hostel;
                  _roomTypeOptions = List<Map<String, dynamic>>.from(hostel['types'] ?? []);
                  _currentStep = 3;
                });
              },
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
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
                              color: const Color(0xFF1A2744),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                '$bedsFree beds free',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                              Text(
                                '  ·  $roomTypesCount room types',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey, size: 22),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // STEP 3: Choose Room Type in Hostel (Image 4)
  Widget _buildStep3RoomTypeSelectionView() {
    final hostelName = _selectedHostel?['name'] ?? 'Hostel';

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
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chevron_left, size: 18, color: Color(0xFF1A2744)),
                SizedBox(width: 4),
                Text(
                  'Back',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2744),
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
            color: const Color(0xFF1A2744),
          ),
        ),
        const SizedBox(height: 16),

        // Room Types List
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _roomTypeOptions.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final roomType = _roomTypeOptions[index];
            final typeName = roomType['name'].toString();
            final bedsFree = roomType['beds_free'] ?? 0;
            final fee = roomType['fee'] ?? 0;

            final bool isUpgrade = fee > 0;
            final String feeDisplay = isUpgrade ? "+₹$fee" : "No extra";

            return InkWell(
              onTap: () {
                setState(() {
                  _selectedRoomType = roomType;
                  _currentStep = 4;
                });
              },
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
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
                              color: const Color(0xFF1A2744),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$bedsFree beds free',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (isUpgrade) ...[
                          const Text(
                            'Upgrade',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            feeDisplay,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF3B82F6),
                            ),
                          ),
                        ] else ...[
                          Text(
                            feeDisplay,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF64748B),
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

  // STEP 4: Review and Submit Reason (Image 5)
  Widget _buildStep4ReviewAndSubmitView(UserProvider user) {
    final currentRoomNo = user.roomNumber.isNotEmpty ? user.roomNumber : "T-32 F02- W0-R16";
    final currentRoomType = user.roomTypeDisplay.isNotEmpty ? user.roomTypeDisplay : "4 IN 1 AC";
    final currentHostel = user.hostelName.isNotEmpty ? user.hostelName : "Vaigai Hostel";

    final destHostelName = _selectedHostel?['name'] ?? "Porunai Hostel";
    final destTypeName = _selectedRoomType?['name'] ?? "Super Deluxe 3 IN 1 Bath Attached AC";
    final destAllocatedRoom = _selectedRoomType?['allocated_room'] ?? "T19-F04-W01-R13";
    final fee = _selectedRoomType?['fee'] ?? 40000;

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
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chevron_left, size: 18, color: Color(0xFF1A2744)),
                SizedBox(width: 4),
                Text(
                  'Back',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2744),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Transfer Summary Card (Image 5)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // FROM SECTION
              const Text(
                'FROM',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$currentHostel · $currentRoomType · Room $currentRoomNo',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),

              const SizedBox(height: 12),
              const Icon(Icons.arrow_downward_rounded, color: Colors.grey, size: 20),
              const SizedBox(height: 12),

              // TO SECTION
              const Text(
                'TO',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3B82F6),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$destHostelName · $destTypeName · Room $destAllocatedRoom',
                style: GoogleFonts.lato(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A2744),
                ),
              ),

              const SizedBox(height: 16),
              Divider(color: Colors.grey.shade200),
              const SizedBox(height: 12),

              // UPGRADE FEE
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Upgrade fee (after approval)',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  Text(
                    '₹${fee.toString().replaceAll('-', '')}',
                    style: GoogleFonts.lato(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF3B82F6),
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: TextField(
            controller: _reasonController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Reason for transfer (optional)',
              hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
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
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isSubmitting
                ? const CircularProgressIndicator(color: Colors.white)
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Submit Transfer Request',
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
}
