import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'warden_home_tab.dart';
import 'warden_attendance_tab.dart';
import 'warden_biometric_screen.dart';
import 'warden_reports_tab.dart';
import 'warden_management_tab.dart';
import '../../shared/widgets/glassmorphic_jelly_navbar.dart';

class WardenMainScreen extends StatefulWidget {
  final int initialTabIndex;
  final String? initialReportsCategory;
  const WardenMainScreen({
    super.key,
    this.initialTabIndex = 0,
    this.initialReportsCategory,
  });

  static _WardenMainScreenState? of(BuildContext context) =>
      context.findAncestorStateOfType<_WardenMainScreenState>();

  @override
  State<WardenMainScreen> createState() => _WardenMainScreenState();
}

class _WardenMainScreenState extends State<WardenMainScreen> {
  late int _selectedIndex;
  late PageController _pageController;
  String? _reportsCategoryFilter;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex;
    _reportsCategoryFilter = widget.initialReportsCategory;
    _pageController = PageController(initialPage: _selectedIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void setTabIndex(int index, {String? reportsCategory}) {
    setState(() {
      _selectedIndex = index;
      if (reportsCategory != null) {
        _reportsCategoryFilter = reportsCategory;
      }
    });
    if (_pageController.hasClients && _pageController.page?.round() != index) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 180),
        curve: Curves.fastOutSlowIn,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> tabs = [
      const WardenHomeTab(),
      const WardenAttendanceTab(),
      const WardenBiometricScreen(),
      WardenReportsTab(initialCategory: _reportsCategoryFilter),
      const WardenManagementTab(),
    ];

    final bool useSwipeView = !kIsWeb;

    return Scaffold(
      body: useSwipeView
          ? PageView(
              controller: _pageController,
              scrollDirection: Axis.horizontal,
              physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
              onPageChanged: (index) {
                if (_selectedIndex != index) {
                  setState(() {
                    _selectedIndex = index;
                    if (index != 3) _reportsCategoryFilter = null;
                  });
                }
              },
              children: tabs,
            )
          : IndexedStack(
              index: _selectedIndex,
              children: tabs,
            ),
      bottomNavigationBar: GlassmorphicJellyNavbar(
        currentIndex: _selectedIndex,
        totalTabs: 5,
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
            label: 'Biometric',
            icon: Icons.fingerprint_rounded,
            activeIcon: Icons.fingerprint,
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
          setTabIndex(index);
          if (index != 3) _reportsCategoryFilter = null;
        },
      ),
    );
  }
}
