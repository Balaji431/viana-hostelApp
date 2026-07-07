import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/user_provider.dart';
import '../../shared/category_provider.dart';
import '../../core/api_service.dart';
import '../../core/notification_service.dart';
import '../../core/services/chat_cache_service.dart';
import '../../core/models/request_model.dart';
import '../../shared/chat/request_card.dart';
import '../../shared/chat/request_details_screen.dart';
import '../../shared/request_provider.dart';
import 'request_history_screen.dart';
import '../../shared/ui_provider.dart';
import '../../shared/chat/call_log_card.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../core/styles.dart';
import '../../shared/widgets/complaint_feedback_dialogs.dart';

class SecurityChatScreen extends StatefulWidget {
  final String? requestId;
  final String department;
  const SecurityChatScreen({super.key, this.requestId, this.department = 'Security'});

  @override
  State<SecurityChatScreen> createState() => _SecurityChatScreenState();
}

class _SecurityChatScreenState extends State<SecurityChatScreen> {
  String _assignedStaffName = 'Security';
  String? _assignedStaffUsername;
  bool _isAssigned = true;
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();

  String? _selectedCategory;
  String _currentFilter = 'All';
  final TextEditingController _messageController = TextEditingController();
  bool _isTyping = false;
  bool _isSending = false;
  Timer? _timer;
  String? _activeRequestId;
  int _offset = 0;
  final int _limit = 50;
  bool _isMoreLoading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _activeRequestId = widget.requestId;
    _messageController.addListener(_onMessageChanged);
    _scrollController.addListener(_onScroll);
    _initializeChat();
    NotificationService.fcmRefreshNotifier.addListener(_fetchMessages);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<UserProvider>();
      final catProvider = context.read<CategoryProvider>();
      // Instantly zero the badge — don't wait for API poll
      catProvider.setUnreadCount(widget.department, 0);
      if (_activeRequestId != null && user.username.isNotEmpty) {
        ApiService.markRead(_activeRequestId!, user.username);
      }
    });
  }

  void _onScroll() {
    if (_hasMore && !_isMoreLoading && _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _fetchMoreMessages();
    }
  }

  Future<void> _initializeChat() async {
    final user = context.read<UserProvider>();
    final catProvider = context.read<CategoryProvider>();
    if (user.dbId == null) return;

    final deptKey = widget.department.toLowerCase();
    bool isAssigned = false;

    if (catProvider.assignedStaff.containsKey(deptKey) && catProvider.assignedStaff[deptKey] != null) {
      isAssigned = true;
      if (mounted) {
        setState(() {
          _assignedStaffName = catProvider.assignedStaff[deptKey]['name'] ?? widget.department;
          _assignedStaffUsername = catProvider.assignedStaff[deptKey]['username']?.toString();
          _isAssigned = true;
        });
      }
    }

    if (_activeRequestId == null) {
      final response = await ApiService.getLatestRequestId(user.dbId!, widget.department.toLowerCase());
      if (response['success'] == true && response['request_id'] != null) {
        setState(() {
          _activeRequestId = response['request_id'].toString();
        });
      }
    }

    _loadLocalMessages();

    // Call this asynchronously in the background so it doesn't block loading
    ApiService.getAssignedStaff(user.dbId!).then((staffRes) {
      if (staffRes['success'] == true && staffRes['data'] != null && staffRes['data'][deptKey] != null) {
        if (mounted) {
          setState(() {
            _assignedStaffName = staffRes['data'][deptKey]['name'] ?? widget.department;
            _assignedStaffUsername = staffRes['data'][deptKey]['username']?.toString();
            _isAssigned = true;
          });
        }
      } else {
        if (!isAssigned && mounted) {
          setState(() {
            _assignedStaffName = "${widget.department} (Not Assigned)";
            _assignedStaffUsername = null;
            _isAssigned = false;
          });
        }
      }
    }).catchError((e) {
      if (!isAssigned && mounted) {
        setState(() {
          _assignedStaffName = "${widget.department} (Not Assigned)";
          _assignedStaffUsername = null;
          _isAssigned = false;
        });
      }
    });

    _fetchMessages();
    _startTimer();
  }

  void _loadLocalMessages() {
    final local = ChatCacheService.loadMessages(widget.department.toLowerCase());
    setState(() {
      _messages.clear();
      _messages.addAll(local.reversed.toList());
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        _fetchMessages(silent: true);
      }
    });
  }

  DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp == null || timestamp == 'null' || timestamp == '') return DateTime.now();
    try {
      String ts = timestamp.toString();
      if (!ts.contains('T') && ts.contains(' ')) ts = ts.replaceFirst(' ', 'T');
      return DateTime.parse(ts);
    } catch (e) {
      return DateTime.now();
    }
  }

  Future<void> _fetchMessages({bool silent = false}) async {
    try {
      final user = context.read<UserProvider>();
      if (user.dbId == null) return;

      final response = await ApiService.getDepartmentChat(user.dbId!, widget.department.toLowerCase(), limit: _limit, offset: 0, silent: silent);
      if (response['success'] == true) {
        final List<dynamic> data = response['data'] ?? [];
        if (mounted) {
          if (data.isEmpty) {
            final hasRealMsgs = _messages.any((m) => m['id'] != null && !m['id'].toString().startsWith('local'));
            if (!hasRealMsgs && _messages.isEmpty) {
              setState(() {
                _messages.add({
                  'type': 'text',
                  'sender': 'officer',
                  'content': 'Security Desk. Please state your issue or report an emergency.',
                  'timestamp': DateTime.now().toIso8601String(),
                });
              });
            }
            return;
          }

          setState(() {
            final List<Map<String, dynamic>> updatedList = [];
            
            for (var msg in data) {
              if (msg['id'] == null) continue;
              
              String type = 'text';
              String messageType = msg['message_type']?.toString() ?? "";
              if (messageType == 'request' || messageType == 'request_card') {
                type = 'request';
              } else if (messageType == 'status' || messageType == 'admin_reply') {
                type = 'admin_reply';
              } else if (messageType == 'call') {
                type = 'call';
              }

              updatedList.add({
                'type': type,
                'message_type': msg['message_type'] ?? 'request_card',
                'sender': (msg['sender_id']?.toString() == user.dbId?.toString() || msg['sender_id'] == user.username) ? 'student' : 'officer',
                'content': msg['message']?.toString() ?? 'New Request',
                'request_data': msg,
                'id': msg['id'].toString(),
                'request_id': msg['request_id'] ?? msg['req_id'],
                'category': msg['request_type'],
                'status': msg['status']?.toString() ?? 'sent',
                'timestamp': msg['timestamp'],
              });
            }

            for (var localMsg in _messages) {
              final localId = localMsg['id']?.toString() ?? "";
              if (localId.startsWith('local_')) {
                bool matchesServer = updatedList.any((s) => 
                  (s['content'].toString().trim().toLowerCase() == localMsg['content'].toString().trim().toLowerCase() &&
                   s['sender'] == 'student') ||
                  (s['type'] == 'request' &&
                   localMsg['type'] == 'request' &&
                   (s['request_id']?.toString() == localMsg['request_id']?.toString() ||
                    s['category']?.toString().toLowerCase() == localMsg['category']?.toString().toLowerCase()))
                );
                if (!matchesServer) {
                  updatedList.add(localMsg);
                }
              }
            }

            updatedList.sort((a, b) =>
              _parseTimestamp(b['timestamp']).compareTo(_parseTimestamp(a['timestamp'])));

            _messages.clear();
            _messages.addAll(updatedList);

            bool hasIncoming = data.any((msg) =>
              msg['sender_id']?.toString() != user.username &&
              msg['sender_id']?.toString() != user.dbId?.toString() &&
              msg['status'] != 'seen'
            );
            if (hasIncoming && _activeRequestId != null && mounted && user.username.isNotEmpty) {
              ApiService.markRead(_activeRequestId!, user.username);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching security messages: $e');
    }
  }

  Future<void> _fetchMoreMessages() async {
    if (_isMoreLoading || !_hasMore) return;

    setState(() => _isMoreLoading = true);
    await Future.delayed(const Duration(seconds: 1));

    try {
      final user = context.read<UserProvider>();
      final nextOffset = _offset + _limit;
      final response = await ApiService.getDepartmentChat(user.dbId!, widget.department.toLowerCase(), limit: _limit, offset: nextOffset);
      
      if (response['success'] == true) {
        final List<dynamic> data = response['data'] ?? [];
        if (data.length < _limit) _hasMore = false;

        if (data.isNotEmpty) {
          final List<Map<String, dynamic>> olderMessages = [];
          for (var msg in data) {
            String type = 'text';
            String messageType = msg['message_type']?.toString() ?? "";
            
            if (messageType == 'request' || messageType == 'request_card' || msg['id'] == null) {
              type = 'request';
            } else if (messageType == 'status' || messageType == 'admin_reply') {
              type = 'admin_reply';
            } else if (messageType == 'call') {
              type = 'call';
            }
            
            olderMessages.add({
              'type': type,
              'message_type': msg['message_type'] ?? 'request_card',
              'sender': (msg['sender_id'].toString() == user.dbId.toString() || msg['sender_id'] == user.username) ? 'student' : 'officer',
              'content': msg['message']?.toString() ?? 'New Request',
              'request_data': (type == 'request') ? msg : null,
              'id': msg['id'],
              'request_id': msg['request_id'] ?? msg['req_id'],
              'category': msg['request_type'],
              'status': msg['status']?.toString() ?? 'sent',
              'timestamp': msg['timestamp'],
            });
          }

          setState(() {
            _messages.addAll(olderMessages);
            _offset = nextOffset;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading more security messages: $e');
    } finally {
      if (mounted) setState(() => _isMoreLoading = false);
    }
  }

  String _formatTimestampForTime(dynamic timestamp) {
    return DateFormat('hh:mm a').format(_parseTimestamp(timestamp));
  }

  String _formatTimestampForDate(dynamic timestamp) {
    final date = _parseTimestamp(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDate = DateTime(date.year, date.month, date.day);
    if (msgDate == today) return 'Today';
    if (msgDate == yesterday) return 'Yesterday';
    return DateFormat('dd MMMM yyyy').format(date);
  }

  @override
  void dispose() {
    NotificationService.fcmRefreshNotifier.removeListener(_fetchMessages);
    _timer?.cancel();
    _messageController.removeListener(_onMessageChanged);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onMessageChanged() {
    final isTyping = _messageController.text.trim().isNotEmpty;
    if (isTyping != _isTyping) {
      setState(() => _isTyping = isTyping);
    }
  }

  Widget getStatusIcon(String status) {
    if (status == 'sending') {
      return const Icon(Icons.access_time, size: 14, color: Colors.grey);
    } else if (status == 'sent') {
      return const Icon(Icons.check, size: 14, color: Colors.grey);
    } else if (status == 'delivered') {
      return const Icon(Icons.done_all, size: 14, color: Colors.grey);
    } else if (status == 'seen') {
      return const Icon(Icons.done_all, size: 14, color: Colors.blue);
    }
    return const SizedBox();
  }

  List<Map<String, dynamic>> get _filteredMessages {
    if (_currentFilter == 'All') return _messages.where((m) => m['type'] != 'call').toList();
    if (_currentFilter == 'Calls') return _messages.where((m) => m['type'] == 'call').toList();
    return _messages.where((m) => 
      m['type'] == 'request' &&
      m['category'] != null && 
      m['category'].toString().toLowerCase() == _currentFilter.toLowerCase()
    ).toList();
  }

  void _handleSendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
      _isTyping = false;
    });

    final user = context.read<UserProvider>();
    final tempMsg = {
      'id': 'local_${DateTime.now().millisecondsSinceEpoch}',
      'content': messageText,
      'sender': 'student',
      'sender_id': user.dbId.toString(),
      'timestamp': DateTime.now().toIso8601String(),
      'type': 'text',
      'status': 'sending',
    };

    ChatCacheService.saveMessage(widget.department.toLowerCase(), tempMsg);
    setState(() {
      _messages.insert(0, tempMsg);
    });

    _messageController.clear();

    if (_activeRequestId == null) {
      ApiService.createServiceRequest(
        studentId: user.dbId!,
        department: widget.department.toLowerCase(),
        requestType: 'General Inquiry',
        purpose: 'New chat started: $messageText',
        roomNumber: user.roomNumber,
        skipMessage: true,
      ).then((response) {
        if (response['success'] == true) {
          _activeRequestId = response['request_id'].toString();
          ApiService.sendChatMessage(_activeRequestId!, user.username.isNotEmpty ? user.username : 'unknown', messageText, department: widget.department.toLowerCase());
          
          if (user.username.isNotEmpty) {
            ApiService.markRead(_activeRequestId!, user.username);
          }
          _fetchMessages();
          _startTimer();
        }
      }).catchError((e) {
        debugPrint("Create request failed: $e");
      });
    } else {
      ApiService.sendChatMessage(_activeRequestId!, user.username.isNotEmpty ? user.username : 'unknown', messageText, department: widget.department.toLowerCase())
        .then((response) {
          if (response['success'] == true) {
            setState(() {
              int index = _messages.indexWhere((m) => m['id'] == tempMsg['id']);
              if (index != -1) {
                _messages[index]['status'] = 'sent';
              }
            });
            _fetchMessages();
          }
        }).catchError((e) {
          debugPrint("Send message failed: $e");
        });
    }

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    });
  }

  void _addRequest(String category, Map<String, String> details) async {
    final user = context.read<UserProvider>();
    final requestTime = DateFormat('hh:mm a').format(DateTime.now());
    
    if (user.dbId == null) return;

    final tempReqId = 'local_req_${DateTime.now().millisecondsSinceEpoch}';
    final tempReq = {
      'id': tempReqId,
      'req_id': tempReqId,
      'request_id': tempReqId,
      'student_id': user.dbId.toString(),
      'sender_id': user.dbId.toString(),
      'message': details['purpose'] ?? "Requested $category",
      'request_type': category,
      'category': category,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
      'timestamp': DateTime.now().toIso8601String(),
      'message_type': 'request',
      'sender': 'student',
      'type': 'request',
      'room_number': user.fullRoomDetails,
    };

    setState(() {
      _messages.insert(0, tempReq);
      _isSending = true;
    });

    final response = await ApiService.createServiceRequest(
      studentId: user.dbId!,
      department: widget.department.toLowerCase(),
      requestType: category,
      purpose: details['purpose'] ?? "Requested $category",
      destination: details['destination'],
      roomNumber: user.fullRoomDetails,
    );

    if (mounted) setState(() => _isSending = false);

    if (response['success'] == true) {
      final fullId = response['request_id'].toString();
      setState(() {
        _activeRequestId = fullId;
        int idx = _messages.indexWhere((m) => m['id'] == tempReqId);
        if (idx != -1) {
          _messages[idx] = {
            ..._messages[idx],
            'id': fullId,
            'request_id': fullId,
            'status': 'sent',
          };
        }
      });
      
      if (user.username.isNotEmpty) {
        ApiService.markRead(fullId, user.username);
      }
      _fetchMessages(); 
      _startTimer();
      
      Provider.of<RequestProvider>(context, listen: false).addRequest(
        RequestItem(
          title: category,
          id: fullId,
          date: '${DateFormat('d/M/yyyy').format(DateTime.now())} at $requestTime',
          status: 'Pending',
          isResolved: false,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LinenGridBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: SkeuomorphicNavBar(
          title: _assignedStaffName,
          onTitleLongPress: () {
            if (!_isAssigned || _assignedStaffUsername == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No staff member is currently assigned to you.')),
              );
              return;
            }
            final user = context.read<UserProvider>();
            final studentId = user.isParent ? (user.linkedStudentId ?? 0) : (user.dbId ?? 0);
            if (studentId == 0) return;
            
            ComplaintFeedbackHelper.showComplaintFeedbackMenu(
              context,
              staffName: _assignedStaffName,
              staffUsername: _assignedStaffUsername!,
              staffRole: widget.department.toLowerCase(),
              studentId: studentId,
            );
          },
          onBack: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              context.read<UIProvider>().setActiveChatChannel(null);
            }
          },
          rightAction: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.history, color: Colors.white, size: 22),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RequestHistoryScreen(department: 'security'))),
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.phone_outlined, color: Colors.white, size: 22),
                onPressed: _launchDialer,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
            children: [
              _buildSubHeader(),
              if (!_isAssigned)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFCCCC)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFD32F2F), size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${widget.department} has not been assigned to your hostel block/wing yet. Please contact the administrator.',
                          style: const TextStyle(
                            color: Color(0xFFC62828),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              _buildFilterChips(),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
                  itemCount: _filteredMessages.length + (_isMoreLoading ? 1 : 0) + (!_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _filteredMessages.length && _isMoreLoading) {
                      return const Center(child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator()));
                    }
                    if (index == _filteredMessages.length + (_isMoreLoading ? 1 : 0) && !_hasMore) {
                      return Center(child: Padding(padding: EdgeInsets.all(10), child: Text("All messages loaded", style: TextStyle(color: Colors.grey, fontSize: 11))));
                    }

                    final msgIndex = index;
                    if (msgIndex >= _filteredMessages.length) return const SizedBox.shrink();
                    
                    final msg = _filteredMessages[msgIndex];
                    String? nextDate;
                    if (msgIndex + 1 < _filteredMessages.length) {
                      nextDate = _formatTimestampForDate(_filteredMessages[msgIndex + 1]['timestamp']);
                    }
                    final currDate = _formatTimestampForDate(msg['timestamp']);

                    List<Widget> children = [];
                    if (nextDate == null || nextDate != currDate) {
                      children.add(_buildDateSeparator(currDate));
                    }

                    if (msg['type'] == 'text') {
                      children.add(_buildTextMessage(msg));
                    } else if (msg['type'] == 'call') {
                      children.add(_buildCallMessage(msg));
                    } else if (msg['type'] == 'admin_reply') {
                      children.add(_buildAdminActionCard(msg));
                    } else {
                      children.add(_buildRequestCard(msg));
                    }
                    
                    return Column(children: children);
                  },
                ),
              ),
              _buildBottomInputDesign(),
            ],
          ),
        ),
      ),
    ),
  );
}

  void _launchDialer() async {
    try {
      final user = context.read<UserProvider>();
      final response = await ApiService.getAssignedStaff(user.dbId!);
      String? staffPhone;
      
      final deptKey = widget.department.toLowerCase();
      if (response['success'] == true && response['data'] != null && response['data'][deptKey] != null) {
        staffPhone = response['data'][deptKey]['phone']?.toString();
      }
      
      if (staffPhone == null || staffPhone.isEmpty) {
        final fallbackRes = await ApiService.getUserData(3);
        if (fallbackRes['success'] == true && fallbackRes['data']['phone'] != null) {
          staffPhone = fallbackRes['data']['phone']?.toString();
        }
      }

      if (staffPhone != null && staffPhone.isNotEmpty) {
        final Uri telUri = Uri.parse('tel:${staffPhone.replaceAll(' ', '')}');
        await launchUrl(telUri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${widget.department} phone number not found')),
          );
        }
      }
    } catch (e) {
      debugPrint("Error launching dialer: $e");
    }
  }

  Widget _buildSubHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.black.withOpacity(0.05))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            context.read<UserProvider>().fullRoomDetails.toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5D5D5D), letterSpacing: 0.5, fontFamily: 'Lato'),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildDateSeparator(String date) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(20)),
        child: Text(date, style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = ['All'];
    final securityCodes = context.read<CategoryProvider>()
        .categories
        .where((c) => c['name'] == widget.department)
        .expand((c) => (c['codes'] as List).map((code) => code.toString()))
        .toList();
    filters.addAll(securityCodes);

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: const Color(0xFFF0EDE5),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final isSelected = _currentFilter == filters[index];
          return GestureDetector(
            onTap: () => setState(() => _currentFilter = filters[index]),
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1B2B48) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? Colors.transparent : Colors.black.withOpacity(0.1)),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
              ),
              child: Row(
                children: [
                  if (filters[index] == 'All') Icon(Icons.chat_bubble_outline, size: 14, color: isSelected ? Colors.white : Colors.grey),
                  if (filters[index] == 'Calls') Icon(Icons.phone_outlined, size: 14, color: isSelected ? Colors.white : Colors.grey),
                  if (filters[index] != 'All' && filters[index] != 'Calls')
                    Icon(filters[index].toLowerCase().contains('emergency') ? Icons.warning_amber_outlined : Icons.assignment_outlined, size: 14, color: isSelected ? Colors.white : Colors.grey),
                  const SizedBox(width: 6),
                  Text(filters[index], style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : const Color(0xFF5D5D5D))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAdminActionCard(Map<String, dynamic> msg) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          msg['content']?.toString() ?? '',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: Colors.black.withOpacity(0.5),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildTextMessage(Map<String, dynamic> msg) {
    bool isMe = msg['sender'] == 'student';
    final content = msg['content']?.toString() ?? '';
    final timestamp = msg['timestamp'] ?? DateTime.now().toIso8601String();
    final status = msg['status']?.toString() ?? 'sent';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          decoration: BoxDecoration(
            color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(10),
              topRight: const Radius.circular(10),
              bottomLeft: Radius.circular(isMe ? 10 : 2),
              bottomRight: Radius.circular(isMe ? 2 : 10),
            ),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))
            ],
          ),
          child: IntrinsicWidth(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(content,
                      style: const TextStyle(fontSize: 14, height: 1.2, color: Colors.black87)),
                ),
                const SizedBox(width: 6),
                Text(
                  _formatTimestampForTime(timestamp),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  getStatusIcon(status),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCallMessage(Map<String, dynamic> msg) {
    String duration = "00:00";
    final content = msg['content']?.toString() ?? '';
    if (content.contains('Duration:')) {
      duration = content.split('Duration:').last.trim();
    }
    return CallLogCard(
      title: msg['sender'] == 'student' ? "Called ${widget.department}" : widget.department,
      subtitle: _formatTimestampForTime(msg['timestamp'] ?? DateTime.now().toIso8601String()),
      duration: duration
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> msg) {
    final request = RequestModel.fromJson(msg['request_data'] ?? msg);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: RequestCard(
        request: request,
        isMe: msg['sender'] == 'student' || msg['sender'] == 'user' || msg['sender_id']?.toString() != 'security',
        onTap: () async {
          final response = await ApiService.getRequestDetails(request.customId);
          if (response['success'] == true) {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              barrierColor: Colors.transparent,
              useRootNavigator: false,
              builder: (context) => FractionallySizedBox(
                heightFactor: 0.85,
                child: RequestDetailsScreen(request: RequestModel.fromJson(response['data']), canAction: false),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildBottomInputDesign() {
    if (!_isAssigned) {
      return Container(
        padding: const EdgeInsets.fromLTRB(15, 10, 15, 30),
        color: Colors.white,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, color: Colors.grey.shade600, size: 18),
              const SizedBox(width: 8),
              Text(
                'Chat disabled: ${widget.department} not assigned',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_currentFilter != 'All') {
      return Container(
        padding: const EdgeInsets.fromLTRB(15, 10, 15, 30),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.black12)),
        ),
        child: GestureDetector(
          onTap: _showCategoryPicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('Select a request category...'),
                Icon(Icons.keyboard_arrow_down),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 30),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.black12))),
      child: Column(
        children: [
          if (_currentFilter != 'Calls')
            GestureDetector(
              onTap: _showCategoryPicker,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_selectedCategory ?? 'Select a request category...', style: TextStyle(color: _selectedCategory == null ? Colors.grey : const Color(0xFF1B2B48), fontWeight: FontWeight.bold)),
                    const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.grey.shade300)),
                  child: TextField(
                    controller: _messageController,
                    enabled: _currentFilter == 'All', 
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      filled: false,
                      hintText: 'Type a message',
                      hintStyle: TextStyle(color: Colors.black, fontSize: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: (_isTyping && !_isSending) ? _handleSendMessage : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: (_isTyping && !_isSending) ? Colors.blue : Colors.grey.shade200, shape: BoxShape.circle),
                    child: Icon(Icons.send, color: (_isTyping && !_isSending) ? Colors.white : Colors.grey, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCategoryPicker() {
    final catProvider = context.read<CategoryProvider>();
    final securityCat = catProvider.getCategoryByName('Security');

    final allCodes = securityCat != null 
        ? List<String>.from(securityCat['codes']) 
        : ['Gate Security', 'Night Patrol'];

    List<String> codes = [];
    if (_currentFilter == 'All') {
      codes = allCodes;
    } else {
      codes = [_currentFilter];
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent, 
      useRootNavigator: false, 
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              decoration: const BoxDecoration(
                color: Color(0xFF3B5998),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))
              ),
              child: const Text('Select a request category...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            ...codes.map((cat) => ListTile(
              title: Text(cat),
              onTap: () {
                Navigator.pop(context);
                setState(() => _selectedCategory = cat);
                _showNewRequestModal(cat);
              },
            )),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showNewRequestModal(String category) {
    showDialog(
      context: context,
      builder: (context) => _NewRequestDialog(category: category, onSubmit: (details) { 
        _addRequest(category, details); 
        setState(() => _selectedCategory = null); 
      }),
    );
  }
}

class _NewRequestDialog extends StatefulWidget {
  final String category;
  final Function(Map<String, String>) onSubmit;
  const _NewRequestDialog({required this.category, required this.onSubmit});
  @override
  State<_NewRequestDialog> createState() => _NewRequestDialogState();
}

class _NewRequestDialogState extends State<_NewRequestDialog> {
  final _purposeController = TextEditingController();
  final _destinationController = TextEditingController();
  bool _hasError = false;
  String _errorMessage = "";
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.only(bottom: 15),
              child: Text(
                'New ${widget.category}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1B2B48),
                  fontFamily: 'Lato',
                ),
              ),
            ),
            _buildTextField(_purposeController, "Describe the issue...", maxLines: 4),
            if (widget.category.toLowerCase().contains('exit') || 
                widget.category.toLowerCase().contains('late entry') ||
                widget.category.toLowerCase().contains('gate pass')) ...[
              const SizedBox(height: 10),
              _buildTextField(_destinationController, "Destination (if applicable)"),
            ],
            if (_hasError) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () {
                    if (_purposeController.text.trim().isEmpty) {
                      setState(() {
                        _hasError = true;
                        _errorMessage = "Please describe the issue";
                      });
                      return;
                    }
                    Navigator.pop(context);
                    widget.onSubmit({
                      'purpose': _purposeController.text.trim(),
                      'destination': _destinationController.text.trim(),
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B2B48),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Submit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, {int maxLines = 1}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF1B2B48), width: 2),
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
          contentPadding: const EdgeInsets.all(12),
        ),
      ),
    );
  }
}
