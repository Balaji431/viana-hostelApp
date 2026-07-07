import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/design_system.dart' as ds;
import '../../core/providers/allocation_provider.dart';
import '../../core/widgets/countdown_timer.dart';
import '../../shared/user_provider.dart';
import '../../core/api_service.dart';
import 'allocation_explorer_screen.dart';

class AllocationStatusScreen extends StatefulWidget {
  const AllocationStatusScreen({super.key});

  @override
  State<AllocationStatusScreen> createState() => _AllocationStatusScreenState();
}

class _AllocationStatusScreenState extends State<AllocationStatusScreen> {
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Provider.of<UserProvider>(context, listen: false);
      if (user.dbId != null) {
        Provider.of<AllocationProvider>(context, listen: false).loadAllocation(user.dbId!);
      }
    });
  }

  Future<void> _handlePayment(int allocationId) async {
    setState(() => _isProcessing = true);
    try {
      final res = await ApiService.payAllocation(allocationId, 'Credit Card');
      if (res['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Payment successful — Room ${res['room_id']} is yours!"),
            backgroundColor: ds.RoyalTheme.successMid,
          ),
        );
        // Refresh allocation data
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        if (userProvider.dbId != null) {
          await userProvider.refreshUserData();
          await Provider.of<AllocationProvider>(context, listen: false).loadAllocation(userProvider.dbId!);
        }
      } else {
        throw Exception(res['message']);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: ds.RoyalTheme.dangerMid),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showRoomDetails(Map<String, dynamic>? allocation) {
    if (allocation == null) return;
    
    final bool isPaid = allocation['allocation_status'] == 'approved';

    ds.SkeuomorphicModal.show(
      context,
      title: 'Room Details',
      child: Column(
        children: [
          // Hero strip
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ds.RoyalTheme.primaryGoldStart.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ds.RoyalTheme.primaryGoldStart,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.apartment, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Room ${allocation['room_no']}',
                        style: GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Block ${allocation['building_code']} • ${allocation['floor']} Floor',
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Details List
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withOpacity(0.05)),
            ),
            child: Column(
              children: [
                _buildDetailRow('Capacity', allocation['room_type'] ?? 'N/A'),
                _buildDivider(),
                _buildDetailRow('Block', allocation['building_code'] ?? 'N/A'),
                _buildDivider(),
                _buildDetailRow('Floor', allocation['floor'] ?? 'N/A'),
                _buildDivider(),
                _buildDetailRow('Amenities', allocation['facility'] ?? 'N/A'),
                if (isPaid && allocation['paid_at'] != null) ...[
                  _buildDivider(),
                  _buildDetailRow('Paid On', allocation['paid_at'].toString().split(' ')[0]),
                ],
              ],
            ),
          ),
          
          if (!isPaid) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                  SizedBox(width: 8),
                  Text('Held 24h — Pending Payment', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        ds.SkeuomorphicButton(
          text: 'Close',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildDivider() => Divider(height: 1, color: Colors.black.withOpacity(0.05), indent: 16, endIndent: 16);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AllocationProvider>();
    final status = provider.allocationStatus;
    final allocation = provider.allocation;

    return Scaffold(
      body: ds.LinenBackground(
        child: Column(
          children: [
            const ds.SkeuomorphicNavBar(title: 'Allocation Status'),
            
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  final user = Provider.of<UserProvider>(context, listen: false);
                  if (user.dbId != null) {
                    await Provider.of<AllocationProvider>(context, listen: false).loadAllocation(user.dbId!);
                  }
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                  children: [
                    // Hero Status Card
                    _buildHeroStatus(status, allocation),
                    const SizedBox(height: 24),

                    // Special Priority 1 Occupied Warning Box
                    if ((status == 'submitted' || status == 'under_review') && provider.firstPriorityHeldByPending) ...[
                      _buildPriorityConflictCard(provider),
                      const SizedBox(height: 24),
                    ],
                    
                    // Timeline Card
                    _buildTimeline(status),
                    const SizedBox(height: 24),
                    
                    // Payment Card (Stage 2)
                    if (status == 'payment_pending')
                      _buildPaymentCard(allocation),
                    
                    // Allocated Room Card (Approved)
                    if (status == 'approved' || status == 'payment_pending')
                      _buildAllocatedRoomCard(allocation, status == 'payment_pending'),
                  ],
                ),
              ),
            ),
          ),
            
            // Bottom Bar
            Container(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
              decoration: BoxDecoration(
                gradient: ds.RoyalTheme.navyGradient,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (status == 'none') ...[
                    ds.SkeuomorphicButton(
                      text: 'Browse Available Rooms',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            settings: const RouteSettings(name: '/allocation_explorer'),
                            builder: (_) => const AllocationExplorerScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (status == 'rejected' || status == 'payment_expired') ...[
                    ds.SkeuomorphicButton(
                      text: 'Start New Application',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            settings: const RouteSettings(name: '/allocation_explorer'),
                            builder: (_) => const AllocationExplorerScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  ds.SkeuomorphicButton(
                    text: 'Back to Home',
                    isPrimary: false,
                    onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroStatus(String status, Map<String, dynamic>? allocation) {
    Color statusColor = ds.RoyalTheme.warningMid;
    String statusText = status == 'none' ? 'NEW' : status.replaceAll('_', ' ').toUpperCase();
    String desc = "Your application is being processed.";

    if (status == 'approved') {
      statusColor = ds.RoyalTheme.successMid;
      desc = "Congratulations! Your room is confirmed.";
    } else if (status == 'payment_pending') {
      statusColor = Colors.amber;
      desc = "Room Reserved! Please complete payment within 24h.";
    } else if (status == 'rejected' || status == 'payment_expired') {
      statusColor = ds.RoyalTheme.dangerMid;
      desc = status == 'payment_expired' ? "Payment window expired. Room released." : "Your application was not approved.";
    } else if (status == 'none') {
      statusColor = Colors.grey;
      desc = "You haven't started an application yet. Explore rooms to begin.";
    }

    return ds.SkeuomorphicCard(
      child: Column(
        children: [
          ds.GlossyBadge(label: statusText, isActive: true, colorOverride: statusColor),
          const SizedBox(height: 16),
          Text(
            desc,
            textAlign: TextAlign.center,
            style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (status == 'submitted' && allocation?['queue_position'] != null) ...[
            const SizedBox(height: 16),
            _buildQueueInfo(allocation!['queue_position']),
          ],
        ],
      ),
    );
  }

  Widget _buildQueueInfo(dynamic queuePos) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: ds.RoyalTheme.primaryGoldStart.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ds.RoyalTheme.primaryGoldEnd.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Text('Queue Position', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          Text(
            '#$queuePos',
            style: GoogleFonts.lato(fontSize: 24, fontWeight: FontWeight.bold, color: ds.RoyalTheme.primaryGoldEnd),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(String currentStatus) {
    final steps = ['draft', 'submitted', 'under_review', 'payment_pending', 'approved'];
    final labels = ['Draft', 'Submitted', 'Under Review', 'Awaiting Payment', 'Allocated'];
    final icons = [Icons.edit_note, Icons.send_rounded, Icons.visibility_outlined, Icons.credit_card, Icons.check_circle_outline];
    
    int currentIndex = steps.indexOf(currentStatus);
    bool isExpired = currentStatus == 'payment_expired';
    bool isRejected = currentStatus == 'rejected';

    return ds.SkeuomorphicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Application Progress', style: GoogleFonts.lato(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          ...List.generate(steps.length, (index) {
            bool isCompleted = index < currentIndex || (index == currentIndex && currentStatus == 'approved');
            bool isCurrent = index == currentIndex && currentStatus != 'approved' && !isExpired && !isRejected;
            bool isFailed = index == 4 && (isExpired || isRejected);

            Color stepColor = isCompleted ? ds.RoyalTheme.successMid : isCurrent ? ds.RoyalTheme.warningMid : isFailed ? ds.RoyalTheme.dangerMid : Colors.grey.shade300;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: stepColor,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(
                        isFailed ? Icons.close : (isCompleted ? Icons.check : icons[index]),
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                    if (index < steps.length - 1)
                      Container(
                        width: 2,
                        height: 35,
                        color: index < currentIndex ? ds.RoyalTheme.successMid : Colors.grey.shade300,
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isFailed ? (isExpired ? "Hold Expired" : "Rejected") : labels[index],
                        style: TextStyle(
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          color: isFailed ? ds.RoyalTheme.dangerMid : (isCompleted || isCurrent ? ds.RoyalTheme.navyDarker : Colors.grey),
                        ),
                      ),
                      if (index == 4 && isCompleted && currentStatus == 'approved')
                         Text("Paid ${context.read<AllocationProvider>().allocation?['paid_at']?.toString().split(' ')[0] ?? ''}", 
                              style: const TextStyle(fontSize: 10, color: ds.RoyalTheme.successMid)),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPriorityConflictCard(AllocationProvider provider) {
    final user = Provider.of<UserProvider>(context, listen: false);

    return ds.SkeuomorphicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '1st Priority Occupied',
                        style: GoogleFonts.playfairDisplay(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.amber.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'your first prority room has been occupied by the some other student which is his payment is pending  so if you want to continue with your second priority room there in the screen add two buttons wait for 1st priority or continue',
                        style: TextStyle(fontSize: 13, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'You can choose to wait for the first priority room lock to clear, or continue to your second priority room immediately by paying the amount set for it.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ds.SkeuomorphicButton(
                  text: 'Wait for 1st Priority',
                  isPrimary: false,
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('You are waiting for the 1st priority room hold to expire...'),
                        backgroundColor: ds.RoyalTheme.navyDarker,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ),
              if (provider.hasSecondPriority) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: ds.SkeuomorphicButton(
                    text: _isProcessing ? 'Processing...' : 'Continue',
                    onPressed: _isProcessing ? null : () => _handleContinueToSecondPriority(provider, user.dbId!),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleContinueToSecondPriority(AllocationProvider provider, int studentId) async {
    setState(() => _isProcessing = true);
    try {
      final res = await provider.continueToSecondPriority(studentId);
      if (res['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Successfully continued to 2nd priority room!'),
            backgroundColor: ds.RoyalTheme.successMid,
            behavior: SnackBarBehavior.floating,
          ),
        );
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        await userProvider.refreshUserData();
      } else {
        throw Exception(res['message']);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: ds.RoyalTheme.dangerMid,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Widget _buildPaymentCard(Map<String, dynamic>? allocation) {
    if (allocation == null || allocation['payment_deadline'] == null) return const SizedBox();
    
    DateTime deadline = DateTime.parse(allocation['payment_deadline']);
    final amountStr = allocation['amount'] != null ? '₹${allocation['amount']}' : '₹68,000';
    final bool isExpired = DateTime.now().isAfter(deadline);

    return ds.SkeuomorphicCard(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isExpired ? Colors.red.shade50 : Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isExpired ? Colors.red.shade200 : Colors.transparent),
            ),
            child: Row(
              children: [
                Icon(isExpired ? Icons.error_outline : Icons.lock_clock, color: isExpired ? Colors.red : Colors.amber, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isExpired ? 'Reservation Expired' : 'Room Reserved for You',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 18, 
                      fontWeight: FontWeight.bold, 
                      color: isExpired ? Colors.red.shade900 : Colors.amber.shade900
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CountdownTimer(
            deadline: deadline,
            onExpired: () {
                if (mounted) {
                  setState(() {});
                }
                final userProvider = Provider.of<UserProvider>(context, listen: false);
                if (userProvider.dbId != null) {
                  Provider.of<AllocationProvider>(context, listen: false).loadAllocation(userProvider.dbId!);
                }
            },
          ),
          if (isExpired) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Your 24h payment window has expired. This reservation is no longer valid. Please start a new room allocation request.',
                      style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Allocation Fee', style: TextStyle(color: Colors.grey)),
              Text(amountStr, style: GoogleFonts.lato(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          ds.SkeuomorphicButton(
            text: isExpired ? 'Payment Window Expired' : (_isProcessing ? 'Processing...' : 'Pay $amountStr Now'),
            icon: Icons.credit_card,
            onPressed: (isExpired || _isProcessing) ? null : () => _showPaymentConfirmation(allocation),
          ),
        ],
      ),
    );
  }

  void _showPaymentConfirmation(Map<String, dynamic> allocation) {
    final amountStr = allocation['amount'] != null ? '₹${allocation['amount']}' : '₹68,000';
    ds.SkeuomorphicModal.show(
      context,
      title: 'Confirm Payment',
      child: Column(
        children: [
          const Text('You are about to pay the room allocation fee.', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Amount:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(amountStr, style: GoogleFonts.lato(fontSize: 22, fontWeight: FontWeight.bold, color: ds.RoyalTheme.primaryGoldEnd),),
            ],
          ),
        ],
      ),
      actions: [
        ds.SkeuomorphicButton(
          text: 'Pay & Confirm',
          onPressed: () {
            Navigator.pop(context);
            _handlePayment(allocation['id']);
          },
        ),
        const SizedBox(height: 8),
        ds.SkeuomorphicButton(
          text: 'Cancel',
          isPrimary: false,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildAllocatedRoomCard(Map<String, dynamic>? allocation, bool isHeld) {
    return Column(
      children: [
        const SizedBox(height: 24),
        ds.SkeuomorphicCard(
          borderRadius: 12,
          onTap: () => _showRoomDetails(allocation),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: ds.RoyalTheme.primaryGoldStart, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.home_work_outlined, size: 48, color: ds.RoyalTheme.primaryGoldEnd),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(isHeld ? 'RESERVED ROOM' : 'ALLOCATED ROOM', 
                               style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isHeld ? Colors.amber : ds.RoyalTheme.primaryGoldEnd)),
                          if (isHeld)
                            const ds.GlossyBadge(label: 'HELD 24H', isActive: true, colorOverride: Colors.amber),
                        ],
                      ),
                      Text(
                        'Room ${allocation?['room_no'] ?? 'N/A'}',
                        style: GoogleFonts.lato(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Block ${allocation?['building_code'] ?? ''} • ${allocation?['floor'] ?? ''} Floor',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
