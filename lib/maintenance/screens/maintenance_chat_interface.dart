import 'package:flutter/material.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';

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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F0E8),
      appBar: SkeuomorphicNavBar(
        title: '${widget.channel} Chat',
        onBack: () => Navigator.pop(context),
        rightAction: const ProfileButton(),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildMessageBubble(message);
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final isMe = message['isMe'] as bool;
    
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF1A2744) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
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
                color: isMe ? const Color(0xFFD4AF37) : const Color(0xFF1A2744),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message['message'],
              style: TextStyle(
                fontSize: 14,
                color: isMe ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message['time'],
              style: TextStyle(
                fontSize: 10,
                color: isMe ? Colors.white70 : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
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
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFF5F0E8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
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
