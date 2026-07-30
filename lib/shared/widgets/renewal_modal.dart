import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../user_provider.dart';
import '../../student/screens/upgrade_room_screen.dart';
import '../../student/screens/payment_screens.dart';

// ─────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────
class RoomType {
  final String id;
  final String name;
  final double hostelFee;
  final double foodFee;
  final double totalFee;
  final double monthlyAmount;
  final String description;

  /// backward-compat alias
  double get sixMonthAmount => hostelFee;

  const RoomType({
    required this.id,
    required this.name,
    required this.hostelFee,
    required this.foodFee,
    required this.totalFee,
    required this.monthlyAmount,
    required this.description,
  });
}

class FeeBreakdown {
  final double hostelFee;
  final double foodFee;
  final double total;
  final String selectedRoomName;
  final double alreadyPaid;
  final bool isUpgradePayment;

  FeeBreakdown({
    required this.hostelFee,
    required this.foodFee,
    required this.total,
    required this.selectedRoomName,
    this.alreadyPaid = 0.0,
    this.isUpgradePayment = false,
  });
}

// ─────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────
class RenewalModal extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final DateTime currentRenewalDate;
  final String currentRoomTypeId;
  final Function(DateTime newDate, String receiptNumber, double amount,
      String newRoomType) onRenewalSuccess;
  final VoidCallback? onRoomChangeRequested;
  final String requestStatus; // 'pending' | 'approved' | 'rejected' | 'none'
  final String? approvedRoomType;
  final String currentRoomFacility;
  final String currentRoomBathAttached;
  final String? requestId;

  const RenewalModal({
    super.key,
    this.isOpen = true,
    required this.onClose,
    required this.currentRenewalDate,
    this.currentRoomTypeId = '8-sharing',
    this.currentRoomFacility = 'NON AC',
    this.currentRoomBathAttached = 'No',
    required this.onRenewalSuccess,
    this.onRoomChangeRequested,
    this.requestStatus = 'none',
    this.approvedRoomType,
    this.requestId,
  });

  @override
  State<RenewalModal> createState() => _RenewalModalState();
}

class _RenewalModalState extends State<RenewalModal> {
  String _selectedRoomId = '';
  bool _isProcessing = false;
  bool _isLoading = true;
  List<RoomType> _roomTypes = [];
  int _selectedDays = 5;
  bool _showPlanSelector = false;

  // ── number formatter ──────────────────────────────────────────────────────
  final _fmt = NumberFormat('#,##,##0', 'en_IN');
  String _rupees(double v) => '₹${_fmt.format(v.round())}';

  // ── colours ───────────────────────────────────────────────────────────────
  static const _navy = Color(0xFF1A2744);
  static const _gold = Color(0xFFD4AF37);
  static const _currentBlue = Color(0xFF1565C0);
  static const _currentBlueBg = Color(0xFFE3F2FD);
  static const _currentBlueBorder = Color(0xFF90CAF9);

  @override
  void initState() {
    super.initState();
    _selectedRoomId =
        widget.approvedRoomType ?? widget.currentRoomTypeId.trim();
    // Defer fetch so Provider can be accessed safely after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchRoomTypes());

    final user = Provider.of<UserProvider>(context, listen: false);
    if (user.temporaryStayRequest != null) {
      final req = user.temporaryStayRequest!;
      _selectedDays = int.tryParse(req['duration_value']?.toString() ?? '5') ?? 5;
    }
  }

  // ── fetch ─────────────────────────────────────────────────────────────────
  Future<void> _fetchRoomTypes() async {
    try {
      final user = Provider.of<UserProvider>(context, listen: false);
      final response =
          await ApiService.getRoomTypes(username: user.displayStudentId);
      if (response['status'] == 'success') {
        final List<dynamic> data = response['data'];
        final types = data.asMap().entries.map((entry) {
          final i = entry.key;
          final j = entry.value;
          final roomId =
              j['room_code']?.toString() ?? j['name']?.toString() ?? 'room_$i';
          return RoomType(
            id: roomId,
            name: j['name']?.toString() ?? 'Standard Room',
            hostelFee: (j['hostel_fee'] as num?)?.toDouble() ??
                (j['six_month_amount'] as num?)?.toDouble() ??
                0.0,
            foodFee: (j['food_fee'] as num?)?.toDouble() ?? 50000.0,
            totalFee: (j['total_fee'] as num?)?.toDouble() ?? 0.0,
            monthlyAmount:
                (j['monthly_amount'] as num?)?.toDouble() ?? 2000.0,
            description:
                j['description']?.toString() ?? 'No description available',
          );
        }).toList();

        setState(() {
          _roomTypes = types;
          _isLoading = false;

          // resolve selected id
          final wantId =
              (widget.approvedRoomType ?? widget.currentRoomTypeId).trim();
          final found = types.any(
              (r) => r.id.trim().toLowerCase() == wantId.toLowerCase());
          if (found) {
            _selectedRoomId = wantId;
          } else if (types.isNotEmpty) {
            _selectedRoomId = types.first.id;
          }
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching room types: $e');
      setState(() => _isLoading = false);
    }
  }

  // ── helpers ───────────────────────────────────────────────────────────────
  RoomType? get _currentRoom {
    final cid = widget.currentRoomTypeId.trim().toLowerCase();
    try {
      return _roomTypes
          .firstWhere((r) => r.id.trim().toLowerCase() == cid);
    } catch (_) {
      // fuzzy fallback
      try {
        return _roomTypes.firstWhere((r) =>
            r.name.toLowerCase().contains(cid) ||
            cid.contains(r.name.toLowerCase()));
      } catch (_) {
        return _roomTypes.isNotEmpty ? _roomTypes.first : null;
      }
    }
  }

  RoomType? get _selectedRoom {
    final sid = _selectedRoomId.trim().toLowerCase();
    try {
      return _roomTypes.firstWhere((r) => r.id.trim().toLowerCase() == sid);
    } catch (_) {
      return _currentRoom;
    }
  }

  bool _isCurrentRoom(RoomType r) =>
      r.id.trim().toLowerCase() ==
      widget.currentRoomTypeId.trim().toLowerCase();

  bool _isSelectedRoom(RoomType r) =>
      r.id.trim() == _selectedRoomId.trim();

  bool get _isPaymentDisabled {
    final s = widget.requestStatus.toLowerCase();
    if (s == 'pending') return true;
    if (s == 'approved') {
      return _selectedRoomId.trim().toLowerCase() !=
          (widget.approvedRoomType?.trim().toLowerCase() ?? '');
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!widget.isOpen) return const SizedBox.shrink();
    final String upgradeUsername = Provider.of<UserProvider>(context, listen: false).displayStudentId;
    final user = Provider.of<UserProvider>(context);
    final bool isTemporary = user.temporaryStayRequest != null;

    if (_isLoading && !isTemporary) {
      return Container(
        height: 300,
        decoration: const BoxDecoration(
          color: Color(0xFFF9F6F0),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _gold),
              SizedBox(height: 16),
              Text('Loading room types…',
                  style: TextStyle(color: Colors.grey, fontSize: 14)),
            ],
          ),
        ),
      );
    }

    final currentDate = widget.currentRenewalDate;
    
    if (isTemporary) {
      final newDate = currentDate.add(Duration(days: _selectedDays));
      final req = user.temporaryStayRequest!;
      final double originalAmount = (req['amount'] != null) ? double.tryParse(req['amount'].toString()) ?? 0.0 : 0.0;
      final int durationVal = (req['duration_value'] != null) ? int.tryParse(req['duration_value'].toString()) ?? 1 : 1;
      final double dailyRate = durationVal > 0 ? (originalAmount / durationVal) : 0.0;
      final double totalToPay = dailyRate * _selectedDays;

      final fees = FeeBreakdown(
        hostelFee: totalToPay,
        foodFee: 0,
        total: totalToPay,
        selectedRoomName: user.roomAllocation,
      );

      return Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxWidth: 580,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFFF9F6F0),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
                color: Colors.black26, blurRadius: 30, offset: Offset(0, -8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(upgradeUsername),
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildExpiryDates(currentDate, newDate),
                    const SizedBox(height: 20),
                    
                    // Stay details card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE8E0D5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Stay Details',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _navy),
                          ),
                          const SizedBox(height: 12),
                          _detailRow('Hostel', user.hostelName),
                          _detailRow('Room Allocated', user.roomAllocation),
                          _detailRow('Room Type', user.roomTypeDisplay),
                          _detailRow('Original Stay', '$durationVal Days'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Change Plan Button and Selector
                    !_showPlanSelector
                        ? Center(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _navy,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                              icon: const Icon(Icons.edit_calendar, size: 18),
                              label: const Text('Change Plan / Duration', style: TextStyle(fontWeight: FontWeight.bold)),
                              onPressed: () {
                                setState(() {
                                  _showPlanSelector = true;
                                });
                              },
                            ),
                          )
                        : Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFE8E0D5)),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'Select New Stay Duration',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _navy),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, color: _gold, size: 30),
                                      onPressed: () {
                                        if (_selectedDays > 1) {
                                          setState(() {
                                            _selectedDays--;
                                          });
                                        }
                                      },
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey.shade300),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '$_selectedDays Days',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _navy),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline, color: _gold, size: 30),
                                      onPressed: () {
                                        setState(() {
                                          _selectedDays++;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                    const SizedBox(height: 20),
                    
                    _buildFeeBreakdownTemp(fees, dailyRate, _selectedDays),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            _buildFooter(fees.total, newDate, fees.selectedRoomName),
          ],
        ),
      );
    }

    final newDate =
        DateTime(currentDate.year, currentDate.month + 12, currentDate.day);

    final sel = _selectedRoom;
    final status = widget.requestStatus.toLowerCase();
    
    // Check if we are paying for an approved room change/upgrade
    final bool isApprovedRoomChange = (status == 'pre_approved' || status == 'approved') && 
        widget.approvedRoomType != null &&
        sel != null &&
        sel.id.trim().toLowerCase() == widget.approvedRoomType!.trim().toLowerCase();
        
    final double currentFee = _currentRoom?.hostelFee ?? 0.0;
    double totalToPay = sel?.hostelFee ?? 0.0;
    double alreadyPaid = 0.0;
    
    if (isApprovedRoomChange) {
      final double diff = totalToPay - currentFee;
      if (diff > 0) {
        alreadyPaid = currentFee;
        totalToPay = diff;
      } else {
        totalToPay = 0;
      }
    }

    final fees = sel != null
        ? FeeBreakdown(
            hostelFee: sel.hostelFee,
            foodFee: sel.foodFee,
            total: totalToPay, 
            selectedRoomName: sel.name,
            alreadyPaid: alreadyPaid,
            isUpgradePayment: isApprovedRoomChange,
          )
        : FeeBreakdown(hostelFee: 0, foodFee: 0, total: 0, selectedRoomName: '');

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxWidth: 580,
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF9F6F0),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
              color: Colors.black26, blurRadius: 30, offset: Offset(0, -8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(upgradeUsername),
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildExpiryDates(currentDate, newDate),
                  const SizedBox(height: 20),
                  _buildFeeBreakdown(fees),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          _buildFooter(fees.total, newDate, fees.selectedRoomName),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(String upgradeUsername) {
    final status = widget.requestStatus.toLowerCase();
    final user = Provider.of<UserProvider>(context, listen: false);
    final bool isTemporary = user.temporaryStayRequest != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 20, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        border: Border(bottom: BorderSide(color: Color(0xFFE0D8CC))),
      ),
      child: Column(
        children: [
          // drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                isTemporary ? 'Renew Temporary Stay' : 'Renew',
                style: const TextStyle(
                  color: _navy,
                  fontFamily: 'Lato',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              // action buttons
              Row(
                children: [
                  if (!isTemporary) ...[
                    if (widget.onRoomChangeRequested != null)
                      _headerBtn(
                        label: 'Room Change',
                        icon: Icons.swap_horiz,
                        onTap: (status == 'approved' || status == 'pre_approved')
                            ? null
                            : widget.onRoomChangeRequested,
                      ),
                    const SizedBox(width: 8),
                    _headerBtn(
                      label: 'Upgrade',
                      icon: Icons.auto_awesome,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UpgradeRoomScreen(
                              currentRoomTypeId: widget.currentRoomTypeId,
                              username: upgradeUsername,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                  GestureDetector(
                    onTap: widget.onClose,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.grey, size: 20),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              isTemporary
                  ? 'Renew your temporary stay at your current room'
                  : 'Select your room type for renewal',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          // status banner
          if (!isTemporary && (status == 'pending' || status == 'approved' || status == 'pre_approved'))
            _buildStatusBanner(status),
        ],
      ),
    );
  }

  Widget _headerBtn(
      {required String label,
      required IconData icon,
      VoidCallback? onTap}) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: _navy,
        side: const BorderSide(color: _gold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: const Size(0, 32),
        textStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        elevation: 0,
      ),
    );
  }

  Widget _buildStatusBanner(String status) {
    final isPending = status == 'pending';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isPending
            ? const Color(0xFFFFF8E1)
            : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPending
              ? const Color(0xFFFFE082)
              : const Color(0xFFA5D6A7),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPending ? Icons.hourglass_top_rounded : Icons.check_circle,
            size: 16,
            color: isPending
                ? const Color(0xFFF57F17)
                : const Color(0xFF2E7D32),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isPending
                  ? 'Your room change request is pending approval.'
                  : 'Room change approved! Pay the difference to upgrade.',
              style: TextStyle(
                fontSize: 12,
                color: isPending
                    ? const Color(0xFFF57F17)
                    : const Color(0xFF2E7D32),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Date boxes ────────────────────────────────────────────────────────────
  Widget _buildExpiryDates(DateTime currentDate, DateTime newDate) {
    return Row(
      children: [
        Expanded(
          child: _buildDateBox(
            'Current Expiry',
            DateFormat('dd MMM yyyy').format(currentDate),
            const Color(0xFFF3EFE9),
            Colors.grey,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildDateBox(
            'New Expiry',
            DateFormat('dd MMM yyyy').format(newDate),
            const Color(0xFFE2F0E5),
            const Color(0xFF2E7D32),
          ),
        ),
      ],
    );
  }

  Widget _buildDateBox(
      String label, String date, Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 13, color: textColor.withOpacity(0.6)),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: textColor.withOpacity(0.6))),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            date,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: _navy),
          ),
        ],
      ),
    );
  }

  // ── Section title ─────────────────────────────────────────────────────────
  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _navy.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${_roomTypes.length} types',
            style: const TextStyle(
                fontSize: 10,
                color: _navy,
                fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ── Legend ────────────────────────────────────────────────────────────────
  Widget _buildRoomLegend() {
    return Row(
      children: [
        _legendDot(_currentBlue, 'Your Current Room'),
        const SizedBox(width: 16),
        _legendDot(_gold, 'Selected'),
      ],
    );
  }

  Widget _legendDot(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  // ── Room Card ─────────────────────────────────────────────────────────────
  Widget _buildRoomCard(RoomType room) {
    final isCurrent = _isCurrentRoom(room);
    final isSelected = _isSelectedRoom(room);

    // styling logic
    Color bg = Colors.white;
    Color borderColor = const Color(0xFFE8E0D5);
    double borderWidth = 1;

    if (isCurrent && isSelected) {
      bg = _currentBlueBg;
      borderColor = _currentBlue;
      borderWidth = 2;
    } else if (isCurrent) {
      bg = _currentBlueBg.withOpacity(0.6);
      borderColor = _currentBlueBorder;
      borderWidth = 1.5;
    } else if (isSelected) {
      bg = const Color(0xFFFFF9C4).withOpacity(0.5);
      borderColor = _gold;
      borderWidth = 2;
    }

    return GestureDetector(
      onTap: () => setState(() => _selectedRoomId = room.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (isCurrent ? _currentBlue : _gold)
                        .withOpacity(0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            // ── selection indicator ──────────────────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? (isCurrent ? _currentBlue : _gold)
                      : Colors.grey.shade300,
                  width: 2,
                ),
                color: isSelected
                    ? (isCurrent ? _currentBlue : _gold)
                    : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check,
                      size: 12, color: Colors.white)
                  : null,
            ),
            // ── room info ────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          room.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? _navy : Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (isCurrent)
                        _tag('Your Room', _currentBlue, Colors.white),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    room.description,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // ── fee info ─────────────────────────────────────────────
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _rupees(room.hostelFee),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isCurrent ? _currentBlue : _gold,
                  ),
                ),
                Text(
                  'Hostel / year',
                  style:
                      TextStyle(fontSize: 9, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(label,
          style: TextStyle(
              color: fg, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  // ── Fee Breakdown ─────────────────────────────────────────────────────────
  Widget _buildFeeBreakdown(FeeBreakdown fees) {
    if (_selectedRoom == null) return const SizedBox.shrink();

    final sel = _selectedRoom!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8E0D5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined,
                  size: 16, color: _navy),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fees.isUpgradePayment ? 'Upgrade Fee Breakdown' : 'Fee Breakdown – ${sel.name}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _navy),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _feeRow('New Hostel Fee', sel.hostelFee,
              sub: 'New room type annual fee'),
          if (fees.isUpgradePayment && fees.alreadyPaid > 0) ...[
            const SizedBox(height: 8),
            _feeRow('Already Paid (Current Room)', -fees.alreadyPaid,
                sub: 'Deducted from previous allocation'),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: Color(0xFFE8E0D5), height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Amount to Pay',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: _navy)),
              Text(
                _rupees(fees.total),
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: _gold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _feeRow(String label, double amount, {String? sub}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Colors.black87)),
            if (sub != null)
              Text(sub,
                  style: const TextStyle(
                      fontSize: 10, color: Colors.grey)),
          ],
        ),
        Text(
          _rupees(amount),
          style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.black87),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: _navy)),
        ],
      ),
    );
  }

  Widget _buildFeeBreakdownTemp(FeeBreakdown fees, double dailyRate, int days) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8E0D5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, size: 16, color: _navy),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Fee Breakdown',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _navy),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _feeRow('Daily Room Rate', dailyRate, sub: 'Calculated from original stay amount'),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Days of Stay', style: TextStyle(fontSize: 13, color: Colors.black87)),
                  Text('Renewal stay duration', style: TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
              Text(
                '$days Days',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: Color(0xFFE8E0D5), height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Amount to Pay', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _navy)),
              Text(
                _rupees(fees.total),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: _gold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Footer / Pay button ───────────────────────────────────────────────────
  Widget _buildFooter(
      double totalAmount, DateTime newDate, String selectedRoomName) {
    final user = Provider.of<UserProvider>(context, listen: false);
    final bool isTemporary = user.temporaryStayRequest != null;

    if (isTemporary) {
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE8E0D5))),
        ),
        child: SafeArea(
          top: false,
          child: ElevatedButton(
            onPressed: _isProcessing
                ? null
                : () => _handlePayment(totalAmount, newDate, selectedRoomName),
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: _navy,
              disabledBackgroundColor: Colors.grey.shade200,
              disabledForegroundColor: Colors.grey.shade500,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 2,
            ),
            child: _isProcessing
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: _navy),
                  )
                : Text(
                    'Pay ${_rupees(totalAmount)}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      );
    }

    final status = widget.requestStatus.toLowerCase();
    final disabled = _isPaymentDisabled;

    String btnLabel = 'Proceed to Payment';
    if (status == 'pending') {
      btnLabel = 'Room Change Pending…';
    } else if (status == 'approved' || status == 'pre_approved') {
      if (!disabled) {
        btnLabel = 'Pay ${_rupees(totalAmount)}';
      } else {
        btnLabel = 'Select Approved Room Type';
      }
    } else {
      btnLabel = 'Pay ${_rupees(totalAmount)}';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8E0D5))),
      ),
      child: SafeArea(
        top: false,
        child: ElevatedButton(
          onPressed: (_isProcessing || disabled)
              ? null
              : () => _handlePayment(totalAmount, newDate, selectedRoomName),
          style: ElevatedButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: _navy,
            disabledBackgroundColor: Colors.grey.shade200,
            disabledForegroundColor: Colors.grey.shade500,
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            elevation: disabled ? 0 : 2,
          ),
          child: _isProcessing
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: _navy),
                )
              : Text(
                  btnLabel,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
        ),
      ),
    );
  }

  void _handlePayment(
      double totalAmount, DateTime newDate, String roomName) async {
    final user = Provider.of<UserProvider>(context, listen: false);
    final bool isTemporary = user.temporaryStayRequest != null;

    if (isTemporary) {
      final req = user.temporaryStayRequest!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentPage(
            requestId: req['request_id'],
            requestedRoom: req['room_code'] ?? req['room_no'] ?? roomName,
            customAmount: totalAmount,
            isTemporaryStay: true,
            renewDays: _selectedDays,
            renewAmount: totalAmount,
          ),
        ),
      ).then((_) {
        widget.onClose();
      });
      return;
    }

    final status = widget.requestStatus.toLowerCase();
    if (status == 'pre_approved' || status == 'approved') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentPage(
            requestId: widget.requestId,
            requestedRoom: widget.approvedRoomType ?? roomName,
            customAmount: totalAmount,
          ),
        ),
      ).then((_) {
        widget.onClose();
      });
      return;
    }

    setState(() => _isProcessing = true);
    await Future.delayed(const Duration(seconds: 2));
    widget.onRenewalSuccess(
        newDate,
        'RCP${DateTime.now().millisecondsSinceEpoch}',
        totalAmount,
        roomName);
    setState(() => _isProcessing = false);
    widget.onClose();
  }
}

// ─────────────────────────────────────────────
// Show helper
// ─────────────────────────────────────────────
void showRenewalModal({
  required BuildContext context,
  required DateTime currentRenewalDate,
  required String currentRoomTypeId,
  String currentRoomFacility = 'NON AC',
  String currentRoomBathAttached = 'No',
  VoidCallback? onRoomChangeRequested,
  String requestStatus = 'none',
  String? approvedRoomType,
  required Function(DateTime, String, double, String) onRenewalSuccess,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => RenewalModal(
      isOpen: true,
      currentRenewalDate: currentRenewalDate,
      currentRoomTypeId: currentRoomTypeId,
      currentRoomFacility: currentRoomFacility,
      currentRoomBathAttached: currentRoomBathAttached,
      onRoomChangeRequested: onRoomChangeRequested,
      requestStatus: requestStatus,
      approvedRoomType: approvedRoomType,
      onRenewalSuccess: onRenewalSuccess,
      onClose: () => Navigator.pop(context),
    ),
  );
}
