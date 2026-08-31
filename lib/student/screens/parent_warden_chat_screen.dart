import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/user_provider.dart';
import '../../core/api_service.dart';
import '../../core/notification_service.dart';
import '../../core/websocket_service.dart';
import '../../shared/chat/request_card.dart';
import '../../shared/chat/request_details_screen.dart';
import '../../core/models/request_model.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../core/styles.dart';
import '../../shared/ui_provider.dart';


class ParentWardenChatScreen extends StatefulWidget {
  final String? requestId;
  final String department;
  const ParentWardenChatScreen({super.key, this.requestId, this.department = 'Warden'});

  @override
  State<ParentWardenChatScreen> createState() => _ParentWardenChatScreenState();
}

class _ParentWardenChatScreenState extends State<ParentWardenChatScreen> {
  bool _isAssigned = true;
  String _assignedStaffName = 'Warden';
  String? _assignedStaffUsername;
  String? _wardenPhone;
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController(); 
  final TextEditingController _messageController = TextEditingController();
  bool _isTyping = false;
  Timer? _timer;
  StreamSubscription? _wsSubscription;
  VoidCallback? _wsConnListener;
  String? _activeRequestId;
  int _offset = 0;
  final int _limit = 50;
  bool _isMoreLoading = false;
  bool _hasMore = true;
  String _currentFilter = 'All';

  @override
  void initState() {
    super.initState();
    _activeRequestId = widget.requestId;
    _messageController.addListener(_onMessageChanged);
    _scrollController.addListener(_onScroll);
    _initializeChat();
    NotificationService.fcmRefreshNotifier.addListener(_fetchMessages);

    // WebSocket real-time subscription
    _wsSubscription = WebSocketService.instance.onNewMessage.listen(_onWebSocketMessage);
    _wsConnListener = () {
      if (mounted) {
        if (WebSocketService.instance.isConnected) {
          _fetchMessages(silent: true);
        }
        _startTimer();
      }
    };
    WebSocketService.instance.isConnectedNotifier.addListener(_wsConnListener!);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_activeRequestId != null) {
        final user = context.read<UserProvider>();
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
    final int? effectiveId = user.linkedStudentId;
    if (effectiveId == null) return;

    ApiService.getAssignedStaff(effectiveId).then((staffRes) {
      if (staffRes['success'] == true && staffRes['data'] != null && staffRes['data']['warden'] != null) {
        final wardenData = staffRes['data']['warden'];
        if (mounted) {
          setState(() {
            _isAssigned = true;
            _wardenPhone = wardenData['phone']?.toString();
            _assignedStaffName = wardenData['name'] ?? 'Warden';
            _assignedStaffUsername = wardenData['username']?.toString();
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isAssigned = false;
            _wardenPhone = null;
            _assignedStaffName = 'Warden';
            _assignedStaffUsername = null;
          });
        }
      }
    }).catchError((_) {
      if (mounted) {
        setState(() {
          _isAssigned = false;
          _wardenPhone = null;
          _assignedStaffName = 'Warden';
          _assignedStaffUsername = null;
        });
      }
    });

    if (_activeRequestId == null) {
      ApiService.getLatestRequestId(effectiveId, 'parent_warden').then((response) {
        if (response['success'] == true && response['request_id'] != null) {
          if (mounted) {
            setState(() {
              _activeRequestId = response['request_id'].toString();
            });
            WebSocketService.instance.joinRoom(_activeRequestId!);
          }
        }
      }).catchError((_) {});
    } else {
      WebSocketService.instance.joinRoom(_activeRequestId!);
    }

    _fetchMessages();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    final interval = WebSocketService.instance.isConnected ? 60 : 10;
    _timer = Timer.periodic(Duration(seconds: interval), (timer) {
      if (mounted) {
        _fetchMessages(silent: true);
      }
    });
  }

  void _onWebSocketMessage(Map<String, dynamic> event) {
    if (!mounted) return;
    final eventReqId = (event['request_id'] ?? event['data']?['request_id'])?.toString();
    if (eventReqId != null && _activeRequestId != null && eventReqId.isNotEmpty && _activeRequestId!.isNotEmpty && eventReqId != _activeRequestId) {
      return;
    }

    final user = context.read<UserProvider>();
    final rawMsg = event['data'] is Map ? Map<String, dynamic>.from(event['data']) : event;
    final msgId = (rawMsg['message_id'] ?? rawMsg['id'])?.toString();
    final senderId = rawMsg['sender_id']?.toString() ?? '';
    final messageText = rawMsg['message']?.toString() ?? '';
    final messageType = rawMsg['message_type']?.toString() ?? 'text';
    final timestamp = rawMsg['timestamp'] ?? DateTime.now().toIso8601String();

    if (msgId == null || msgId.isEmpty || messageText.isEmpty) return;

    final bool isMe = (senderId == user.username.toString() || senderId == user.dbId?.toString());

    String type = 'text';
    if (messageType == 'attendance_alert') {
      type = 'attendance_alert';
    } else if (messageType == 'admin_reply' || messageType == 'status') {
      type = 'admin_reply';
    } else if (messageType == 'request' || messageType == 'request_card') {
      type = 'request';
    }

    final newMsg = {
      'id': msgId,
      'content': messageText,
      'sender': isMe ? 'student' : 'warden',
      'timestamp': timestamp,
      'type': type,
      'status': 'sent',
      'request_data': rawMsg,
    };

    setState(() {
      final existingIndex = _messages.indexWhere((m) => m['id']?.toString() == msgId);
      if (existingIndex >= 0) {
        _messages[existingIndex] = newMsg;
      } else {
        if (isMe) {
          _messages.removeWhere((m) =>
              m['status'] == 'sending' &&
              m['content'].toString().trim() == messageText.trim());
        }
        _messages.insert(0, newMsg);
      }
    });

    if (!isMe && _activeRequestId != null && _activeRequestId!.isNotEmpty) {
      ApiService.markRead(_activeRequestId!, user.username);
    }
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
      final int? effectiveId = user.linkedStudentId;
      if (effectiveId == null) return;

      final response = await ApiService.getDepartmentChat(effectiveId, 'parent_warden', limit: _limit, offset: 0, silent: silent);
      if (response['success'] == true) {
        final List<dynamic> data = response['data'] ?? [];

        if (mounted) {
          setState(() {
            final List<Map<String, dynamic>> updatedList = [];
            for (var msg in data) {
              final serverId = msg['id']?.toString() ?? '';
              if (serverId.isEmpty) continue;

              String type = 'text';
              String messageType = msg['message_type']?.toString() ?? "";
              
              if (messageType == 'attendance_alert') {
                type = 'attendance_alert';
              } else if (messageType == 'admin_reply' || messageType == 'status') {
                type = 'admin_reply';
              } else if (messageType == 'request' || messageType == 'request_card') {
                type = 'request';
              }

              final serverMsg = {
                'id': serverId,
                'content': msg['message']?.toString() ?? '',
                'sender': (msg['sender_id']?.toString() == user.username.toString() ||
                           msg['sender_id']?.toString() == user.dbId?.toString()) 
                    ? 'student' 
                    : 'warden',
                'timestamp': msg['timestamp'],
                'type': type,
                'status': msg['status']?.toString() ?? 'sent',
                'request_data': msg,
              };
              updatedList.add(serverMsg);
            }

            // Retain actively sending messages (within last 15s)
            for (var localMsg in _messages) {
              if (localMsg['status'] == 'sending') {
                final localTime = _parseTimestamp(localMsg['timestamp']);
                if (DateTime.now().difference(localTime).inSeconds < 15) {
                  bool matchesServer = updatedList.any((s) =>
                    s['content'].toString().trim() == localMsg['content'].toString().trim()
                  );
                  if (!matchesServer) {
                    updatedList.add(localMsg);
                  }
                }
              }
            }

            updatedList.sort((a, b) {
              final t1 = _parseTimestamp(a['timestamp']);
              final t2 = _parseTimestamp(b['timestamp']);
              return t2.compareTo(t1);
            });

            _messages.clear();
            _messages.addAll(updatedList);

            bool hasIncoming = data.any((msg) =>
              msg['sender_id']?.toString() != user.username &&
              msg['sender_id']?.toString() != user.dbId?.toString() &&
              msg['status'] != 'seen'
            );
            if (hasIncoming && _activeRequestId != null && mounted) {
              ApiService.markRead(_activeRequestId!, user.username);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching parent chat: $e');
    }
  }

  Future<void> _fetchMoreMessages() async {
    if (_isMoreLoading || !_hasMore) return;
    setState(() => _isMoreLoading = true);
    await Future.delayed(const Duration(seconds: 1));

    try {
      final user = context.read<UserProvider>();
      final int? effectiveId = user.linkedStudentId;
      if (effectiveId == null) return;

      final nextOffset = _offset + _limit;
      final response = await ApiService.getDepartmentChat(effectiveId, 'parent_warden', limit: _limit, offset: nextOffset);
      
      if (response['success'] == true) {
        final List<dynamic> data = response['data'] ?? [];
        if (data.length < _limit) _hasMore = false;

        if (data.isNotEmpty) {
          final List<Map<String, dynamic>> olderMessages = [];
          for (var msg in data) {
            String type = 'text';
            String messageType = msg['message_type']?.toString() ?? "";
            
            if (messageType == 'attendance_alert') {
              type = 'attendance_alert';
            } else if (messageType == 'admin_reply' || messageType == 'status') {
              type = 'admin_reply';
            } else if (messageType == 'request' || messageType == 'request_card' || msg['id'] == null) {
              type = 'request';
            }

            olderMessages.add({
              'id': msg['id'],
              'type': type,
              'sender': (msg['sender_id']?.toString() == user.dbId?.toString() || 
                       msg['sender_id']?.toString() == user.username.toString() ||
                       msg['sender_id']?.toString() == user.linkedStudentId?.toString()) ? 'student' : 'warden',
              'content': msg['message'] ?? 'New Update',
              'request_data': msg,
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
      debugPrint('Error loading more parent messages: $e');
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
    if (_activeRequestId != null && _activeRequestId!.isNotEmpty) {
      WebSocketService.instance.leaveRoom(_activeRequestId!);
    }
    _wsSubscription?.cancel();
    if (_wsConnListener != null) {
      WebSocketService.instance.isConnectedNotifier.removeListener(_wsConnListener!);
    }
    NotificationService.fcmRefreshNotifier.removeListener(_fetchMessages);
    _timer?.cancel();
    _messageController.removeListener(_onMessageChanged);
    _messageController.dispose();
    _scrollController.dispose(); 
    super.dispose();
  }

  void _onMessageChanged() {
    final isTyping = _messageController.text.trim().isNotEmpty;
    if (isTyping != _isTyping) setState(() => _isTyping = isTyping);
  }

  Future<void> _handleSendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    final user = context.read<UserProvider>();
    _messageController.clear();
    setState(() => _isTyping = false);

    setState(() {
      _messages.insert(0, {
        'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
        'type': 'text',
        'sender': 'student',
        'content': messageText,
        'timestamp': DateTime.now().toIso8601String(),
      });
    });

    if (_activeRequestId == null) {
      final response = await ApiService.createServiceRequest(
        studentId: user.linkedStudentId!, 
        department: 'parent_warden',
        requestType: 'General Inquiry',
        purpose: 'New parent chat started: $messageText',
        roomNumber: user.linkedStudentRoom,
        skipMessage: true,
      );

      if (response['success'] == true) {
        _activeRequestId = response['request_id'].toString();
        await ApiService.sendChatMessage(_activeRequestId!, user.username, messageText);
        _fetchMessages();
      }
    } else {
      final response = await ApiService.sendChatMessage(_activeRequestId!, user.username, messageText);
      if (response['success'] == true) {
        _fetchMessages();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LinenGridBackground(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.transparent,
        appBar: SkeuomorphicNavBar(
          title: _assignedStaffName,
          onBack: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              context.read<UIProvider>().setActiveChatChannel(null);
            }
          },
          rightAction: IconButton(
            icon: const Icon(Icons.phone_outlined, color: Colors.white),
            onPressed: () async {
              if (_wardenPhone == null || _wardenPhone!.trim().isEmpty || _wardenPhone!.toLowerCase() == 'n/a') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Warden phone number not available'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              try {
                final Uri telUri = Uri.parse('tel:${_wardenPhone!.replaceAll(' ', '')}');
                await launchUrl(telUri, mode: LaunchMode.externalApplication);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not trigger phone call'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
        ),
        body: Column(
          children: [
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
                        'Warden has not been assigned to your child yet. Please contact the administrator.',
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
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                itemCount: _messages.length + (_isMoreLoading ? 1 : 0) + (!_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length && _isMoreLoading) {
                    return const Center(child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator()));
                  }
                  if (index == _messages.length + (_isMoreLoading ? 1 : 0) && !_hasMore) {
                    return Center(child: Padding(padding: EdgeInsets.all(10), child: Text("All messages loaded", style: TextStyle(color: Colors.grey, fontSize: 11))));
                  }
  
                  if (index >= _messages.length) return const SizedBox.shrink();
  
                  final msg = _messages[index];
                  String? nextDate;
                  if (index + 1 < _messages.length) {
                    nextDate = _formatTimestampForDate(_messages[index + 1]['timestamp']);
                  }
                  final currDate = _formatTimestampForDate(msg['timestamp']);
  
                  List<Widget> children = [];
                  if (nextDate == null || nextDate != currDate) {
                    children.add(_buildDateSeparator(currDate));
                  }
  
                  if (msg['type'] == 'text') {
                    children.add(_buildTextMessage(msg));
                  } else if (msg['type'] == 'attendance_alert') {
                    children.add(_buildAttendanceAlertCard(msg));
                  } else if (msg['type'] == 'admin_reply') {
                    children.add(_buildAdminActionCard(msg));
                  } else {
                    children.add(_buildRequestCard(msg));
                  }
                  
                  return Column(children: children);
                },
              ),
            ),
            _buildInputSection(),
          ],
        ),
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

  Widget getStatusIcon(String status) {
    if (status == 'sending') return const Icon(Icons.access_time, size: 14, color: Colors.black45);
    if (status == 'sent') return const Icon(Icons.check, size: 14, color: Colors.black45);
    if (status == 'delivered') return const Icon(Icons.done_all, size: 14, color: Colors.black45);
    if (status == 'seen') return const Icon(Icons.done_all, size: 14, color: Colors.blue);
    return const SizedBox();
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

  Widget _buildAttendanceAlertCard(Map<String, dynamic> msg) {
    Map<String, dynamic> data = {};
    try {
      data = jsonDecode(msg['content']);
    } catch (e) {
      data = {
        'title': 'Attendance Alert ⚠️',
        'student_name': 'Student',
        'status': 'ABSENT',
        'date': '',
        'message': msg['content']
      };
    }

    final title = data['title'] ?? 'Attendance Alert ⚠️';
    final studentName = data['student_name'] ?? 'Student';
    final status = data['status'] ?? 'ABSENT';
    final date = data['date'] ?? '';
    final messageText = data['message'] ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Align(
        alignment: Alignment.centerLeft, // Warden sent this to Parent
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF5F5), // Soft warning red background
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFFC1C1), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.08),
                blurRadius: 8,
                spreadRadius: 1,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEE2E2), // Slightly darker warning background
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(15),
                    topRight: Radius.circular(15),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444), // Crimson red exclamation circle
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.priority_high_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF991B1B), // Dark red title text
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    if (date.isNotEmpty)
                      Text(
                        date,
                        style: const TextStyle(
                          color: Color(0xFFB91C1C),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
              
              // Body Details
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      studentName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text(
                          "Status: ",
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            status,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      messageText,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF4B5563),
                        height: 1.4,
                      ),
                    ),
                    const Divider(height: 24, color: Color(0xFFFFD2D2)),
                    const Row(
                      children: [
                        Icon(Icons.reply_rounded, color: Color(0xFFEF4444), size: 16),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Type your reply below to explain the absence.",
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF991B1B),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextMessage(Map<String, dynamic> msg) {
    bool isMe = msg['sender'] == 'student';
    final status = msg['status']?.toString() ?? 'sent';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          decoration: BoxDecoration(
            color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(12),
              topRight: const Radius.circular(12),
              bottomLeft: Radius.circular(isMe ? 12 : 2),
              bottomRight: Radius.circular(isMe ? 2 : 12),
            ),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
          ),
          child: IntrinsicWidth(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    msg['content'], 
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatTimestampForTime(msg['timestamp']), 
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
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

  Widget _buildRequestCard(Map<String, dynamic> msg) {
    final request = RequestModel.fromJson(msg['request_data']);
    return RequestCard(
      request: request, 
      isMe: msg['sender'] == 'student',
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RequestDetailsScreen(
              request: request,
              canAction: false,
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputSection() {
    if (!_isAssigned) {
      return Container(
        padding: const EdgeInsets.fromLTRB(15, 12, 15, 30),
        decoration: const BoxDecoration(
          color: Color(0xFFF9F9F9),
          border: Border(top: BorderSide(color: Colors.black12)),
        ),
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

    return SafeArea(
      top: false,
      bottom: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(15, 8, 15, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: Colors.black12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    filled: false,
                    hintText: 'Type a message',
                    hintStyle: TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                  onSubmitted: (_) => _isTyping ? _handleSendMessage() : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(onPressed: _isTyping ? _handleSendMessage : null, icon: const Icon(Icons.send, color: Color(0xFF3B5998))),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = ['All'];
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: const Color(0xFFF0EDE5),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 15, right: 15),
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (filters[index] == 'All') Icon(Icons.chat_bubble_outline, size: 14, color: isSelected ? Colors.white : Colors.grey),
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
}
