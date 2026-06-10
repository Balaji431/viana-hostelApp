import 'package:flutter/material.dart';
import '../../core/styles.dart';
import '../../core/api_service.dart';
import '../widgets/warden_widgets.dart';
import '../../core/models/room_change_request_model.dart';
import 'package:provider/provider.dart';
import '../../shared/user_provider.dart';

class PendingRenewalsModal extends StatefulWidget {
  const PendingRenewalsModal({super.key});

  @override
  State<PendingRenewalsModal> createState() => _PendingRenewalsModalState();
}

class _PendingRenewalsModalState extends State<PendingRenewalsModal> {
  final List<Map<String, String>> _pending = [
    {'name': 'Arjun Krishnan', 'room': 'A-204'},
    {'name': 'Rahul Sharma', 'room': 'B-105'},
    {'name': 'Vikram Singh', 'room': 'C-302'},
  ];

  void _removeStudent(int index) {
    setState(() => _pending.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20)],
          ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Pending Renewals', style: SkeuomorphicStyles.playfairHeader.copyWith(fontSize: 18, color: SkeuomorphicColors.residenceNavy)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(),
            if (_pending.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Text('No pending approvals.', style: TextStyle(color: Colors.grey)),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _pending.length,
                  itemBuilder: (context, index) => _buildStudentItem(_pending[index], index),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildStudentItem(Map<String, String> student, int index) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: SkeuomorphicStyles.skeuomorphicCard,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(student['name']!, style: SkeuomorphicStyles.playfairHeader.copyWith(fontSize: 14)),
                Text('Room: ${student['room']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          Row(
            children: [
              _buildCircularActionButton(Icons.close, Colors.red, () => _removeStudent(index)),
              const SizedBox(width: 8),
              _buildCircularActionButton(Icons.check, Colors.green, () => _removeStudent(index)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCircularActionButton(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle, border: Border.all(color: color.withOpacity(0.3))),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

class NewAnnouncementModal extends StatefulWidget {
  final Function(String, String) onPost;
  const NewAnnouncementModal({super.key, required this.onPost});

  @override
  State<NewAnnouncementModal> createState() => _NewAnnouncementModalState();
}

class _NewAnnouncementModalState extends State<NewAnnouncementModal> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    bool canPost = _titleController.text.isNotEmpty && _contentController.text.isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New Announcement', style: SkeuomorphicStyles.playfairHeader.copyWith(fontSize: 18, color: SkeuomorphicColors.residenceNavy)),
            const SizedBox(height: 20),
            SkeuomorphicInput(label: 'Title', hint: 'Enter announcement title...', controller: _titleController, onChanged: (_) => setState(() {})),
            const SizedBox(height: 15),
            SkeuomorphicInput(label: 'Content', hint: 'Enter details...', controller: _contentController, isTextArea: true, onChanged: (_) => setState(() {})),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
                const SizedBox(width: 15),
                SkeuomorphicButton(
                  disabled: !canPost,
                  onTap: () {
                    widget.onPost(_titleController.text, _contentController.text);
                    Navigator.pop(context);
                  },
                  child: const Text('Post', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
}



class EditConductModal extends StatefulWidget {
  final Map<String, dynamic> student;
  const EditConductModal({super.key, required this.student});

  @override
  State<EditConductModal> createState() => _EditConductModalState();
}

class _EditConductModalState extends State<EditConductModal> {
  late String _selectedConduct;
  late TextEditingController _remarksController;
  late TextEditingController _initialDueController;
  late TextEditingController _finalDueController;
  late String _status; // '1' for Active, '0' for Inactive
  DateTime? _validFrom;
  DateTime? _validTo;
  bool _isSaving = false;
  bool _isDeallocating = false;


  @override
  void initState() {
    super.initState();
    _selectedConduct = widget.student['conduct'] ?? 'Good';
    _remarksController = TextEditingController(text: widget.student['conduct_remarks'] ?? '');
    _initialDueController = TextEditingController(text: (widget.student['initial_due'] ?? 0).toString());
    _finalDueController = TextEditingController(text: (widget.student['final_due'] ?? 0).toString());
    _status = (widget.student['Status'] ?? 'active').toString();
    
    if (widget.student['valid_from'] != null && widget.student['valid_from'] != '0000-00-00') {
      try { _validFrom = DateTime.parse(widget.student['valid_from']); } catch (_) {}
    }
    if (widget.student['valid_to'] != null && widget.student['valid_to'] != '0000-00-00') {
      try { _validTo = DateTime.parse(widget.student['valid_to']); } catch (_) {}
    }
  }

  @override
  void dispose() {
    _remarksController.dispose();
    _initialDueController.dispose();
    _finalDueController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    final response = await ApiService.updateStudentDetails(
      studentId: int.parse(widget.student['id'].toString()),
      status: _status,
      conduct: _selectedConduct,
      remarks: _remarksController.text,
      initialDue: double.tryParse(_initialDueController.text),
      finalDue: double.tryParse(_finalDueController.text),
      validFrom: _validFrom != null ? _validFrom!.toIso8601String().split('T')[0] : null,
      validTo: _validTo != null ? _validTo!.toIso8601String().split('T')[0] : null,
    );
    
    if (mounted) {
      setState(() => _isSaving = false);
      if (response['success'] == true) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Student details updated successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${response['message']}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String name = widget.student['full_name'] ?? widget.student['name'] ?? 'Unknown';
    String room = widget.student['room_no'] ?? 'N/A';
    String initials = name.isNotEmpty ? name.split(' ').where((s)=>s.isNotEmpty).map((l)=>l[0]).take(2).join().toUpperCase() : "?";

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F6F1),
            borderRadius: BorderRadius.circular(25),
          ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Edit Student', style: SkeuomorphicStyles.playfairHeader.copyWith(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF1B2B48))),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 28),
                    style: IconButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.05)),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 15),
              Row(
                children: [
                  Container(
                    width: 55, height: 55,
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: SkeuomorphicColors.goldGlossyGradient),
                    child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: SkeuomorphicStyles.playfairHeader.copyWith(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1B2B48)), overflow: TextOverflow.ellipsis),
                        Text('Room $room', style: const TextStyle(color: Colors.grey, fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 25),
              _buildSectionTitle('Conduct Score'),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildConductBtn('Good', Colors.green),
                  const SizedBox(width: 10),
                  _buildConductBtn('Satisfactory', Colors.orange),
                  const SizedBox(width: 10),
                  _buildConductBtn('Poor', Colors.red),
                ],
              ),
              const SizedBox(height: 25),
              _buildSectionTitle('Remarks'),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.black12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
                ),
                child: TextField(
                  controller: _remarksController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.all(15),
                    border: InputBorder.none,
                    hintText: 'Add remarks...',
                  ),
                ),
              ),
              const SizedBox(height: 30),
              _buildDeallocateButton(),
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5D5D5D), fontSize: 16));
  }

  Widget _buildConductBtn(String label, Color color) {
    bool active = _selectedConduct == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedConduct = label),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.6) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? color : color.withOpacity(0.3), width: 1.5),
          ),
          child: Center(
            child: Text(label, style: TextStyle(color: active ? Colors.white : color, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ),
      ),
    );
  }

  Widget _buildDeallocateButton() {
    final room = widget.student['room_no'] ?? widget.student['room_allocation'];
    if (room == null || room == 'N/A' || room.toString().isEmpty || room == 'unallocated') {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: GestureDetector(
        onTap: _isDeallocating ? null : _handleDeallocate,
        child: Container(
          width: double.infinity,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.red.withOpacity(0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: _isDeallocating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.red,
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout_rounded, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Checkout / Deallocate Student',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleDeallocate() async {
    final name = widget.student['full_name'] ?? widget.student['name'] ?? 'Unknown';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: const Color(0xFFF9F6F1),
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(maxWidth: 350),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 50),
                const SizedBox(height: 15),
                Text(
                  'Confirm Checkout',
                  style: SkeuomorphicStyles.playfairHeader.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1B2B48),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Are you sure you want to checkout $name and deallocate them from their current room? This action cannot be undone.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black87, fontSize: 14),
                ),
                const SizedBox(height: 25),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Checkout', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirm != true) return;

    setState(() => _isDeallocating = true);

    try {
      final response = await ApiService.deallocateStudent(
        studentId: int.parse(widget.student['id'].toString()),
      );

      if (mounted) {
        setState(() => _isDeallocating = false);
        if (response['success'] == true) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Student checked out successfully'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${response['message']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDeallocating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exception: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildActionButtons() {

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              height: 50,
              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(15)),
              child: const Center(child: Text('Cancel', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold))),
            ),
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: GestureDetector(
            onTap: _isSaving ? null : _handleSave,
            child: Container(
              height: 50,
              decoration: BoxDecoration(gradient: SkeuomorphicColors.goldGlossyGradient, borderRadius: BorderRadius.circular(15)),
              child: Center(
                child: _isSaving 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class WardenRoomChangeDetailsModal extends StatefulWidget {
  final RoomChangeRequest request;
  final VoidCallback onActionComplete;

  const WardenRoomChangeDetailsModal({
    super.key,
    required this.request,
    required this.onActionComplete,
  });

  @override
  State<WardenRoomChangeDetailsModal> createState() => _WardenRoomChangeDetailsModalState();
}

class _WardenRoomChangeDetailsModalState extends State<WardenRoomChangeDetailsModal> {
  bool _isProcessing = false;

  Future<void> _updateStatus(String status) async {
    setState(() => _isProcessing = true);
    try {
      final user = context.read<UserProvider>();
      final response = await ApiService.updateRoomChangeRequest(
        requestId: widget.request.requestId,
        status: status,
        wardenId: user.dbId ?? 1,
      );

      if (response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Request $status successfully'),
              backgroundColor: status == 'approved' ? Colors.green : Colors.red,
            ),
          );
          Navigator.pop(context);
          widget.onActionComplete();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: ${response['message']}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F6F1),
            borderRadius: BorderRadius.circular(25),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Request Details", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48))),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const Divider(),
              const SizedBox(height: 15),
              _buildInfoTile("Student", widget.request.studentName, Icons.person_outline),
              _buildInfoTile("Reg No", widget.request.studentRegNo, Icons.badge_outlined),
              _buildInfoTile("Requested Type", widget.request.requestedRoomType ?? 'Standard', Icons.star_outline),
              const SizedBox(height: 15),
              const Text("Movement Details", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.black.withOpacity(0.05))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildRoomIndicator(widget.request.currentRoom, "Current"),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 15),
                      child: Icon(Icons.arrow_forward_rounded, color: Colors.grey),
                    ),
                    _buildRoomIndicator(widget.request.requestedRoom, "Target", isTarget: true),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text("Reason for Change", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Text(widget.request.reason, style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
              ),
              const SizedBox(height: 30),
              if (_isProcessing)
                const Center(child: CircularProgressIndicator())
              else
                Column(
                  children: [
                    if (widget.request.status.toLowerCase() == 'pending')
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _updateStatus('rejected'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade50,
                                foregroundColor: Colors.red,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                              child: const Text("Reject", style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _updateStatus('pre_approved'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD4AF37),
                                foregroundColor: Colors.white,
                                elevation: 2,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                              child: const Text("Pre-Approve", style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    if (widget.request.status.toLowerCase() == 'pre_approved')
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          "Awaiting Student Payment...",
                          style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
                        ),
                      ),
                    if (widget.request.status.toLowerCase() == 'paid')
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _finalizeAllocation(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF43A047),
                            foregroundColor: Colors.white,
                            elevation: 4,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                          child: const Text("Finalize Allocation", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _finalizeAllocation() async {
    setState(() => _isProcessing = true);
    try {
      final response = await ApiService.finalizeRoomChange(
        requestId: widget.request.requestId,
        studentId: widget.request.studentId,
        newRoomCode: widget.request.requestedRoom,
      );

      if (response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Room Allocation Finalized!'), backgroundColor: Colors.green),
          );
          Navigator.pop(context);
          widget.onActionComplete();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: ${response['message']}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }


  Widget _buildInfoTile(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoomIndicator(String room, String label, {bool isTarget = false}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(room, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isTarget ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48))),
      ],
    );
  }
}
