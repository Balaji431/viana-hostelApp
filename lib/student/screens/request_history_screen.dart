import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../shared/request_provider.dart';
import '../../shared/user_provider.dart';
import '../../shared/widgets/calendar_modal.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';

class RequestHistoryScreen extends StatefulWidget {
  final String? department;
  const RequestHistoryScreen({super.key, this.department});

  @override
  State<RequestHistoryScreen> createState() => _RequestHistoryScreenState();
}

class _RequestHistoryScreenState extends State<RequestHistoryScreen> {
  DateTime? _fromDate;
  DateTime? _toDate;
  String _statusFilter = 'All Statuses';
  String _sortBy = 'Newest First';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Provider.of<UserProvider>(context, listen: false);
      if (user.dbId != null) {
        Provider.of<RequestProvider>(context, listen: false).fetchRequests(user.dbId!);
      }
    });
  }

  DateTime? _parseDate(String dateStr) {
    if (dateStr == 'N/A') return null;
    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      try {
        if (dateStr.contains(' at ')) {
          final parts = dateStr.split(' at ');
          final dateParts = parts[0].split('/');
          final timeParts = parts[1].split(' ');
          final hm = timeParts[0].split(':');
          
          int hour = int.parse(hm[0]);
          int minute = int.parse(hm[1]);
          if (timeParts[1].toUpperCase() == 'PM' && hour < 12) hour += 12;
          if (timeParts[1].toUpperCase() == 'AM' && hour == 12) hour = 0;

          return DateTime(
            int.parse(dateParts[2]), 
            int.parse(dateParts[1]), 
            int.parse(dateParts[0]),
            hour, 
            minute
          );
        }
      } catch (e) {
        debugPrint("Error parsing date: $dateStr - $e");
      }
    }
    return null;
  }

  List<RequestItem> _getFilteredRequests(List<RequestItem> allRequests) {
    List<RequestItem> filtered = allRequests.where((req) {
      // 1. Filter out dummy General Inquiry requests auto-created for initializing chat
      final isDummyGeneralInquiry = req.title.toLowerCase() == 'general inquiry' &&
          (req.purpose?.toLowerCase().startsWith('new chat started') == true ||
           req.purpose?.toLowerCase().startsWith('new parent chat started') == true ||
           req.purpose?.toLowerCase() == 'auto-created via chat');
      if (isDummyGeneralInquiry) return false;

      // 2. Filter by department if widget.department is provided
      if (widget.department != null) {
        final reqDept = req.department?.toLowerCase() ?? '';
        final targetDept = widget.department!.toLowerCase();
        if (targetDept == 'warden') {
          if (reqDept != 'warden' && reqDept != 'parent_warden') {
            return false;
          }
        } else {
          if (reqDept != targetDept) {
            return false;
          }
        }
      }

      final reqDate = _parseDate(req.date);
      
      if (_statusFilter != 'All Statuses') {
        if (req.status.toLowerCase() != _statusFilter.toLowerCase()) {
          return false;
        }
      }

      if (reqDate != null) {
        if (_fromDate != null) {
          final start = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
          if (reqDate.isBefore(start)) return false;
        }
        if (_toDate != null) {
          final end = DateTime(_toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59);
          if (reqDate.isAfter(end)) return false;
        }
      }

      return true;
    }).toList();

    filtered.sort((a, b) {
      final dateA = _parseDate(a.date) ?? DateTime(1970);
      final dateB = _parseDate(b.date) ?? DateTime(1970);
      if (_sortBy == 'Newest First') {
        return dateB.compareTo(dateA);
      } else {
        return dateA.compareTo(dateB);
      }
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final requestProvider = context.watch<RequestProvider>();
    final allRequests = requestProvider.requests;
    final requests = _getFilteredRequests(allRequests);

    return Scaffold(
      backgroundColor: const Color(0xFFE8E4DB),
      appBar: SkeuomorphicNavBar(
        title: 'Request History',
        onBack: () => Navigator.pop(context),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            children: [
              _buildFilters(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                   child: Text('${requests.length} requests found', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ),
              ),
              Expanded(
                child: requests.isEmpty 
                  ? const Center(child: Text('No requests found for these filters.', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: requests.length,
                      itemBuilder: (context, index) {
                        final req = requests[index];
                        return _buildHistoryCard(
                          title: req.title,
                          id: req.id,
                          date: req.date,
                          status: req.status,
                          isResolved: req.isResolved,
                          rating: req.rating,
                          comment: req.comment,
                        );
                      },
                    ),
              ),
              _buildCancelButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F1E9),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildDateField('FROM', _fromDate, (date) => setState(() => _fromDate = date)),
              const SizedBox(width: 15),
              _buildDateField('TO', _toDate, (date) => setState(() => _toDate = date)),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
               _buildStatusDropdown(),
              const SizedBox(width: 15),
               _buildSortDropdown(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateField(String label, DateTime? value, Function(DateTime?) onSelected) {
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          final DateTime? picked = await showDialog<DateTime>(
            context: context,
            builder: (context) => UniversalCalendarModal(initialDate: value ?? DateTime.now()),
          );
          onSelected(picked);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black.withOpacity(0.05)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    value == null ? 'dd-mm-yyyy' : DateFormat('dd-MM-yyyy').format(value), 
                    style: TextStyle(fontSize: 13, color: value == null ? Colors.grey : const Color(0xFF1B2B48))
                  ),
                  const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.black54),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDropdown() {
    final List<String> statuses = ['All Statuses', 'Pending', 'Approved', 'Rejected'];
    
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('STATUS', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          PopupMenuButton<String>(
            onSelected: (val) => setState(() => _statusFilter = val),
            itemBuilder: (context) => statuses.map((s) => PopupMenuItem(value: s, child: Text(s))).toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black.withOpacity(0.05)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_statusFilter, style: const TextStyle(fontSize: 13, color: Color(0xFF1B2B48))),
                  const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortDropdown() {
    final List<String> options = ['Newest First', 'Oldest First'];
    
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SORT BY', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          PopupMenuButton<String>(
            onSelected: (val) => setState(() => _sortBy = val),
            itemBuilder: (context) => options.map((o) => PopupMenuItem(value: o, child: Text(o))).toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black.withOpacity(0.05)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.swap_vert, size: 16, color: Colors.grey),
                  const SizedBox(width: 5),
                  Text(_sortBy, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF5D5D5D))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard({
    required String title,
    required String id,
    required String date,
    required String status,
    required bool isResolved,
    int? rating,
    String? comment,
  }) {
    Color statusColor;
    String displayStatus = status.toUpperCase();
    
    final s = status.toLowerCase();
    if (s == 'completed') {
      statusColor = const Color(0xFF4CAF50);
    } else if (s == 'approved') {
      statusColor = const Color(0xFF4CAF50);
      displayStatus = 'APPROVED';
    } else if (s == 'rejected') {
      statusColor = const Color(0xFFE57373);
    } else if (s == 'pending' || s == 'fixed' || s == 'reopened') {
      statusColor = const Color(0xFFFF9800);
      displayStatus = 'PENDING';
    } else {
      statusColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Text(
                  displayStatus,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          Text(id, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 10),
          Text(date, style: const TextStyle(color: Color(0xFF8A9AAB), fontSize: 14)),
          if (rating != null && rating > 0) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1),
            ),
            Row(
              children: List.generate(
                5,
                (index) => Icon(
                  index < rating ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                  size: 18,
                ),
              ),
            ),
            if (comment != null && comment.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text('"$comment"', style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildCancelButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: const Center(
            child: Text(
              'Done',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87),
            ),
          ),
        ),
      ),
    );
  }
}
