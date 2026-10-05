import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../../shared/main_layout.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../warden/widgets/warden_widgets.dart' show LinenBackground;
import 'it_biometric_history_screen.dart';

class ItAuditHistoryScreen extends StatefulWidget {
  const ItAuditHistoryScreen({super.key});

  @override
  State<ItAuditHistoryScreen> createState() => _ItAuditHistoryScreenState();
}

class _ItAuditHistoryScreenState extends State<ItAuditHistoryScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Map<String, dynamic>> _recentActivity = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchActivity();
  }

  Future<void> _fetchActivity() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.fetchItDashboardStats();
      if (mounted) {
        if (res['success'] == true) {
          final data = res['data'] as Map<String, dynamic>? ?? {};
          final list = (data['recent_activity'] as List?)
                  ?.map((e) => Map<String, dynamic>.from(e))
                  .toList() ??
              [];
          setState(() {
            _recentActivity = list;
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return 'ST';
    if (parts.length == 1) return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = context.watch<WallpaperProvider>().isDarkTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: 'Recent Biometric Audit Log',
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A2744),
            Color(0xFF2A3A5C),
          ],
        ),
        titleColor: const Color(0xFFD4AF37),
        borderColor: const Color(0xFFD4AF37).withOpacity(0.5),
        onHomeTap: () => context.findAncestorStateOfType<MainResponsiveLayoutState>()?.setSelectedIndex(0),
        rightAction: ProfileButton(
          onTap: () => context.findAncestorStateOfType<MainResponsiveLayoutState>()?.setSelectedIndex(3),
        ),
      ),
      body: LinenBackground(
        child: Column(
          children: [
            // Deep Royal Navy Header Banner (Same as Student Home Page Header Blue)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF1A2744),
                    Color(0xFF2A3A5C),
                  ],
                ),
                border: Border(
                  bottom: BorderSide(color: Color(0xFFD4AF37), width: 1.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE5C058), Color(0xFFD4AF37), Color(0xFFB8860B)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFD4AF37).withOpacity(0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.history_rounded, color: Color(0xFF1B2B48), size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Live Biometric Audit Stream',
                          style: TextStyle(
                            fontFamily: 'Lato',
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 1),
                        Text(
                          'Real-time verified punch logs & machine checks',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFFD4AF37),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _fetchActivity,
                    icon: const Icon(Icons.refresh_rounded, color: Color(0xFFD4AF37), size: 20),
                  ),
                ],
              ),
            ),

            // Activity List with Image 2 style Cards
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
                      ),
                    )
                  : _recentActivity.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.checklist_rounded,
                                size: 52,
                                color: isDark ? Colors.white24 : Colors.grey.shade300,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No audit logs recorded yet',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchActivity,
                          color: const Color(0xFFD4AF37),
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                            itemCount: _recentActivity.length,
                            itemBuilder: (context, index) {
                              final item = _recentActivity[index];
                              final fullName = item['full_name']?.toString() ?? 'Student';
                              final regNo = item['register_no']?.toString() ?? 'N/A';
                              final hostel = item['hostel_name']?.toString() ?? 'N/A';
                              final room = item['room_allocation']?.toString() ?? 'N/A';
                              final isSynced = (item['is_synced'] == 1 || item['is_synced'] == true);
                              final records = item['records_found'] ?? 0;
                              final lastChecked = item['last_checked_at']?.toString() ?? '';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF162032) : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFE2E8F0),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => ItBiometricHistoryScreen(
                                            student: item,
                                            onDataUpdated: _fetchActivity,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      child: Row(
                                        children: [
                                          // Gold Circle Avatar with dark initials (Image 2 style)
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: const LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [Color(0xFFE5C058), Color(0xFFD4AF37), Color(0xFFB8860B)],
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFFD4AF37).withOpacity(0.35),
                                                  blurRadius: 6,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              _getInitials(fullName),
                                              style: const TextStyle(
                                                fontFamily: 'Lato',
                                                color: Color(0xFF1B2B48),
                                                fontWeight: FontWeight.w900,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 14),

                                          // Student details (Title, Room, Subtitle note)
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  fullName,
                                                  style: TextStyle(
                                                    fontFamily: 'Lato',
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.bold,
                                                    color: isDark ? Colors.white : const Color(0xFF1B2B48),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  'Room $room • $hostel',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                    color: isDark ? Colors.white70 : Colors.grey.shade700,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '"ID: $regNo • $lastChecked"',
                                                  style: TextStyle(
                                                    fontStyle: FontStyle.italic,
                                                    fontSize: 11,
                                                    color: isDark ? const Color(0xFFD4AF37) : const Color(0xFFB8860B),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),

                                          // Right Side: 3D Skeuomorphic Pill Badge (Image 2 style)
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topCenter,
                                                    end: Alignment.bottomCenter,
                                                    colors: isSynced
                                                        ? [const Color(0xFF4ADE80), const Color(0xFF16A34A)]
                                                        : [const Color(0xFFFBBF24), const Color(0xFFD97706)],
                                                  ),
                                                  borderRadius: BorderRadius.circular(12),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: (isSynced ? const Color(0xFF16A34A) : const Color(0xFFD97706)).withOpacity(0.35),
                                                      blurRadius: 4,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Text(
                                                  isSynced ? 'Registered' : 'Not Registered',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                    letterSpacing: 0.2,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                isSynced
                                                    ? (records > 0 ? '$records punch logs' : 'Active')
                                                    : 'Pending',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            color: isDark ? Colors.white38 : Colors.grey.shade400,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
