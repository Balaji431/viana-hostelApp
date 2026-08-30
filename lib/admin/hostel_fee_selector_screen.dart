import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/providers/hierarchical_hostel_provider.dart';
import '../shared/wallpaper_provider.dart';
import 'fee_manager_screen.dart';
import '../shared/widgets/skeuomorphic_navbar.dart';
import '../core/styles.dart';
import '../core/api_service.dart';

class HostelFeeSelectorScreen extends StatefulWidget {
  final bool isEmbedded;
  const HostelFeeSelectorScreen({super.key, this.isEmbedded = false});

  @override
  State<HostelFeeSelectorScreen> createState() => _HostelFeeSelectorScreenState();
}

class _HostelFeeSelectorScreenState extends State<HostelFeeSelectorScreen> {
  List<dynamic> _hostels = [];
  Map<String, int> _roomCounts = {};
  bool _isLoading = true;

  // Standard Navy Blue skeuomorphic theme for all hostels
  static const _HostelTheme _navyGoldTheme = _HostelTheme(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1A2744), Color(0xFF2D4A7A)],
    ),
    icon: Icons.apartment,
    badge: Color(0xFFD4AF37),
  );

  // Diverse hostel icons for avatars
  static const List<IconData> _hostelIcons = [
    Icons.apartment,
    Icons.villa,
    Icons.home_work,
    Icons.domain,
    Icons.location_city,
    Icons.business,
    Icons.maps_home_work,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHostels();
    });
  }

  Future<void> _loadHostels() async {
    setState(() => _isLoading = true);
    try {
      final provider = Provider.of<HierarchicalHostelProvider>(context, listen: false);
      await provider.loadHostels();

      final summaryRes = await ApiService.getExternalFeesSummary();
      Map<String, int> counts = {};
      if (summaryRes['success']) {
        final data = summaryRes['data'] as Map<String, dynamic>;
        data.forEach((k, v) => counts[k] = v as int);
      }

      if (mounted) {
        setState(() {
          _hostels = provider.hostels.map((h) => {
            'id': h.id,
            'name': h.name,
            'campus': h.campus,
          }).toList();
          _roomCounts = counts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Load hostels error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  int _getRoomCount(String name) {
    int count = _roomCounts[name] ?? 0;
    if (count == 0) {
      final nameWithHostel = name.endsWith('Hostel') ? name : '$name Hostel';
      count = _roomCounts[nameWithHostel] ?? 0;
    }
    if (count == 0) {
      final nameWithoutHostel =
          name.replaceAll(RegExp(r'\s*Hostel\s*$', caseSensitive: false), '').trim();
      count = _roomCounts[nameWithoutHostel] ?? 0;
    }
    return count;
  }

  Widget _buildHostelCard(dynamic hostel, int index, bool isDark) {
    final theme = _navyGoldTheme;
    final icon = _hostelIcons[index % _hostelIcons.length];
    final rawName = hostel['name'] ?? 'Unknown Hostel';
    final displayName =
        rawName.toLowerCase().contains('hostel') ? rawName : '$rawName Hostel';
    final campus = hostel['campus'] ?? 'N/A';
    final feeTypes = _getRoomCount(rawName);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => FeeManagerScreen(
              hostelId: int.tryParse(hostel['id'].toString()) ?? 0,
              hostelName: hostel['name'],
            ),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A).withOpacity(0.85) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.35 : 0.07),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              // ── Coloured gradient header strip ──────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: isDark
                      ? const LinearGradient(
                          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : theme.gradient,
                ),
                child: Row(
                  children: [
                    // Icon badge
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.25)),
                      ),
                      child: Icon(icon, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Campus: $campus',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.78),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Arrow
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_forward_ios,
                          size: 14, color: Colors.white),
                    ),
                  ],
                ),
              ),
              // ── Stats footer ────────────────────────────────────────
              Container(
                color: isDark ? const Color(0xFF131D2E).withOpacity(0.7) : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    _buildStat(
                      Icons.price_change_outlined,
                      '$feeTypes fee type${feeTypes == 1 ? '' : 's'}',
                      const Color(0xFFD4AF37),
                      isDark,
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AF37).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.4)),
                      ),
                      child: Text(
                        'Manage Fees →',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFD4AF37) : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStat(IconData icon, String label, Color color, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: isDark ? Colors.white70 : Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    Widget body = _isLoading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF1B2B48)))
        : _hostels.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.apartment_outlined,
                        size: 56, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text(
                      'No hostels found',
                      style: GoogleFonts.outfit(
                          color: Colors.grey.shade500, fontSize: 15),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                shrinkWrap: widget.isEmbedded,
                physics: widget.isEmbedded
                    ? const NeverScrollableScrollPhysics()
                    : null,
                itemCount: _hostels.length,
                itemBuilder: (context, index) =>
                    _buildHostelCard(_hostels[index], index, isDark),
              );

    if (widget.isEmbedded) return body;

    return LinenGridBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: SkeuomorphicNavBar(
          title: 'Select Hostel for Fees',
          onBack: () => Navigator.pop(context),
          rightAction: IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
            onPressed: _loadHostels,
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
        ),
        body: body,
      ),
    );
  }
}

/// Immutable theme descriptor for each hostel card
class _HostelTheme {
  final LinearGradient gradient;
  final IconData icon;
  final Color badge;
  const _HostelTheme(
      {required this.gradient, required this.icon, required this.badge});
}
