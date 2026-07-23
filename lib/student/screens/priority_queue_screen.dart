import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/design_system.dart' as ds;
import '../../core/providers/allocation_provider.dart';
import '../../shared/user_provider.dart';
import 'allocation_status_screen.dart';

class PriorityQueueScreen extends StatelessWidget {
  const PriorityQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AllocationProvider>();
    final user = context.watch<UserProvider>();
    final isDraft = provider.allocationStatus == 'draft' || 
                    provider.allocationStatus == 'none' ||
                    provider.allocationStatus == 'rejected' ||
                    provider.allocationStatus == 'payment_expired';

    return Scaffold(
      body: ds.LinenBackground(
        child: Column(
          children: [
            const ds.SkeuomorphicNavBar(title: 'Priority Queue'),
            
            // Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              color: isDraft ? ds.RoyalTheme.warningStart.withOpacity(0.2) : ds.RoyalTheme.successStart.withOpacity(0.2),
              child: Row(
                children: [
                  Icon(
                    isDraft ? Icons.lock_open : Icons.lock,
                    color: isDraft ? ds.RoyalTheme.warningEnd : ds.RoyalTheme.successEnd,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isDraft 
                        ? 'Draft Mode: You can reorder or remove rooms before submitting.'
                        : 'Preferences Locked: Your request has been submitted to the warden.',
                      style: GoogleFonts.lato(
                        fontSize: 12, 
                        fontWeight: FontWeight.bold,
                        color: ds.RoyalTheme.navyDarker
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: provider.preferences.length,
                itemBuilder: (context, index) {
                  final pref = provider.preferences[index];
                  
                  // Reorder helper
                  void moveItem(int oldIdx, int newIdx) {
                    if (!isDraft) return;
                    if (newIdx < 0 || newIdx >= provider.preferences.length) return;
                    
                    final List<Map<String, dynamic>> items = List.from(provider.preferences);
                    final item = items.removeAt(oldIdx);
                    items.insert(newIdx, item);
                    
                    final List<Map<String, dynamic>> payload = [];
                    for (int i = 0; i < items.length; i++) {
                      payload.add({
                        'room_id': items[i]['room_id'],
                        'priority_order': i + 1
                      });
                    }
                    provider.reorderPreferences(user.dbId!, payload);
                  }

                  return Padding(
                    key: ValueKey(pref['id']),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ds.SkeuomorphicCard(
                      child: Row(
                        children: [
                          // Priority Number
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: ds.RoyalTheme.goldGradient, 
                              shape: BoxShape.circle,
                              border: Border.all(color: ds.RoyalTheme.goldDarkBorder, width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 2,
                                  offset: const Offset(0, 1),
                                )
                              ],
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pref['room_type']?.toString() ?? 'N/A',
                                  style: GoogleFonts.lato(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: ds.RoyalTheme.navyDarker,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Room ${pref['room_no'] ?? ''} (${pref['building_code'] ?? ''})',
                                  style: GoogleFonts.lato(fontSize: 12, color: Colors.grey.shade600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (isDraft) ...[
                            // Up/Down Arrows
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 32,
                                  width: 32,
                                  child: index > 0 
                                    ? IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.arrow_drop_up, color: Colors.grey, size: 30),
                                        onPressed: () => moveItem(index, index - 1),
                                      )
                                    : const SizedBox.shrink(),
                                ),
                                SizedBox(
                                  height: 32,
                                  width: 32,
                                  child: index < provider.preferences.length - 1
                                    ? IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 30),
                                        onPressed: () => moveItem(index, index + 1),
                                      )
                                    : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => provider.removePreference(user.dbId!, int.parse(pref['room_id'].toString())),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Bottom Actions
            Container(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
              decoration: BoxDecoration(
                gradient: ds.RoyalTheme.navyGradient,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isDraft) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${provider.preferences.length} of 5 rooms selected',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        TextButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.add, color: ds.RoyalTheme.primaryGoldStart, size: 18),
                          label: const Text('Add more', style: TextStyle(color: ds.RoyalTheme.primaryGoldStart)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ds.SkeuomorphicButton(
                      text: 'Submit to Warden',
                      icon: Icons.send,
                      onPressed: provider.preferences.isEmpty ? null : () => _showSubmitConfirmation(context, provider, user.dbId!),
                    ),
                  ] else ...[
                    ds.SkeuomorphicButton(
                      text: 'View Allocation Status',
                      isPrimary: false,
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AllocationStatusScreen())),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSubmitConfirmation(BuildContext context, AllocationProvider provider, int studentId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ds.RoyalTheme.linenStart,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          'Confirm Submission',
          style: GoogleFonts.lato(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to submit these priorities?'),
            const SizedBox(height: 12),
            ...provider.preferences.map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• Priority ${p['priority_order']}: ${p['room_type']} (Room ${p['room_no']})'),
            )),
            const SizedBox(height: 12),
            const Text(
              'Once submitted, you cannot change your preferences.',
              style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ds.RoyalTheme.primaryGoldEnd,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              final success = await provider.submitPreferences(studentId);
              if (success) {
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      settings: const RouteSettings(name: '/allocation_status'),
                      builder: (context) => const AllocationStatusScreen(),
                    ),
                  );
                }
              }
            },
            child: const Text('Confirm & Submit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
