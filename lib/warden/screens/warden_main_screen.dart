import 'package:flutter/material.dart';
import 'warden_home_tab.dart';
import 'warden_attendance_tab.dart';
import 'warden_reports_tab.dart';
import 'warden_management_tab.dart';

class WardenMainScreen extends StatefulWidget {
  const WardenMainScreen({super.key});

  static _WardenMainScreenState? of(BuildContext context) =>
      context.findAncestorStateOfType<_WardenMainScreenState>();

  @override
  State<WardenMainScreen> createState() => _WardenMainScreenState();
}

class _WardenMainScreenState extends State<WardenMainScreen> {
  int _selectedIndex = 0;
  String? _reportsCategoryFilter;

  void setTabIndex(int index, {String? reportsCategory}) {
    setState(() {
      _selectedIndex = index;
      if (reportsCategory != null) {
        _reportsCategoryFilter = reportsCategory;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> tabs = [
      const WardenHomeTab(),
      const WardenAttendanceTab(),
      WardenReportsTab(initialCategory: _reportsCategoryFilter),
      const WardenManagementTab(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: tabs,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3D3D3D), Color(0xFF1A1A1A)],
          ),
          boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, -2))],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
              // Reset filter if moving away from reports, or keep it? 
              // Usually reset to "All" when clicking the bottom tab directly
              if (index != 2) _reportsCategoryFilter = null;
            });
          },
          backgroundColor: Colors.transparent,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFFD4AF37),
          unselectedItemColor: Colors.grey,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          selectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontSize: 10),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home, shadows: [Shadow(color: Color(0xFFD4AF37), blurRadius: 8)]), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), activeIcon: Icon(Icons.calendar_month, shadows: [Shadow(color: Color(0xFFD4AF37), blurRadius: 8)]), label: 'Attendance'),
            BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), activeIcon: Icon(Icons.bar_chart, shadows: [Shadow(color: Color(0xFFD4AF37), blurRadius: 8)]), label: 'Reports'),
            BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings, shadows: [Shadow(color: Color(0xFFD4AF37), blurRadius: 8)]), label: 'Management'),
          ],
        ),
      ),
    );
  }
}
