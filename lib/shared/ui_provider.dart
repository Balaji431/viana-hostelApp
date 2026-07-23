import 'package:flutter/material.dart';

class UIProvider with ChangeNotifier {
  String? _activeChatChannel;
  bool _showBottomNavBar = true;
  
  String? get activeChatChannel => _activeChatChannel;
  bool get showBottomNavBar => _showBottomNavBar;
  
  void setActiveChatChannel(String? channel) {
    _activeChatChannel = channel;
    notifyListeners();
  }

  void setShowBottomNavBar(bool show) {
    if (_showBottomNavBar != show) {
      _showBottomNavBar = show;
      notifyListeners();
    }
  }
}
