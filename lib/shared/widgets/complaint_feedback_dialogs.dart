import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/api_service.dart';
import '../../core/styles.dart';

class ComplaintFeedbackHelper {
  static void showComplaintFeedbackMenu(
    BuildContext context, {
    required String staffName,
    required String staffUsername,
    required String staffRole,
    required int studentId,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Color(0xFF141E2E), // Royal deep navy
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 15,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pull bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                staffName,
                style: GoogleFonts.tinos(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                staffRole.toUpperCase(),
                style: GoogleFonts.lato(
                  color: const Color(0xFFD4AF37), // Gold
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              
              // Option 1: Raise Complaint
              _buildMenuOption(
                context: context,
                icon: Icons.report_problem_outlined,
                iconColor: Colors.redAccent,
                title: "Raise a Complaint",
                subtitle: "Report improper behavior or problems directly",
                onTap: () {
                  Navigator.pop(context);
                  _showComplaintDialog(
                    context,
                    staffName: staffName,
                    staffUsername: staffUsername,
                    staffRole: staffRole,
                    studentId: studentId,
                  );
                },
              ),
              const SizedBox(height: 12),
              
              // Option 2: Submit Feedback
              _buildMenuOption(
                context: context,
                icon: Icons.star_border_rounded,
                iconColor: const Color(0xFFD4AF37),
                title: "Submit Feedback",
                subtitle: "Rate and review performance out of 5 stars",
                onTap: () {
                  Navigator.pop(context);
                  _showFeedbackDialog(
                    context,
                    staffName: staffName,
                    staffUsername: staffUsername,
                    staffRole: staffRole,
                    studentId: studentId,
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  static Widget _buildMenuOption({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Lato',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 12,
                      fontFamily: 'Lato',
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  static void _showComplaintDialog(
    BuildContext context, {
    required String staffName,
    required String staffUsername,
    required String staffRole,
    required int studentId,
  }) {
    final TextEditingController controller = TextEditingController();
    bool isSubmitting = false;

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
                  color: const Color(0xFFF5F0E8), // Linen white/cream
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFB8962E), width: 1.5), // Gold outline
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
                    // Styled Royal header strip
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
                          const Icon(Icons.report_problem_rounded, color: Colors.redAccent, size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Raise Complaint",
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
                          RichText(
                            text: TextSpan(
                              style: GoogleFonts.lato(color: Colors.black87, fontSize: 14),
                              children: [
                                const TextSpan(text: "Raising complaint against "),
                                TextSpan(
                                  text: staffName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B2B48)),
                                ),
                                TextSpan(text: " ($staffRole)."),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Custom styled text area
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                )
                              ],
                            ),
                            child: TextField(
                              controller: controller,
                              maxLines: 4,
                              minLines: 3,
                              style: const TextStyle(fontSize: 14, color: Colors.black),
                              decoration: const InputDecoration(
                                hintText: "Write your complaint details here...",
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
                              // Cancel
                              TextButton(
                                onPressed: isSubmitting ? null : () => Navigator.pop(context),
                                child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 12),
                              
                              // Submit skeuo button
                              InkWell(
                                onTap: isSubmitting
                                    ? null
                                    : () async {
                                        final msg = controller.text.trim();
                                        if (msg.isEmpty) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text("Please write complaint details")),
                                          );
                                          return;
                                        }
                                        if (msg.length < 10) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text("Complaint must be at least 10 characters long")),
                                          );
                                          return;
                                        }
                                        
                                        setState(() => isSubmitting = true);
                                        
                                        final res = await ApiService.submitComplaint(
                                          studentId: studentId,
                                          staffUsername: staffUsername,
                                          staffRole: staffRole,
                                          message: msg,
                                        );
                                        
                                        if (context.mounted) {
                                          setState(() => isSubmitting = false);
                                          Navigator.pop(context);
                                          
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(res['message'] ?? 'Action complete'),
                                              backgroundColor: res['success'] == true ? Colors.green : Colors.red,
                                            ),
                                          );
                                        }
                                      },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  decoration: SkeuomorphicStyles.glossyButton(
                                    isSubmitting
                                        ? const LinearGradient(colors: [Colors.grey, Colors.grey])
                                        : SkeuomorphicColors.goldGlossyGradient,
                                  ),
                                  child: isSubmitting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Text(
                                          "Submit",
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

  static void _showFeedbackDialog(
    BuildContext context, {
    required String staffName,
    required String staffUsername,
    required String staffRole,
    required int studentId,
  }) {
    final TextEditingController controller = TextEditingController();
    int rating = 5;
    bool isSubmitting = false;

    final List<String> ratingLabels = [
      "Select stars to rate",
      "Very Bad",
      "Poor",
      "Average",
      "Good",
      "Excellent",
    ];

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
                    // Styled Royal header strip
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
                          const Icon(Icons.star_rounded, color: Color(0xFFD4AF37), size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Submit Feedback",
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
                          RichText(
                            text: TextSpan(
                              style: GoogleFonts.lato(color: Colors.black87, fontSize: 14),
                              children: [
                                const TextSpan(text: "Rating performance of "),
                                TextSpan(
                                  text: staffName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B2B48)),
                                ),
                                TextSpan(text: " ($staffRole)."),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          // Stars Selector
                          Center(
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(5, (index) {
                                    final starValue = index + 1;
                                    final isSelected = starValue <= rating;
                                    return GestureDetector(
                                      onTap: () {
                                        setState(() => rating = starValue);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 6),
                                        child: Icon(
                                          isSelected ? Icons.star_rounded : Icons.star_outline_rounded,
                                          color: isSelected ? const Color(0xFFD4AF37) : Colors.grey.shade400,
                                          size: 38,
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  ratingLabels[rating],
                                  style: GoogleFonts.lato(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: rating >= 4 
                                      ? const Color(0xFF2E7D32) 
                                      : rating == 3 
                                        ? const Color(0xFFE0B400) 
                                        : const Color(0xFFB71C1C),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          // Custom styled text area
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                )
                              ],
                            ),
                            child: TextField(
                              controller: controller,
                              maxLines: 3,
                              minLines: 2,
                              style: const TextStyle(fontSize: 14, color: Colors.black),
                              decoration: const InputDecoration(
                                hintText: "Write additional comments here (optional)...",
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
                              // Cancel
                              TextButton(
                                onPressed: isSubmitting ? null : () => Navigator.pop(context),
                                child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 12),
                              
                              // Submit skeuo button
                              InkWell(
                                onTap: isSubmitting
                                    ? null
                                    : () async {
                                        final msg = controller.text.trim();
                                        
                                        setState(() => isSubmitting = true);
                                        
                                        final res = await ApiService.submitFeedback(
                                          studentId: studentId,
                                          staffUsername: staffUsername,
                                          staffRole: staffRole,
                                          rating: rating,
                                          message: msg.isEmpty ? null : msg,
                                        );
                                        
                                        if (context.mounted) {
                                          setState(() => isSubmitting = false);
                                          Navigator.pop(context);
                                          
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(res['message'] ?? 'Action complete'),
                                              backgroundColor: res['success'] == true ? Colors.green : Colors.red,
                                            ),
                                          );
                                        }
                                      },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  decoration: SkeuomorphicStyles.glossyButton(
                                    isSubmitting
                                        ? const LinearGradient(colors: [Colors.grey, Colors.grey])
                                        : SkeuomorphicColors.goldGlossyGradient,
                                  ),
                                  child: isSubmitting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Text(
                                          "Submit",
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
