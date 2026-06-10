import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api_service.dart';

/// Room Type Definition
class RoomType {
  final String id;
  final String name;
  final double sixMonthAmount;
  final double monthlyAmount;
  final String description;
  final double cautionDeposit;
  final double messCharges;

  const RoomType({
    required this.id,
    required this.name,
    required this.sixMonthAmount,
    required this.monthlyAmount,
    required this.description,
    this.cautionDeposit = 5000.0,
    this.messCharges = 0.0,
  });
}

/// Room Types Available - Vaigai Hostel Configuration

/// Fee Breakdown Item
class FeeBreakdownItem {
  final String label;
  final double amount;

  FeeBreakdownItem({required this.label, required this.amount});
}

/// Renewal Modal Widget with Room Upgrade
class RenewalModal extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final DateTime currentRenewalDate;
  final String currentRoomTypeId;
  final Function(DateTime newDate, String receiptNumber, double amount, String newRoomType) onRenewalSuccess;
  final VoidCallback? onRoomChangeRequested;
  final String requestStatus; // 'pending', 'approved', 'rejected', 'none'
  final String? approvedRoomType;
  final String currentRoomFacility;
  final String currentRoomBathAttached;

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
  });

  @override
  State<RenewalModal> createState() => _RenewalModalState();
}

class _RenewalModalState extends State<RenewalModal> {
  String _selectedRoomId = '8-sharing';
  bool _isUpgrading = false;
  bool _isProcessing = false;
  bool _isLoading = true;
  List<RoomType> _dynamicRoomTypes = [];

  @override
  void initState() {
    super.initState();
    _selectedRoomId = widget.approvedRoomType ?? widget.currentRoomTypeId.trim();
    // Automatically set to upgrade mode if we have an approved room type
    _isUpgrading = widget.requestStatus.toLowerCase() == 'approved' && widget.approvedRoomType != null;
    _fetchRoomTypes();
  }

  Future<void> _fetchRoomTypes() async {
    try {
      final response = await ApiService.getRoomTypes();
      if (response['status'] == 'success') {
        final List<dynamic> data = response['data'];
        setState(() {
          _dynamicRoomTypes = data.asMap().entries.map((entry) {
            final index = entry.key;
            final json = entry.value;
            // Use room_code if available, else name, else unique index
            String roomId = json['room_code']?.toString() ?? json['name']?.toString() ?? 'room_$index';
              return RoomType(
                id: roomId,
                name: json['name']?.toString() ?? 'Standard Room',
                sixMonthAmount: (json['six_month_amount'] as num?)?.toDouble() ?? 0.0,
                monthlyAmount: (json['monthly_amount'] as num?)?.toDouble() ?? 0.0,
                description: json['description']?.toString() ?? 'No description available',
                cautionDeposit: (json['caution_deposit'] as num?)?.toDouble() ?? 5000.0,
                messCharges: (json['mess_charges'] as num?)?.toDouble() ?? 0.0,
              );
          }).toList();
          _isLoading = false;
          
          final currentId = (widget.approvedRoomType ?? _selectedRoomId).trim();
          final exists = _dynamicRoomTypes.any((r) => r.id.trim() == currentId);
          
          if (exists) {
             _selectedRoomId = currentId;
          } else {
             // Try to resolve based on capacity/sharing mapping if not approved upgrade
             if (widget.approvedRoomType == null) {
               final String currentCap = widget.currentRoomTypeId.split('-')[0];
               final matched = _dynamicRoomTypes.firstWhere(
                 (r) => r.id.trim().toLowerCase() == widget.currentRoomTypeId.trim().toLowerCase() ||
                        r.name.contains('($currentCap IN 1)'), 
                 orElse: () => _dynamicRoomTypes.first
               );
               _selectedRoomId = matched.id;
             } else {
               _selectedRoomId = _dynamicRoomTypes.first.id;
             }
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching room types: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOpen) return const SizedBox.shrink();
    
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final today = DateTime.now();
    final currentDate = widget.currentRenewalDate;
    
    final newDate = DateTime(currentDate.year, currentDate.month + 6, currentDate.day);

    final remainingMonths = _calculateRemainingMonths(today, currentDate);

    final listToUse = _dynamicRoomTypes;

    final String currentCap = widget.currentRoomTypeId.split('-')[0]; // e.g. "4"
    final isAcUser = widget.currentRoomFacility.toUpperCase().trim() == 'AC';
    final isBathAttachedUser = widget.currentRoomBathAttached.toLowerCase().trim() == 'yes';

    final currentRoom = listToUse.firstWhere(
      (r) {
        final rName = r.name.toUpperCase();
        // 1. Must match capacity code e.g. "4 IN 1" or "4 sharing" or similar
        final matchesCapacity = rName.contains('($currentCap IN 1)') || rName.contains('$currentCap SHARING');
        if (!matchesCapacity) return false;
        
        // 2. Check AC / NON AC facility match
        final isRoomAc = rName.contains('AC') && !rName.contains('NON AC');
        if (isAcUser != isRoomAc) return false;
        
        // 3. Check bath attached match
        final isRoomBath = rName.contains('B ATTACHED') || rName.contains('B&T ATTACHED') || rName.contains('B-ATTACHED') || rName.contains('B & T ATTACHED');
        if (isBathAttachedUser != isRoomBath) return false;
        
        return true;
      },
      orElse: () {
        // Fallback: match by capacity only
        return listToUse.firstWhere(
          (r) => r.id.trim().toLowerCase() == widget.currentRoomTypeId.trim().toLowerCase() ||
                 r.name.contains('($currentCap IN 1)'),
          orElse: () => listToUse.first,
        );
      },
    );
    final selectedRoom = _isUpgrading 
        ? listToUse.firstWhere(
            (r) => r.id.trim().toLowerCase() == _selectedRoomId.trim().toLowerCase(),
            orElse: () => currentRoom,
          )
        : currentRoom;

    final monthlyMarkup = _isUpgrading ? (selectedRoom.monthlyAmount - currentRoom.monthlyAmount).toDouble() : 0.0;
    // If already approved, we don't show the mid-term adjustment, we just charge the new room's fee
    final midTermAdjustment = (widget.requestStatus.toLowerCase() == 'approved') ? 0.0 : (remainingMonths * monthlyMarkup).toDouble();
    final renewalRoomRent = selectedRoom.sixMonthAmount;

    final fees = FeeBreakdown(
      roomRent: renewalRoomRent,
      upgradeAdjustment: midTermAdjustment,
      messCharges: selectedRoom.messCharges,
      maintenance: selectedRoom.cautionDeposit,
      total: renewalRoomRent + midTermAdjustment + selectedRoom.cautionDeposit + selectedRoom.messCharges,
      selectedRoomName: selectedRoom.name,
      remainingMonths: remainingMonths,
    );

    bool isPaymentDisabled = false;
    if (widget.requestStatus.toLowerCase() == 'pending') {
      isPaymentDisabled = true;
    } else if (_isUpgrading) {
      // In upgrade mode, only enable if already approved for this specific type
      if (widget.requestStatus.toLowerCase() == 'approved') {
        final currentSelected = _selectedRoomId.trim().toLowerCase();
        final approved = widget.approvedRoomType?.trim().toLowerCase();
        isPaymentDisabled = currentSelected != approved;
      } else {
        // If not approved, student can only preview types, not pay yet
        isPaymentDisabled = true;
      }
    }

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxWidth: 550,
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F0),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildExpiryDates(currentDate, newDate),
                  const SizedBox(height: 24),
                  _buildRoomSelection(currentRoom, selectedRoom, remainingMonths, monthlyMarkup, midTermAdjustment, listToUse),
                  const SizedBox(height: 24),
                  _buildFeeBreakdown(fees, _isUpgrading),
                ],
              ),
            ),
          ),
          _buildFooter(fees.total, newDate, selectedRoom.name, isPaymentDisabled),
        ],
      ),
    );
  }

  int _calculateRemainingMonths(DateTime today, DateTime currentDate) {
    if (currentDate.isBefore(today)) return 0;
    final difference = currentDate.difference(today);
    return (difference.inDays / 30.44).ceil().clamp(0, 12);
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(25, 20, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Renew Your Stay',
                style: TextStyle(
                  color: Color(0xFF1B2B48),
                  fontFamily: 'Georgia',
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
          const SizedBox(height: 15),
          const Divider(height: 1, color: Color(0xFFE0D8CC)),
        ],
      ),
    );
  }

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

  Widget _buildDateBox(String label, String date, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 14, color: textColor.withOpacity(0.6)),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.6))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            date,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48)),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomSelection(
    RoomType currentRoom,
    RoomType selectedRoom,
    int remainingMonths,
    double monthlyMarkup,
    double midTermAdjustment,
    List<RoomType> listToUse,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.apartment, size: 18, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.requestStatus.toLowerCase() == 'approved' ? 'Approved' : 'Select',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                if (widget.onRoomChangeRequested != null) ...[
                  ElevatedButton.icon(
                    onPressed: (widget.requestStatus.toLowerCase() == 'approved') 
                      ? null // Already approved, cannot change again until paid/processed
                      : () {
                          // Do NOT close the modal here.
                          // _handleRoomChangePressed will close it only after
                          // confirming a floorwise warden is assigned.
                          // If no warden, the user returns to this modal after dismissing the alert.
                          widget.onRoomChangeRequested!();
                        },
                    icon: const Icon(Icons.swap_horiz, size: 16),
                    label: const Text('Room Change'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1A2744),
                      side: const BorderSide(color: Color(0xFFD4AF37)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: const Size(0, 32),
                      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (widget.requestStatus.toLowerCase() != 'approved')
                  ElevatedButton.icon(
                    onPressed: (widget.requestStatus.toLowerCase() == 'pending')
                      ? null // Disable while pending
                      : () {
                          setState(() {
                            _isUpgrading = !_isUpgrading;
                            if (!_isUpgrading) _selectedRoomId = currentRoom.id;
                          });
                        },
                    icon: Icon(_isUpgrading ? Icons.close : Icons.upgrade, size: 16),
                    label: Text(_isUpgrading ? 'Cancel' : 'Upgrade'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isUpgrading ? const Color(0xFF1A2744) : const Color(0xFFD4AF37),
                      foregroundColor: _isUpgrading ? Colors.white : const Color(0xFF1A2744),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: const Size(0, 32),
                      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isUpgrading) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: listToUse.map((room) => _buildRoomCard(room, selectedRoom, currentRoom)).toList(),
              ),
            ),
          ),
          if (remainingMonths > 0 && _selectedRoomId != widget.currentRoomTypeId.trim() && monthlyMarkup > 0)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBBDEFB)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Color(0xFF1976D2)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Mid-term Adjustment: ₹${midTermAdjustment.toStringAsFixed(0)} for remaining $remainingMonths months.',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF1565C0), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
        ] else
          _buildStaticRoomDisplay(currentRoom),
      ],
    );
  }

  Widget _buildRoomCard(RoomType room, RoomType selectedRoom, RoomType currentRoom) {
    final isCurrent = room.id.trim().toLowerCase() == currentRoom.id.trim().toLowerCase();
    final isSelected = _selectedRoomId == room.id;
    
    return GestureDetector(
      onTap: () => setState(() => _selectedRoomId = room.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF9C4).withOpacity(0.3) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFD4AF37) : const Color(0xFFE8E0D5),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: const Color(0xFFD4AF37).withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ] : [],
        ),
        child: Row(
          children: [
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
                            fontSize: 14, // Slightly smaller to fit better
                            fontWeight: FontWeight.bold,
                            color: isSelected ? const Color(0xFF1A2744) : Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A2744),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Current',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    room.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${room.sixMonthAmount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD4AF37),
                  ),
                ),
                Text(
                  'per 6 months',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
                const SizedBox(height: 2),
                Text(
                  '₹${room.monthlyAmount.toStringAsFixed(0)} / month',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaticRoomDisplay(RoomType room) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE0D8CC))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(room.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('₹${room.sixMonthAmount.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildFeeBreakdown(FeeBreakdown fees, bool isUpgrading) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          _buildFeeRow('Room Rent', fees.roomRent),
          if (isUpgrading && fees.upgradeAdjustment > 0) _buildFeeRow('Upgrade Adjustment', fees.upgradeAdjustment),
          _buildFeeRow('Maintenance Charges', fees.maintenance),
          const Divider(),
          _buildFeeRow('Total', fees.total, isTotal: true),
        ],
      ),
    );
  }

  Widget _buildFeeRow(String label, double amount, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
        Text('₹${amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: isTotal ? 18 : 14)),
      ],
    );
  }

  Widget _buildFooter(double totalAmount, DateTime newDate, String selectedRoomName, bool isPaymentDisabled) {
    String buttonText = 'Proceed to Payment';
    final status = widget.requestStatus.toLowerCase();
    
    if (status == 'pending') {
      buttonText = 'Room Change Pending';
    } else if (_isUpgrading) {
      if (status == 'approved') {
        if (_selectedRoomId.trim().toLowerCase() == widget.approvedRoomType?.trim().toLowerCase()) {
          buttonText = 'Pay ₹${totalAmount.toStringAsFixed(0)}';
        } else {
          buttonText = 'Select Approved Type';
        }
      } else {
        buttonText = 'Request Room Change First';
      }
    } else {
      buttonText = 'Pay ₹${totalAmount.toStringAsFixed(0)}';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(25, 10, 25, 25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: (_isProcessing || isPaymentDisabled) ? null : () => _handlePayment(totalAmount, newDate, selectedRoomName),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFD4AF37),
          foregroundColor: const Color(0xFF1A2744),
          disabledBackgroundColor: Colors.grey.shade300,
          disabledForegroundColor: Colors.grey.shade600,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: (_isProcessing || isPaymentDisabled) ? 0 : 2,
        ),
        child: _isProcessing 
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A2744)),
            )
          : Text(
              buttonText,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
      ),
    );
  }

  void _handlePayment(double totalAmount, DateTime newDate, String selectedRoomName) async {
    setState(() => _isProcessing = true);
    await Future.delayed(const Duration(seconds: 2));
    widget.onRenewalSuccess(newDate, 'RCP${DateTime.now().millisecondsSinceEpoch}', totalAmount, selectedRoomName);
    setState(() => _isProcessing = false);
    widget.onClose();
  }
}

/// Fee Breakdown Model
class FeeBreakdown {
  final double roomRent;
  final double upgradeAdjustment;
  final double messCharges;
  final double maintenance;
  final double total;
  final String selectedRoomName;
  final int remainingMonths;

  FeeBreakdown({
    required this.roomRent,
    required this.upgradeAdjustment,
    required this.messCharges,
    required this.maintenance,
    required this.total,
    required this.selectedRoomName,
    required this.remainingMonths,
  });
}

/// Helper function to show the renewal modal
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

