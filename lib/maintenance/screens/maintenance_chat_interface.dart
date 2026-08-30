import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../warden/widgets/warden_widgets.dart' show LinenBackground;

class MaintenanceChatInterface extends StatefulWidget {
  final String channel;
  
  const MaintenanceChatInterface({
    super.key,
    required this.channel,
  });

  @override
  State<MaintenanceChatInterface> createState() => _MaintenanceChatInterfaceState();
}

class _MaintenanceChatInterfaceState extends State<MaintenanceChatInterface> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [
    {
      'sender': 'Warden',
      'message': 'Hi maintenance team, we have a plumbing issue in Block A.',
      'time': '09:30 AM',
      'isMe': false,
    },
    {
      'sender': 'Maintenance Staff',
      'message': 'Noted. We will check it right away.',
      'time': '09:35 AM',
      'isMe': true,
    },
    {
      'sender': 'Warden',
      'message': 'Thank you. Please update once resolved.',
      'time': '09:40 AM',
      'isMe': false,
    },
  ];

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;
    
    setState(() {
      _messages.add({
        'sender': 'Maintenance Staff',
        'message': _messageController.text,
        'time': '10:00 AM',
        'isMe': true,
      });
      _messageController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: '${widget.channel} Chat',
        onBack: () => Navigator.pop(context),
        rightAction: const ProfileButton(),
      ),
      body: LinenBackground(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return _buildMessageBubble(message, isDark);
                },
              ),
            ),
            _buildMessageInput(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isDark) {
    final isMe = message['isMe'] as bool;
    
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isMe 
              ? const Color(0xFF1A2744) 
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: isDark ? Border.all(color: Colors.white12) : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.35 : 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message['sender'],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isMe ? const Color(0xFFD4AF37) : (isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message['message'],
              style: TextStyle(
                fontSize: 14,
                color: isMe ? Colors.white : (isDark ? Colors.white : Colors.black87),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message['time'],
              style: TextStyle(
                fontSize: 10,
                color: isMe ? Colors.white70 : (isDark ? Colors.white60 : Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                filled: true,
                fillColor: isDark ? const Color(0xFF0F1520) : const Color(0xFFF5F0E8),
                hintText: 'Type a message...',
                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: isDark ? const BorderSide(color: Colors.white24) : BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1A2744),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
