import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../../shared/main_layout.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../warden/widgets/warden_widgets.dart' show LinenBackground;
import '../../shared/widgets/raise_issue_header_button.dart';

class ItDashboardScreen extends StatefulWidget {
  const ItDashboardScreen({super.key});

  @override
  State<ItDashboardScreen> createState() => _ItDashboardScreenState();
}

class _ItDashboardScreenState extends State<ItDashboardScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  bool _isSyncing = false;
  String _syncProgressMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.fetchItDashboardStats();
      if (mounted) {
        if (res['success'] == true) {
          setState(() {
            _stats = res['data'] as Map<String, dynamic>?;
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

  Future<void> _startBulkSync() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.sync_rounded, color: Color(0xFFD4AF37)),
            SizedBox(width: 8),
            Text('Start Biometric Audit?'),
          ],
        ),
        content: const Text(
          'This will audit all student accounts against the university biometric attendance server to verify punch registration.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Start Audit Scan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isSyncing = true;
      _syncProgressMessage = 'Auditing student registrations...';
    });

    try {
      int offset = 0;
      const int batchSize = 100;
      bool hasMore = true;

      while (hasMore) {
        final res = await ApiService.syncBiometricAuditBatch(limit: batchSize, offset: offset);
        if (res['success'] == true) {
          final total = res['total_students'] ?? 0;
          hasMore = res['has_more'] == true;
          offset = res['next_offset'] ?? (offset + batchSize);

          if (mounted) {
            setState(() {
              _syncProgressMessage = 'Audited $offset of $total students...';
            });
          }
        } else {
          break;
        }
      }

      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncProgressMessage = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF10B981),
            content: Text('Audit scan complete! Stats refreshed.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        );
        _fetchStats();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncProgressMessage = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Color(0xFFD4AF37), content: Text('Sync completed.')),
        );
      }
    }
  }

  Color _getHostelColor(String hostel) {
    final h = hostel.toLowerCase();
    if (h.contains('vaigai')) return const Color(0xFF2563EB); // Royal Blue
    if (h.contains('krishna')) return const Color(0xFF8B5CF6); // Purple
    if (h.contains('siruvani')) return const Color(0xFF0D9488); // Teal
    if (h.contains('ponni')) return const Color(0xFFF43F5E); // Rose
    if (h.contains('kaveri')) return const Color(0xFFD97706); // Amber
    if (h.contains('palar')) return const Color(0xFF059669); // Emerald
    if (h.contains('noyyal')) return const Color(0xFF6366F1); // Indigo
    if (h.contains('porunai')) return const Color(0xFFBE123C); // Crimson
    if (h.contains('radiance')) return const Color(0xFFB45309); // Bronze
    if (h.contains('stunner')) return const Color(0xFF475569); // Slate
    return const Color(0xFF64748B);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = context.watch<WallpaperProvider>().isDarkTheme;
    final user = context.watch<UserProvider>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: 'IT Biometric Portal',
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1E293B),
            Color(0xFF0F172A),
          ],
        ),
        titleColor: const Color(0xFFD4AF37),
        borderColor: const Color(0xFFD4AF37).withOpacity(0.5),
        onHomeTap: () => context.findAncestorStateOfType<MainResponsiveLayoutState>()?.setSelectedIndex(0),
        rightAction: const RaiseIssueHeaderButton(),
      ),
      body: LinenBackground(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
                ),
              )
            : RefreshIndicator(
                onRefresh: _fetchStats,
                color: const Color(0xFFD4AF37),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Welcome Header Card
                      _buildWelcomeCard(user, isDark),
                      const SizedBox(height: 16),

                      // Sync In Progress Banner
                      if (_isSyncing) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4AF37).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  _syncProgressMessage,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : const Color(0xFF1B2B48),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Summary Stats Grid (Using Gold instead of Red for Not Registered)
                      _buildSummaryGrid(isDark),
                      const SizedBox(height: 18),

                      // Quick Action: Universal Search
                      _buildQuickActionCard(isDark),
                      const SizedBox(height: 18),

                      // Hostel-wise Sync Breakdown
                      _buildHostelBreakdownCard(isDark),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildWelcomeCard(UserProvider user, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF162032) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.fingerprint_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'IT Biometric Hub',
                  style: TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1B2B48),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Live Attendance & Machine Sync Audit',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _isSyncing ? null : _startBulkSync,
            icon: const Icon(Icons.sync_rounded, size: 15),
            label: const Text('Scan All'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: const Color(0xFF1B2B48),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              elevation: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryGrid(bool isDark) {
    final total = int.tryParse(_stats?['total_students']?.toString() ?? '0') ?? 0;
    final synced = int.tryParse(_stats?['synced_count']?.toString() ?? '0') ?? 0;
    final notSynced = int.tryParse(_stats?['not_synced_count']?.toString() ?? '0') ?? 0;
    final percentage = double.tryParse(_stats?['sync_percentage']?.toString() ?? '0') ?? 0.0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Total Students',
                '$total',
                Icons.people_alt_outlined,
                const Color(0xFF2563EB),
                const [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                isDark,
                subtitle: 'Active Enrollments',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                'Registered Rate',
                '${percentage.toStringAsFixed(1)}%',
                Icons.verified_rounded,
                const Color(0xFF10B981),
                const [Color(0xFF10B981), Color(0xFF047857)],
                isDark,
                subtitle: '$synced of $total',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Registered',
                '$synced',
                Icons.fingerprint_rounded,
                const Color(0xFF0D9488),
                const [Color(0xFF14B8A6), Color(0xFF0F766E)],
                isDark,
                subtitle: 'Attendance Active',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                'Not Registered',
                '$notSynced',
                Icons.pending_actions_rounded,
                const Color(0xFFD4AF37),
                const [Color(0xFFF59E0B), Color(0xFFD97706)],
                isDark,
                subtitle: 'Pending Punch Sync',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color accentColor,
    List<Color> gradientColors,
    bool isDark, {
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF162032) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withOpacity(0.25), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.grey.shade700,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradientColors),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: gradientColors[0].withOpacity(0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1B2B48),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white38 : Colors.grey.shade500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActionCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF172554)]
              : [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3B82F6).withOpacity(0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.search_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Universal Student Search',
                  style: TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1B2B48),
                  ),
                ),
                Text(
                  'Audit any student, query live machine, assign biometric IDs',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              final mainState = context.findAncestorStateOfType<MainResponsiveLayoutState>();
              mainState?.setSelectedIndex(1);
            },
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            color: const Color(0xFF2563EB),
          ),
        ],
      ),
    );
  }

  Widget _buildHostelBreakdownCard(bool isDark) {
    final breakdown = (_stats?['hostel_breakdown'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF162032) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Hostel-wise Sync Breakdown',
                style: TextStyle(
                  fontFamily: 'Lato',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1B2B48),
                ),
              ),
              const Icon(
                Icons.apartment_rounded,
                color: Color(0xFFD4AF37),
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (breakdown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No hostel audit data available yet. Click "Scan All" to generate.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                ),
              ),
            )
          else
            ...breakdown.map((item) {
              final hostel = item['hostel']?.toString() ?? 'Unknown';
              final total = int.tryParse(item['total']?.toString() ?? '0') ?? 0;
              final synced = int.tryParse(item['synced']?.toString() ?? '0') ?? 0;
              final pct = total > 0 ? (synced / total) : 0.0;
              final hostelColor = _getHostelColor(hostel);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: hostelColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              hostel,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : const Color(0xFF1B2B48),
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: hostelColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$synced / $total (${(pct * 100).toStringAsFixed(0)}%)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: hostelColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: pct.clamp(0.0, 1.0),
                        minHeight: 7,
                        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(hostelColor),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
