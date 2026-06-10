import 'package:flutter/material.dart';

class UIProvider with ChangeNotifier {
  String? _activeChatChannel;
  
  String? get activeChatChannel => _activeChatChannel;
  
  void setActiveChatChannel(String? channel) {
    _activeChatChannel = channel;
    notifyListeners();
  }
}
