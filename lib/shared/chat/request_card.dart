import 'package:flutter/material.dart';
import '../../core/models/request_model.dart';
import 'package:intl/intl.dart';

class RequestCard extends StatelessWidget {
  final RequestModel request;
  final bool isMe;
  final VoidCallback onTap;

  const RequestCard({
    super.key,
    required this.request,
    required this.isMe,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                width: MediaQuery.of(context).size.width * 0.75,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getCardBgColor(request.status.toLowerCase()),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              request.department.toUpperCase(),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF7D8C9B)),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'ID: ${request.customId}',
                              style: const TextStyle(fontSize: 10, color: Color(0xFF7D8C9B), fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Text(
                      'Submitted request for ${request.requestType}.',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF1B2B48),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Status:', style: TextStyle(fontSize: 13, color: Color(0xFF8A9AAB))),
                        const SizedBox(width: 10),
                        Flexible(child: _buildStatusBadge(request.status)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${DateFormat('hh:mm a').format(request.createdAt)} • ',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF8A9AAB)),
                  ),
                  const Text(
                    'Tap for details',
                    style: TextStyle(fontSize: 11, color: Color(0xFFC5A358), fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color startColor;
    Color endColor;
    final s = status.toLowerCase();
    final dept = request.department.toLowerCase();

    if (s == 'completed' || (s == 'approved' && dept != 'maintenance')) {
      startColor = Colors.green.shade600;
      endColor = Colors.green.shade800;
    } else if (s == 'rejected') {
      startColor = const Color(0xFFEF5350);
      endColor = const Color(0xFFD32F2F);
    } else {
      startColor = Colors.orange.shade400;
      endColor = Colors.orange.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [startColor, endColor],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Text(
        (s == 'approved' || s == 'fixed' || s == 'reopened' || s == 'pending')
          ? (dept == 'maintenance' ? 'PENDING' : (status.length > 1 ? status[0].toUpperCase() + status.substring(1) : status.toUpperCase()))
          : (status.length > 1 ? status[0].toUpperCase() + status.substring(1) : status.toUpperCase()),
        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
  }

  Color _getCardBgColor(String status) {
    final s = status.toLowerCase();
    final dept = request.department.toLowerCase();
    
    if (s == 'completed' || (s == 'approved' && dept != 'maintenance')) {
      return const Color(0xFFC8E6C9);
    } else if (s == 'rejected') {
      return const Color(0xFFFFCDD2);
    } else {
      return const Color(0xFFFFE0B2);
    }
  }


}
