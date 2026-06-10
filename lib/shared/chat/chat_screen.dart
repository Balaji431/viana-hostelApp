import 'package:flutter/material.dart';
import '../../core/api_service.dart';
import '../../core/styles.dart';
import '../../core/app_logger.dart';
import '../widgets/skeuomorphic_navbar.dart';

class ChatScreen extends StatefulWidget {
  final String title;
  final String roomNumber;
  final String requestId;
  final String currentUserId;

  const ChatScreen({
    super.key, 
    required this.title, 
    required this.roomNumber,
    this.requestId = 'REQ_default', 
    this.currentUserId = 'unknown', 
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    AppLogger.info("Chat init: ${widget.title}, Request: ${widget.requestId}, User: ${widget.currentUserId}");
    _messages.add({
      'sender': 'System',
      'msg': 'Welcome to ${widget.title} support chat.\nRequest ID: ${widget.requestId}\nUser: ${widget.currentUserId}',
      'isMe': false,
      'timestamp': DateTime.now(),
    });
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    try {
      setState(() => _isLoading = true);
      AppLogger.info("Loading messages: Request ${widget.requestId}, User ${widget.currentUserId}");
      final response = await ApiService.getChatMessages(widget.requestId);
      if (response['success'] == true && response['data'] != null) {
        setState(() {
          _messages.clear();
          for (var msg in response['data']) {
            final isMe = (msg['sender_username'] == widget.currentUserId) || 
                        (msg['sender_id'] == widget.currentUserId);
            _messages.add({
              'sender': msg['sender_name'] ?? 'Unknown',
              'msg': msg['message'] ?? '',
              'isMe': isMe,
              'timestamp': DateTime.parse(msg['created_at']),
            });
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      AppLogger.error("Error loading messages: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    if (_msgController.text.trim().isEmpty) return;
    final message = _msgController.text.trim();
    _msgController.clear();
    final requestId = widget.requestId.isNotEmpty ? widget.requestId : 'REQ_default';
    final currentUserId = widget.currentUserId.isNotEmpty ? widget.currentUserId : 'test_user';
    setState(() {
      _messages.add({
        'sender': 'Me',
        'msg': message,
        'isMe': true,
        'timestamp': DateTime.now(),
      });
    });
    _scrollToBottom();
    try {
      final response = await ApiService.sendChatMessage(requestId, currentUserId, message);
      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Message sent!"), backgroundColor: Colors.green, duration: Duration(seconds: 2)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Failed to send: ${response['message']}"), backgroundColor: Colors.red));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Network error: $e"), backgroundColor: Colors.red));
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5E5E5),
      appBar: SkeuomorphicNavBar(
        title: widget.title,
        onBack: () => Navigator.pop(context),
        rightAction: IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
          onPressed: _loadMessages,
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        ),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                color: Colors.black.withOpacity(0.05),
                child: Text('Room: ${widget.roomNumber}', style: const TextStyle(fontSize: 10, color: Colors.black54), textAlign: TextAlign.center),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (ctx, index) {
                          final message = _messages[index];
                          final isMe = message['isMe'] ?? false;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                              children: [
                                if (!isMe) ...[
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: Colors.grey[400],
                                    child: Text(
                                      message['sender']?.toString().substring(0, 1).toUpperCase() ?? 'S',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isMe ? SkeuomorphicColors.luxuryGreen : Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2)),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (!isMe)
                                          Text(
                                            message['sender']?.toString() ?? 'Unknown',
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isMe ? Colors.white : Colors.grey[600]),
                                          ),
                                        Text(
                                          message['msg']?.toString() ?? '',
                                          style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 14),
                                        ),
                                        Text(
                                          _formatTime(message['timestamp']),
                                          style: TextStyle(fontSize: 10, color: isMe ? Colors.white70 : Colors.grey[500]),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (isMe) ...[
                                  const SizedBox(width: 8),
                                  const CircleAvatar(
                                    radius: 16,
                                    backgroundColor: SkeuomorphicColors.luxuryGreen,
                                    child: Icon(Icons.person, size: 16, color: Colors.white),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, -2))],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _msgController,
                        decoration: InputDecoration(
                          hintText: 'Type your message...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          filled: true,
                          fillColor: const Color(0xFFF5F0E8),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _sendMessage,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(color: SkeuomorphicColors.luxuryGreen, shape: BoxShape.circle),
                        child: const Icon(Icons.send, color: Colors.white, size: 20),
                      ),
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

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final time = timestamp is String ? DateTime.parse(timestamp) : timestamp as DateTime;
      return "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return '';
    }
  }
}
