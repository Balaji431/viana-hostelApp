import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../../core/styles.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';

class AdminActivityLogsScreen extends StatefulWidget {
  const AdminActivityLogsScreen({super.key});

  @override
  State<AdminActivityLogsScreen> createState() => _AdminActivityLogsScreenState();
}

class _AdminActivityLogsScreenState extends State<AdminActivityLogsScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _activeTab = 0; // 0: Complaints, 1: Feedback
  List<Map<String, dynamic>> _complaints = [];
  List<Map<String, dynamic>> _feedbacks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final compRes = await ApiService.getComplaints();
      final feedRes = await ApiService.getFeedbacks();

      setState(() {
        if (compRes['success'] == true) {
          _complaints = List<Map<String, dynamic>>.from(compRes['data'] ?? []);
        }
        if (feedRes['success'] == true) {
          _feedbacks = List<Map<String, dynamic>>.from(feedRes['data'] ?? []);
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error fetching logs: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: 'Activity Logs',
        onBack: null,
        rightAction: IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
          onPressed: _fetchData,
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        ),
      ),
      body: LinenGridBackground(
        child: Column(
          children: [
            _buildTabSwitcher(isDark),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF1B2B48)))
                  : _activeTab == 0
                      ? _buildComplaintsList()
                      : _buildFeedbackList(),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Skeuomorphic Tab Switcher ──────────────────────────────────────────
  Widget _buildTabSwitcher(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withOpacity(0.85) : Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.14) : Colors.black12,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Complaints Tab
          Expanded(
            child: _buildTabButton(
              index: 0,
              label: "Complaints",
              icon: Icons.report_problem_outlined,
              badgeCount: _complaints.where((c) => c['status'] == 'Pending').length,
              isDark: isDark,
            ),
          ),
          // Feedback Tab
          Expanded(
            child: _buildTabButton(
              index: 1,
              label: "Feedback",
              icon: Icons.star_border_rounded,
              badgeCount: 0,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required int index,
    required String label,
    required IconData icon,
    int badgeCount = 0,
    bool isDark = false,
  }) {
    final active = _activeTab == index;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          gradient: active ? SkeuomorphicColors.goldGlossyGradient : null,
          color: active ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: const Color(0xFFB8962E).withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: active ? const Color(0xFF3D2E0A) : (isDark ? Colors.white60 : Colors.grey),
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: active ? const Color(0xFF3D2E0A) : (isDark ? Colors.white70 : Colors.grey),
                fontWeight: FontWeight.bold,
                fontSize: 14,
                fontFamily: 'Lato',
              ),
            ),
            if (badgeCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  "$badgeCount",
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  // ─── Complaints List ────────────────────────────────────────────────────
  Widget _buildComplaintsList() {
    if (_complaints.isEmpty) {
      return const Center(
        child: Text("No complaints raised yet.", style: TextStyle(color: Colors.grey, fontFamily: 'Lato')),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _complaints.length,
      itemBuilder: (context, index) {
        final complaint = _complaints[index];
        return _buildComplaintCard(complaint);
      },
    );
  }

  Widget _buildComplaintCard(Map<String, dynamic> c) {
    final date = DateTime.parse(c['created_at']);
    final status = c['status']?.toString() ?? 'Pending';
    final hasReply = c['admin_reply'] != null && c['admin_reply'].toString().trim().isNotEmpty;

    Color badgeColor;
    Color badgeTextColor;
    if (status == 'Resolved') {
      badgeColor = Colors.green.withOpacity(0.12);
      badgeTextColor = Colors.green.shade800;
    } else if (status == 'Under Review') {
      badgeColor = Colors.blue.withOpacity(0.12);
      badgeTextColor = Colors.blue.shade800;
    } else {
      badgeColor = Colors.orange.withOpacity(0.12);
      badgeTextColor = Colors.orange.shade800;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: SkeuomorphicStyles.skeuomorphicCard,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Student & Staff Header Strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9F6F1),
                border: Border(bottom: BorderSide(color: Colors.black.withOpacity(0.05))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c['student_name'] ?? 'Unknown Student',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1B2B48)),
                        ),
                        Text(
                          "Room ${c['student_room'] ?? 'N/A'} • Reg No: ${c['student_reg_no'] ?? 'N/A'}",
                          style: const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(color: badgeTextColor, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Target Staff Details
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(color: Colors.black87, fontSize: 13, fontFamily: 'Lato'),
                          children: [
                            const TextSpan(text: "Against "),
                            TextSpan(
                              text: c['staff_name'] ?? 'Unknown Staff',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                            ),
                            TextSpan(text: " (${c['staff_role']?.toString().capitalize()})"),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Complaint Message Box
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.08)),
                    ),
                    child: Text(
                      c['message'] ?? '',
                      style: const TextStyle(color: Colors.black87, fontSize: 13.5, height: 1.4),
                    ),
                  ),

                  // Admin Reply display
                  if (hasReply) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withOpacity(0.12)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.check_circle_outline, size: 14, color: Colors.green),
                              SizedBox(width: 6),
                              Text(
                                "ADMINISTRATIVE REPLY",
                                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            c['admin_reply'],
                            style: const TextStyle(color: Colors.black87, fontSize: 13, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // Footer & Action Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('dd MMM yyyy, hh:mm a').format(date),
                        style: const TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                      if (status != 'Resolved')
                        InkWell(
                          onTap: () => _showUpdateStatusDialog(c),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: SkeuomorphicStyles.glossyButton(
                              SkeuomorphicColors.goldGlossyGradient,
                            ),
                            child: const Text(
                              "Reply & Resolve",
                              style: TextStyle(color: Color(0xFF3D2E0A), fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                        )
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Feedback List ──────────────────────────────────────────────────────
  Widget _buildFeedbackList() {
    if (_feedbacks.isEmpty) {
      return const Center(
        child: Text("No feedback received yet.", style: TextStyle(color: Colors.grey, fontFamily: 'Lato')),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _feedbacks.length,
      itemBuilder: (context, index) {
        final feedback = _feedbacks[index];
        return _buildFeedbackCard(feedback);
      },
    );
  }

  Widget _buildFeedbackCard(Map<String, dynamic> f) {
    final date = DateTime.parse(f['created_at']);
    final rating = int.tryParse(f['rating']?.toString() ?? '5') ?? 5;
    final hasComments = f['message'] != null && f['message'].toString().trim().isNotEmpty;

    final List<String> ratingLabels = [
      "",
      "Very Bad",
      "Poor",
      "Average",
      "Good",
      "Excellent",
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: SkeuomorphicStyles.skeuomorphicCard,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Student & Rating Strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9F6F1),
                border: Border(bottom: BorderSide(color: Colors.black.withOpacity(0.05))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f['student_name'] ?? 'Unknown Student',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1B2B48)),
                        ),
                        Text(
                          "Room ${f['student_room'] ?? 'N/A'} • Reg No: ${f['student_reg_no'] ?? 'N/A'}",
                          style: const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  
                  // Stars
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(5, (index) {
                          final isSelected = index < rating;
                          return Icon(
                            isSelected ? Icons.star_rounded : Icons.star_border_rounded,
                            color: isSelected ? const Color(0xFFD4AF37) : Colors.grey.shade400,
                            size: 18,
                          );
                        }),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ratingLabels[rating],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: rating >= 4 
                            ? Colors.green.shade800 
                            : rating == 3 
                              ? Colors.orange.shade800 
                              : Colors.red.shade800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Target Staff Details
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(color: Colors.black87, fontSize: 13, fontFamily: 'Lato'),
                          children: [
                            const TextSpan(text: "For "),
                            TextSpan(
                              text: f['staff_name'] ?? 'Unknown Staff',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                            ),
                            TextSpan(text: " (${f['staff_role']?.toString().capitalize()})"),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  if (hasComments) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        f['message'],
                        style: const TextStyle(color: Colors.black87, fontSize: 13.5, fontStyle: FontStyle.italic, height: 1.4),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('dd MMM yyyy, hh:mm a').format(date),
                        style: const TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                      const Text("", style: TextStyle(fontSize: 1)), // Just to align
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Status Update Dialog ───────────────────────────────────────────────
  void _showUpdateStatusDialog(Map<String, dynamic> c) {
    final TextEditingController replyController = TextEditingController();
    String selectedStatus = c['status'] == 'Pending' ? 'Under Review' : 'Resolved';
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F0E8),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFB8962E), width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: const BoxDecoration(
                        gradient: SkeuomorphicColors.royalHeaderGradient,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(22),
                          topRight: Radius.circular(22),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.reply_rounded, color: Colors.white, size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Reply & Update Status",
                              style: GoogleFonts.tinos(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Dropdown for Status
                          const Text("Select New Status", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B2B48))),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: selectedStatus,
                                isExpanded: true,
                                items: ['Under Review', 'Resolved'].map((String val) {
                                  return DropdownMenuItem<String>(
                                    value: val,
                                    child: Text(val, style: const TextStyle(fontSize: 14)),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => selectedStatus = val);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Text field for Reply
                          const Text("Administrative Reply / Action Taken", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B2B48))),
                          const SizedBox(height: 6),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: TextField(
                              controller: replyController,
                              maxLines: 3,
                              minLines: 2,
                              style: const TextStyle(fontSize: 14, color: Colors.black),
                              decoration: const InputDecoration(
                                hintText: "Write response or action taken details...",
                                hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                                contentPadding: EdgeInsets.all(12),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: isSaving ? null : () => Navigator.pop(context),
                                child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 12),
                              InkWell(
                                onTap: isSaving
                                    ? null
                                    : () async {
                                        final reply = replyController.text.trim();
                                        if (reply.isEmpty) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text("Please write a reply/action details.")),
                                          );
                                          return;
                                        }

                                        setState(() => isSaving = true);

                                        final compId = int.tryParse(c['id']?.toString() ?? '') ?? 0;
                                        final res = await ApiService.updateComplaintStatus(
                                          complaintId: compId,
                                          status: selectedStatus,
                                          reply: reply,
                                        );

                                        if (res['success'] == true) {
                                          // 🔥 AUTO-POST TO CHAT
                                          try {
                                            final int studentId = int.tryParse(c['student_id']?.toString() ?? '0') ?? 0;
                                            final String staffRole = c['staff_role']?.toString().toLowerCase() ?? 'warden';
                                            final String staffName = c['staff_name'] ?? 'Staff';
                                            
                                            if (studentId > 0) {
                                              // 1. Get relevant chat request ID
                                              final channel = (staffRole == 'warden' || staffRole == 'parent') ? 'parent_warden' : staffRole;
                                              final reqRes = await ApiService.getLatestRequestId(studentId, channel);
                                              
                                              if (reqRes['success'] == true && reqRes['request_id'] != null) {
                                                final rid = reqRes['request_id'].toString();
                                                final updateMsg = "Action taken on $staffName (${staffRole.capitalize()}): $reply";
                                                
                                                // 2. Post as administrative update
                                                await ApiService.sendChatMessage(
                                                  rid, 
                                                  'admin', 
                                                  updateMsg, 
                                                  messageType: 'admin_reply',
                                                  department: channel,
                                                );
                                              }
                                            }
                                          } catch (e) {
                                            debugPrint("Failed to post admin update to chat: $e");
                                          }
                                        }

                                        if (context.mounted) {
                                          setState(() => isSaving = false);
                                          Navigator.pop(context);

                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(res['message'] ?? 'Status updated successfully'),
                                              backgroundColor: res['success'] == true ? Colors.green : Colors.red,
                                            ),
                                          );
                                          
                                          // Refresh logs list
                                          _fetchData();
                                        }
                                      },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  decoration: SkeuomorphicStyles.glossyButton(
                                    isSaving
                                        ? const LinearGradient(colors: [Colors.grey, Colors.grey])
                                        : SkeuomorphicColors.goldGlossyGradient,
                                  ),
                                  child: isSaving
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Text(
                                          "Save",
                                          style: TextStyle(
                                            color: Color(0xFF3D2E0A),
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Lato',
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

}
