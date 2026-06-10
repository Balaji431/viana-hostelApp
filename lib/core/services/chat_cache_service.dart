import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ChatCacheService {
  static Box? _getBox(String chatType) {
    if (kIsWeb) return null;
    try {
      return Hive.box('chat_$chatType');
    } catch (e) {
      return null;
    }
  }

  static List<Map<String, dynamic>> loadMessages(String chatType) {
    final box = _getBox(chatType);
    if (box == null) return [];
    return box.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static void saveMessage(String chatType, Map<String, dynamic> msg) {
    final box = _getBox(chatType);
    if (box != null) box.add(msg);
  }

  static void clearMessages(String chatType) {
    final box = _getBox(chatType);
    if (box != null) box.clear();
  }
}
