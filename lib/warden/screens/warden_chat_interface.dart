import 'package:flutter/material.dart';
import 'package:vianasoft_stay/core/styles.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/category_provider.dart';
import 'package:flutter/services.dart';
import '../../core/api_service.dart';
import '../../core/notification_service.dart';
import '../../core/models/request_model.dart';
import '../../shared/chat/request_card.dart';
import '../../shared/chat/request_details_screen.dart';
import '../../shared/ui_provider.dart';
import '../../shared/chat/call_log_card.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../widgets/warden_modals.dart';

class WardenChatInterface extends StatefulWidget {
  final String channel;
  final String? initialRequestId;
  const WardenChatInterface({super.key, required this.channel, this.initialRequestId});

  @override
  State<WardenChatInterface> createState() => _WardenChatInterfaceState();
}

class _WardenChatInterfaceState extends State<WardenChatInterface> {
  Map<String, dynamic>? _activeConversation;
  String? _activeRequestId;
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _activeMessages = [];
  bool _isLoading = true;
  Timer? _timer;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _currentFilter = 'All';
  bool _isTyping = false;
  bool _isSending = false; 
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _messageController.addListener(() {
      final isTypingNow = _messageController.text.trim().isNotEmpty;
      if (isTypingNow != _isTyping) {
        setState(() => _isTyping = isTypingNow);
      }
    });
    _fetchConversations();
    _startTimer();
    NotificationService.fcmRefreshNotifier.addListener(_onFCMRefresh);

    // Instantly zero the badge for this channel — don't wait for next API poll
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<CategoryProvider>().setUnreadCount(widget.channel, 0);
      }
    });
  }

  void _onFCMRefresh() {
    if (mounted) {
      if (_activeConversation == null) {
        _fetchConversations();
      } else {
        _fetchMessages();
      }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        if (_activeConversation == null) {
          _fetchConversations(silent: true);
        } else {
          _fetchMessages(silent: true);
        }
      }
    });
  }

  @override
  void dispose() {
    NotificationService.fcmRefreshNotifier.removeListener(_onFCMRefresh);
    _timer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchConversations({bool silent = false}) async {
    try {
      final user = context.read<UserProvider>();
      final response = await ApiService.getConversationList(
        widget.channel, 
        wardenUsername: user.username,
        silent: silent,
      );
      if (response['success'] == true && response['data'] is List) {
        if (mounted) {
          setState(() {
            final List<Map<String, dynamic>> rawList = List<Map<String, dynamic>>.from(response['data']);
            rawList.sort((a, b) {
              final int unreadA = int.tryParse(a['unread_count']?.toString() ?? "0") ?? 0;
              final int unreadB = int.tryParse(b['unread_count']?.toString() ?? "0") ?? 0;
              if (unreadA > 0 && unreadB == 0) return -1;
              if (unreadB > 0 && unreadA == 0) return 1;
              if (unreadA != unreadB) return unreadB.compareTo(unreadA);
              final t1 = _parseTimestamp(a['last_time']);
              final t2 = _parseTimestamp(b['last_time']);
              return t2.compareTo(t1);
            });
            _conversations = rawList;
            _isLoading = false;

            // AUTOMATICALLY SELECT INITIAL REQUEST IF PROVIDED
            if (widget.initialRequestId != null && _activeConversation == null) {
              final matched = _conversations.firstWhere(
                (c) => c['request_id']?.toString() == widget.initialRequestId,
                orElse: () => <String, dynamic>{},
              );
              if (matched.isNotEmpty) {
                _activeConversation = matched;
                _activeMessages = [];
                _isLoading = true;
                _fetchMessages();
              }
            }
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMessages({bool silent = false}) async {
    if (_activeConversation == null) return;
    int? studentId = int.tryParse(_activeConversation!['student_id']?.toString() ?? "");
    if (studentId == null) return;

    try {
      final response = await ApiService.getDepartmentChat(studentId, widget.channel, silent: silent);
      if (response['success'] == true && response['data'] is List) {
        final List<Map<String, dynamic>> newMsgList = (response['data'] as List).map((msg) {
          if (msg is! Map<String, dynamic>) return <String, dynamic>{};
          String type = 'text';
          String messageType = msg['message_type']?.toString() ?? "";
          if (msg['id'] == null || messageType == 'request' || messageType == 'request_card') {
            type = 'request';
          } else if (messageType == 'status' || messageType == 'admin_reply') {
            type = 'admin_reply';
          } else if (messageType == 'call') {
            type = 'call';
          }
          return {
            ...msg,
            'type': type,
            'request_id': msg['request_id']?.toString() ?? msg['req_id']?.toString() ?? "",
            'message': msg['message'] ?? "",
          };
        }).where((m) => m.isNotEmpty).toList();

        if (mounted) {
          setState(() {
            final List<Map<String, dynamic>> updatedList = [];
            for (var msg in newMsgList) {
              updatedList.add(msg);
            }
            updatedList.sort((a, b) {
              final t1 = _parseTimestamp(a['timestamp']);
              final t2 = _parseTimestamp(b['timestamp']);
              return t2.compareTo(t1);
            });
            _activeMessages.clear();
            _activeMessages.addAll(updatedList);
            _isLoading = false;
          });
          
          final user = context.read<UserProvider>();
          final myUsername = user.username.toString();
          final myDbId = user.dbId?.toString() ?? "";

          // Resolve active request ID if not yet assigned
          if (_activeRequestId == null || _activeRequestId!.isEmpty) {
            for (var m in newMsgList) {
              final rid = m['request_id']?.toString() ?? m['req_id']?.toString();
              if (rid != null && rid.isNotEmpty) {
                _activeRequestId = rid;
                break;
              }
            }
          }
          if (_activeRequestId == null || _activeRequestId!.isEmpty) {
            _activeRequestId = _activeConversation?['request_id']?.toString();
          }

          bool hasIncoming = newMsgList.any((msg) =>
            msg['status'] != 'seen' &&
            !( (msg['sender_username']?.toString() == myUsername && myUsername.isNotEmpty) || 
               (msg['sender_id']?.toString() == myDbId && myDbId.isNotEmpty) )
          );
          if (hasIncoming && _activeRequestId != null && _activeRequestId!.isNotEmpty && mounted) {
            ApiService.markRead(_activeRequestId!, user.username).then((_) {
              if (mounted) context.read<CategoryProvider>().fetchCounts(wardenUsername: user.username, force: true);
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching messages: $e");
    }
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty || 
        _activeRequestId == null || 
        _isSending) {
      return;
    }

    final user = context.read<UserProvider>();
    String msg = _messageController.text.trim();

    setState(() {
      _isSending = true;
      _isTyping = false;
    });

    setState(() {
      _activeMessages.insert(0, {
        'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
        'isTemp': true, 
        'message': msg,
        'sender_id': user.dbId.toString(),
        'sender_username': user.username, 
        'timestamp': DateTime.now().toIso8601String(),
        'type': 'text',
      });
    });

    _messageController.clear();

    ApiService.sendChatReply(
      requestId: _activeRequestId!,
      senderId: user.dbId!,
      message: msg,
    ).then((response) {
      if (response['success'] == true && response['message_id'] != null) {
        setState(() {
          int index = _activeMessages.indexWhere((m) => 
            m['isTemp'] == true &&
            m['message'].toString().trim() == msg.trim()
          );
          if (index != -1) {
            _activeMessages[index]['id'] = response['message_id'].toString();
            _activeMessages[index]['status'] = 'sent';
            _activeMessages[index]['isTemp'] = false; 
          }
        });
      }
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _fetchMessages();
      });
    }).catchError((e) {
      debugPrint("Send failed: $e");
    });

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
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

  List<Map<String, dynamic>> get _filteredMessages {
    if (_currentFilter == 'All') return _activeMessages.where((m) => m['type'] != 'call').toList();
    if (_currentFilter == 'Calls') return _activeMessages.where((m) => m['type'] == 'call').toList();
    return _activeMessages.where((m) => 
      m['type'] == 'request' &&
      m['request_type'] != null && 
      m['request_type'].toString().toLowerCase() == _currentFilter.toLowerCase()
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    return PopScope(
      canPop: _activeConversation == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_activeConversation != null) {
          setState(() => _activeConversation = null);
        }
      },
      child: LinenGridBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: _activeConversation == null 
            ? SkeuomorphicNavBar(
                title: widget.channel == "parent_warden" 
                  ? "Parent Logs" 
                  : "${widget.channel[0].toUpperCase()}${widget.channel.substring(1).toLowerCase()} Logs",
                onBack: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    context.read<UIProvider>().setActiveChatChannel(null);
                  }
                },
                rightAction: IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                  onPressed: _fetchConversations,
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              )
            : SkeuomorphicNavBar(
                title: _activeConversation!['name']?.toString() ?? "Chat",
                onBack: () => setState(() => _activeConversation = null),
                onTitleLongPress: () {
                  if (_activeConversation != null) {
                    final studentIdStr = _activeConversation!['student_id']?.toString() ?? "";
                    final studentId = int.tryParse(studentIdStr);
                    final String name = _activeConversation!['name']?.toString() ?? "Student";
                    final String regNo = (_activeConversation!['student_username'] ?? 'N/A').toString();
                    final String room = (_activeConversation!['room_allocation'] ?? 'N/A').toString();

                    showDialog(
                      context: context,
                      builder: (context) => StudentDetailsDialog(
                        studentId: studentId,
                        fallbackName: name,
                        fallbackRegNo: regNo,
                        fallbackRoom: room,
                      ),
                    );
                  }
                },
                rightAction: _activeConversation == null
                    ? const SizedBox.shrink()
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.phone_outlined, color: Colors.white, size: 22),
                            onPressed: _launchStudentDialer,
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
              ),
          body: _activeConversation == null 
              ? _buildConversationListBody(isDark) 
              : _buildIndividualChatBody(isDark),
        ),
      ),
    );
  }

  void _launchStudentDialer() {
    if (_activeConversation != null) {
      final studentIdStr = _activeConversation!['student_id']?.toString() ?? "";
      final studentId = int.tryParse(studentIdStr);
      if (studentId != null) {
        try {
          ApiService.getUserData(studentId).then((response) async {
            if (response['success'] == true && response['data'] != null) {
              final phone = response['data']['phone']?.toString();
              if (phone != null && phone.isNotEmpty) {
                final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '');
                Clipboard.setData(ClipboardData(text: cleanPhone));
                final Uri telUri = Uri.parse('tel:$cleanPhone');
                await launchUrl(telUri, mode: LaunchMode.externalApplication);
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Phone number not found for this student.')),
                  );
                }
              }
            } else {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to fetch student details.')),
                );
              }
            }
          });
        } catch (e) {
          debugPrint("Error launching dialer: $e");
        }
      }
    }
  }

  Widget _buildConversationListBody(bool isDark) {
    final filteredConversations = _conversations.where((conv) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      final name = (conv['name'] ?? '').toString().toLowerCase();
      final username = (conv['student_username'] ?? '').toString().toLowerCase();
      final room = (conv['room_allocation'] ?? '').toString().toLowerCase();
      return name.contains(query) || username.contains(query) || room.contains(query);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1B2B48), fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search student by name, reg no, room...',
              hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade400, fontSize: 13),
              prefixIcon: Icon(Icons.search, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48), size: 20),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: Color(0xFFD4AF37)),
              ),
            ),
          ),
        ),
        Expanded(
          child: _isLoading 
            ? Center(child: CircularProgressIndicator(color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48)))
            : filteredConversations.isEmpty
              ? Center(child: Text("No conversations found", style: TextStyle(color: isDark ? Colors.white60 : Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  itemCount: filteredConversations.length,
                  itemBuilder: (context, index) => _buildConversationCard(filteredConversations[index], isDark),
                ),
        ),
      ],
    );
  }

  Widget _buildConversationCard(Map<String, dynamic> conv, bool isDark) {
    final String name = conv['name']?.toString() ?? "Student";
    final String timeStr = _formatTimestampForTime(conv['last_time']);
    final int unread = int.tryParse(conv['unread_count']?.toString() ?? "0") ?? 0;
    
    String initials = "";
    if (name.isNotEmpty) {
      final parts = name.split(' ');
      initials = parts[0][0].toUpperCase();
      if (parts.length > 1) initials += parts[1][0].toUpperCase();
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Card(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
        margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
        elevation: isDark ? 0 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(color: isDark ? Colors.white.withOpacity(0.14) : Colors.transparent),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          onTap: () {
            setState(() {
              conv['unread_count'] = 0;
              _activeConversation = conv;
              _activeRequestId = conv['request_id']?.toString();
              _activeMessages = [];
              _isLoading = true;
            });
            final user = context.read<UserProvider>();
            context.read<CategoryProvider>().setUnreadCount(widget.channel, 0);
            final requestId = conv['request_id']?.toString() ?? "";
            if (user.username.isNotEmpty && requestId.isNotEmpty) {
              ApiService.markRead(requestId, user.username).then((_) {
                if (mounted) context.read<CategoryProvider>().fetchCounts(wardenUsername: user.username, force: true);
              });
            }
            _fetchMessages();
          },
          onLongPress: () {
            final studentIdStr = conv['student_id']?.toString() ?? "";
            final studentId = int.tryParse(studentIdStr);
            final String name = conv['name']?.toString() ?? "Student";
            final String regNo = (conv['student_username'] ?? 'N/A').toString();
            final String room = (conv['room_allocation'] ?? 'N/A').toString();

            showDialog(
              context: context,
              builder: (context) => StudentDetailsDialog(
                studentId: studentId,
                fallbackName: name,
                fallbackRegNo: regNo,
                fallbackRoom: room,
              ),
            );
          },
          leading: Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle, 
              gradient: widget.channel == 'parent_warden' 
                  ? SkeuomorphicColors.softBrownGradient 
                  : const LinearGradient(colors: [Color(0xFF4A69BB), Color(0xFF1E2F5E)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Center(
              child: widget.channel == 'parent_warden'
                  ? const Icon(Icons.family_restroom, color: Colors.white, size: 24)
                  : Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  name, 
                  style: TextStyle(
                    fontFamily: 'Lato', 
                    fontSize: 16, 
                    fontWeight: FontWeight.bold, 
                    color: isDark ? Colors.white : const Color(0xFF1B2B48),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 10),
              Text(timeStr, style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey), textAlign: TextAlign.right),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                () {
                  final msg = conv['last_msg']?.toString() ?? '';
                  if (msg.isEmpty || msg == 'New Request') return 'No messages yet';
                  return msg;
                }(),
                style: TextStyle(
                  fontSize: 12,
                  color: (conv['last_msg']?.toString() ?? '').isEmpty || conv['last_msg']?.toString() == 'New Request'
                      ? (isDark ? Colors.white38 : Colors.grey.shade400)
                      : (isDark ? Colors.white70 : const Color(0xFF5D6D7E)),
                  fontStyle: (conv['last_msg']?.toString() ?? '').isEmpty || conv['last_msg']?.toString() == 'New Request'
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.meeting_room_outlined, size: 10, color: isDark ? const Color(0xFFD4AF37) : Colors.blueGrey),
                  const SizedBox(width: 3),
                  Text(
                    () {
                      final room = conv['room_allocation']?.toString() ?? '';
                      if (room.isEmpty || room == 'null' || room == 'unallocated') return 'Room not assigned';
                      return room;
                    }(),
                    style: TextStyle(fontSize: 10, color: isDark ? Colors.white60 : Colors.blueGrey, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unread > 0)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(6), 
                  decoration: const BoxDecoration(color: Color(0xFFC62828), shape: BoxShape.circle), 
                  child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))
                ),
              Icon(Icons.chevron_right, color: isDark ? Colors.white60 : Colors.grey, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIndividualChatBody(bool isDark) {
    return Column(
      children: [
        _buildRoomBanner(isDark),
        _buildFilterChips(isDark),
        Expanded(child: _buildMessagesArea(isDark)),
        _buildChatInputArea(isDark),
      ],
    );
  }

  Widget _buildFilterChips(bool isDark) {
    final catProvider = context.read<CategoryProvider>();
    final String deptName = widget.channel == 'parent_warden' ? 'Warden' : (widget.channel.toLowerCase() == 'warden' ? 'Warden' : widget.channel);
    
    final filters = ['All'];
    final categoryData = catProvider.getCategoryByName(deptName);
    if (categoryData != null && categoryData['codes'] != null) {
      final codes = (categoryData['codes'] as List).map((code) => code.toString()).where((c) => c != 'Calls').toList();
      filters.addAll(codes);
    }

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF0EDE5),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = _currentFilter == filter;
          
          IconData icon;
          if (filter == 'All') {
            icon = Icons.chat_bubble_outline;
          } else if (filter == 'Calls') icon = Icons.phone_outlined;
          else if (filter.toLowerCase().contains('emergency')) icon = Icons.warning_amber_outlined;
          else icon = Icons.assignment_outlined;

          return GestureDetector(
            onTap: () => setState(() => _currentFilter = filter),
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected 
                    ? (isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48)) 
                    : (isDark ? const Color(0xFF0F1520) : Colors.white),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? Colors.transparent : (isDark ? Colors.white24 : Colors.black.withOpacity(0.1)),
                ),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
              ),
              child: Row(
                children: [
                  Icon(
                    icon, 
                    size: 14, 
                    color: isSelected 
                        ? (isDark ? const Color(0xFF1B2B48) : Colors.white) 
                        : (isDark ? Colors.white60 : Colors.grey),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    filter, 
                    style: TextStyle(
                      fontSize: 12, 
                      fontWeight: FontWeight.bold, 
                      color: isSelected 
                          ? (isDark ? const Color(0xFF1B2B48) : Colors.white) 
                          : (isDark ? Colors.white70 : const Color(0xFF5D5D5D)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRoomBanner([bool isDark = false]) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05))),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  (_activeConversation!['room_allocation']?.toString() ?? "Room N/A").toUpperCase(),
                  style: SkeuomorphicStyles.latoBody.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 1.0,
                    color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF8C7A5E),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesArea([bool isDark = false]) {
    final filtered = _filteredMessages;
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final msg = filtered[index];
        String? nextDate;
        if (index + 1 < filtered.length) {
          nextDate = _formatTimestampForDate(filtered[index + 1]['timestamp']);
        }
        final currDate = _formatTimestampForDate(msg['timestamp']);
        List<Widget> children = [];
        if (nextDate == null || nextDate != currDate) {
          children.add(_buildDateSeparator(currDate, isDark));
        }
        children.add(_buildMessageBubble(msg, isDark));
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: children,
        );
      },
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, [bool isDark = false]) {
    final user = context.read<UserProvider>();
    final myUsername = user.username.toString();
    final myDbId = user.dbId?.toString() ?? "";
    final senderId = msg['sender_id']?.toString() ?? "";
    final senderUsername = msg['sender_username']?.toString() ?? "";
    bool isMe = (senderUsername == myUsername && myUsername.isNotEmpty) || 
               (senderId == myDbId && myDbId.isNotEmpty);
    if (msg['type'] == 'request') return _buildRequestMessage(msg, isMe);
    if (msg['type'] == 'call') return _buildCallMessage(msg, isMe);
    if (msg['type'] == 'admin_reply') {
      return Center(
         child: Container(
           margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
           padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
           decoration: BoxDecoration(
             color: isDark ? Colors.white12 : Colors.black.withOpacity(0.08), 
             borderRadius: BorderRadius.circular(20)
           ),
           child: Text(
             msg['message']?.toString() ?? "", 
             textAlign: TextAlign.center,
             style: TextStyle(
               fontSize: 11, 
               color: isDark ? Colors.white70 : Colors.black.withOpacity(0.5), 
               fontWeight: FontWeight.w500
             )
           ),
         ),
      );
    }
    final String timeStr = _formatTimestampForTime(msg['timestamp']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          decoration: BoxDecoration(
            color: isMe 
                ? (isDark ? const Color(0xFF1E3A2F) : const Color(0xFFDCF8C6)) 
                : (isDark ? const Color(0xFF1E293B) : Colors.white),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(10),
              topRight: const Radius.circular(10),
              bottomLeft: Radius.circular(isMe ? 10 : 2),
              bottomRight: Radius.circular(isMe ? 2 : 10),
            ),
            border: isDark ? Border.all(color: Colors.white12) : null,
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
          ),
          child: IntrinsicWidth(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    msg['message']?.toString() ?? "", 
                    style: TextStyle(
                      fontSize: 14, 
                      height: 1.2, 
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(timeStr, style: TextStyle(color: isDark ? Colors.white60 : Colors.grey, fontSize: 10)),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      _getStatusIcon(msg['status']?.toString() ?? 'sent'),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRequestMessage(Map<String, dynamic> msg, bool isMe) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: RequestCard(
        request: RequestModel.fromJson(msg),
        isMe: isMe,
        onTap: () async {
          final result = await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            barrierColor: Colors.transparent, 
            useRootNavigator: false, 
            builder: (context) => FractionallySizedBox(
              heightFactor: 0.85,
              child: RequestDetailsScreen(
                request: RequestModel.fromJson(msg),
                canAction: true,
              ),
            ),
          );
          if (result == true && mounted) {
            _fetchMessages();
          }
        },
      ),
    );
  }

  Widget _buildCallMessage(Map<String, dynamic> msg, bool isMe) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: CallLogCard(
        title: msg['title'] ?? 'Voice Call',
        subtitle: msg['subtitle'] ?? (isMe ? 'Outgoing Call' : 'Incoming Call'),
        duration: msg['duration'] ?? '00:00',
        status: msg['status'] ?? 'Completed',
      ),
    );
  }

  Widget _buildChatInputArea([bool isDark = false]) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 30),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white, 
        border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F1520) : Colors.white, 
                borderRadius: BorderRadius.circular(25), 
                border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
              ),
              child: TextField(
                controller: _messageController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  filled: false,
                  hintText: 'Type a message',
                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 14),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: (!_isSending) ? _sendMessage : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_isTyping && !_isSending) ? Colors.blue : (isDark ? Colors.white12 : Colors.grey.shade200),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.send,
                  color: (_isTyping && !_isSending) ? Colors.white : (isDark ? Colors.white38 : Colors.grey),
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSeparator(String text, [bool isDark = false]) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 20),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05), 
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text.toUpperCase(), 
          style: TextStyle(
            fontSize: 10, 
            fontWeight: FontWeight.bold, 
            color: isDark ? Colors.white70 : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _getStatusIcon(String status) {
    if (status == 'sending') return const Icon(Icons.access_time, size: 12, color: Colors.grey);
    if (status == 'sent') return const Icon(Icons.check, size: 12, color: Colors.grey);
    if (status == 'delivered') return const Icon(Icons.done_all, size: 12, color: Colors.grey);
    if (status == 'seen') return const Icon(Icons.done_all, size: 12, color: Colors.blue);
    return const SizedBox.shrink();
  }
}
