import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// WhatsApp-style local on-device message caching using Hive NoSQL.
/// Ensures 0ms instant chat rendering and offline history access.
class ChatCacheService {
  static const String _boxName = 'vstay_chat_store';
  static Box? _box;

  /// Ensure Hive box is open and ready
  static Future<Box?> _getBox() async {
    if (kIsWeb) return null;
    try {
      if (_box != null && _box!.isOpen) return _box;
      if (Hive.isBoxOpen(_boxName)) {
        _box = Hive.box(_boxName);
      } else {
        _box = await Hive.openBox(_boxName);
      }
      return _box;
    } catch (e) {
      debugPrint('ChatCacheService error opening box: $e');
      return null;
    }
  }

  /// Load cached messages for a specific request / conversation ID
  static Future<List<Map<String, dynamic>>> loadMessages(String requestId) async {
    if (requestId.isEmpty) return [];
    try {
      final box = await _getBox();
      if (box == null) return [];
      final raw = box.get('msgs_$requestId');
      if (raw == null) return [];

      if (raw is List) {
        return raw.map((item) {
          if (item is Map) {
            return Map<String, dynamic>.from(item);
          } else if (item is String) {
            return Map<String, dynamic>.from(jsonDecode(item));
          }
          return <String, dynamic>{};
        }).where((m) => m.isNotEmpty).toList();
      }
      return [];
    } catch (e) {
      debugPrint('ChatCacheService loadMessages error: $e');
      return [];
    }
  }

  /// Save full list of messages for a request / conversation ID
  static Future<void> saveMessages(String requestId, List<Map<String, dynamic>> messages) async {
    if (requestId.isEmpty) return;
    try {
      final box = await _getBox();
      if (box != null) {
        await box.put('msgs_$requestId', messages);
      }
    } catch (e) {
      debugPrint('ChatCacheService saveMessages error: $e');
    }
  }

  /// Append a single message to cached conversation
  static Future<void> saveMessage(String requestId, Map<String, dynamic> message) async {
    if (requestId.isEmpty) return;
    try {
      final current = await loadMessages(requestId);
      current.add(message);
      await saveMessages(requestId, current);
    } catch (e) {
      debugPrint('ChatCacheService saveMessage error: $e');
    }
  }

  /// Merges server messages with local on-device history so old messages (>45 days) stay visible on the phone
  static Future<List<Map<String, dynamic>>> mergeWithLocal(
    String requestId,
    List<Map<String, dynamic>> serverMessages,
  ) async {
    if (requestId.isEmpty) return serverMessages;
    try {
      final local = await loadMessages(requestId);
      if (local.isEmpty) {
        await saveMessages(requestId, serverMessages);
        return serverMessages;
      }

      final map = <String, Map<String, dynamic>>{};
      // 1. Keep local history (including past chats older than 45 days)
      for (final m in local) {
        final key = m['id']?.toString() ?? '${m['sender']}_${m['timestamp']}';
        map[key] = m;
      }

      // 2. Overwrite / insert updated server messages
      for (final m in serverMessages) {
        final key = m['id']?.toString() ?? '${m['sender']}_${m['timestamp']}';
        map[key] = m;
      }

      final merged = map.values.toList();
      await saveMessages(requestId, merged);
      return merged;
    } catch (e) {
      debugPrint('ChatCacheService mergeWithLocal error: $e');
      return serverMessages;
    }
  }

  /// Append a single new incoming or sent message to local storage
  static Future<void> appendMessage(String requestId, Map<String, dynamic> msg) async {
    if (requestId.isEmpty) return;
    try {
      final existing = await loadMessages(requestId);
      // Avoid duplicate messages by message id or timestamp+sender
      final msgId = msg['id'] ?? msg['message_id'];
      final exists = existing.any((m) {
        if (msgId != null && (m['id'] == msgId || m['message_id'] == msgId)) return true;
        return m['message'] == msg['message'] &&
               m['sender_id'] == msg['sender_id'] &&
               m['timestamp'] == msg['timestamp'];
      });

      if (!exists) {
        existing.add(msg);
        await saveMessages(requestId, existing);
      }
    } catch (e) {
      debugPrint('ChatCacheService appendMessage error: $e');
    }
  }

  /// Clear messages for a specific conversation or when logging out
  static Future<void> clearMessages(String requestId) async {
    try {
      final box = await _getBox();
      if (box != null) {
        await box.delete('msgs_$requestId');
      }
    } catch (e) {
      debugPrint('ChatCacheService clearMessages error: $e');
    }
  }

  /// Clear all cached chats on logout
  static Future<void> clearAll() async {
    try {
      final box = await _getBox();
      if (box != null) {
        await box.clear();
      }
    } catch (e) {
      debugPrint('ChatCacheService clearAll error: $e');
    }
  }
}
