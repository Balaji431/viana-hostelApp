import 'package:flutter/material.dart';
import 'warden_home_tab.dart';
import 'warden_attendance_tab.dart';
import 'warden_reports_tab.dart';
import 'warden_management_tab.dart';
import '../../shared/widgets/glassmorphic_jelly_navbar.dart';

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
      bottomNavigationBar: GlassmorphicJellyNavbar(
        currentIndex: _selectedIndex,
        totalTabs: 4,
        tabs: const [
          GlassmorphicTabItem(
            label: 'Home',
            icon: Icons.home_outlined,
            activeIcon: Icons.home,
          ),
          GlassmorphicTabItem(
            label: 'Attendance',
            icon: Icons.calendar_month_outlined,
            activeIcon: Icons.calendar_month,
          ),
          GlassmorphicTabItem(
            label: 'Reports',
            icon: Icons.bar_chart_outlined,
            activeIcon: Icons.bar_chart,
          ),
          GlassmorphicTabItem(
            label: 'Management',
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings,
          ),
        ],
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
            if (index != 2) _reportsCategoryFilter = null;
          });
        },
      ),
    );
  }
}
