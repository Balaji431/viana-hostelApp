import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/api_service.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../warden/widgets/warden_widgets.dart' show LinenBackground;
import '../../shared/widgets/skeuomorphic_navbar.dart';

class EBReadingHistoryScreen extends StatefulWidget {
  final String? recordedBy;

  const EBReadingHistoryScreen({super.key, this.recordedBy});

  @override
  State<EBReadingHistoryScreen> createState() => _EBReadingHistoryScreenState();
}

class _EBReadingHistoryScreenState extends State<EBReadingHistoryScreen> {
  List<Map<String, dynamic>> _readings = [];
  bool _isLoading = true;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() => _isLoading = true);
    final user = context.read<UserProvider>();
    final username = widget.recordedBy ?? user.username;

    final response = await ApiService.getEBReadings(
      status: _statusFilter,
      recordedBy: username.isNotEmpty ? username : null,
      limit: 100,
    );

    if (mounted) {
      if (response['status'] == 'success') {
        setState(() {
          _readings = List<Map<String, dynamic>>.from(response['data'] ?? []);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'billed':
        return const Color(0xFF2E7D32);
      case 'approved':
        return const Color(0xFF1976D2);
      case 'rejected':
        return const Color(0xFFD32F2F);
      case 'pending':
      default:
        return const Color(0xFFE65100);
    }
  }

  void _showPhotoDialog(String photoUrl) {
    final fullUrl = photoUrl.startsWith('http') ? photoUrl : ApiService.buildUri(photoUrl).toString();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                fullUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  padding: const EdgeInsets.all(20),
                  color: Colors.white,
                  child: const Text('Could not load image'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC5A358),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close),
              label: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: 'EB Inspection History',
        onHomeTap: () => Navigator.pop(context),
        rightAction: IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          tooltip: 'Refresh',
          onPressed: _fetchHistory,
        ),
      ),
      body: LinenBackground(
        child: RefreshIndicator(
          onRefresh: _fetchHistory,
          color: const Color(0xFFC5A358),
          child: Column(
            children: [
              // Filter chips
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All', 'all', isDark),
                      const SizedBox(width: 8),
                      _buildFilterChip('Pending', 'pending', isDark),
                      const SizedBox(width: 8),
                      _buildFilterChip('Billed', 'billed', isDark),
                      const SizedBox(width: 8),
                      _buildFilterChip('Approved', 'approved', isDark),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFFC5A358)))
                    : _readings.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.electric_meter_outlined, size: 60, color: isDark ? Colors.white38 : Colors.black26),
                                const SizedBox(height: 12),
                                Text(
                                  'No meter readings found',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white70 : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                            itemCount: _readings.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final item = _readings[index];
                              return _buildReadingCard(item, isDark);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, bool isDark) {
    final isSelected = _statusFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _statusFilter = value);
          _fetchHistory();
        }
      },
      selectedColor: const Color(0xFFC5A358),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF334155)),
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 13,
      ),
      side: BorderSide(
        color: isSelected ? const Color(0xFFC5A358) : (isDark ? Colors.white12 : Colors.black12),
      ),
    );
  }

  Widget _buildReadingCard(Map<String, dynamic> item, bool isDark) {
    final roomNo = item['room_no'] ?? '-';
    final hostelName = item['hostel_name'] ?? 'Hostel';
    final status = (item['status'] ?? 'pending').toString();
    final unitsConsumed = double.tryParse(item['units_consumed']?.toString() ?? '0') ?? 0.0;
    final volts = double.tryParse(item['volts']?.toString() ?? '230') ?? 230.0;
    final watts = double.tryParse(item['watts']?.toString() ?? '0') ?? 0.0;
    final isHighWattage = watts >= 1500;
    final photoUrl = item['photo_url']?.toString();
    final createdAt = item['created_at']?.toString() ?? '';
    final notes = item['notes']?.toString() ?? '';
    final anomalyTags = item['anomaly_tags']?.toString() ?? '';

    String formattedDate = createdAt;
    try {
      final dt = DateTime.parse(createdAt);
      formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(dt.toLocal());
    } catch (_) {}

    final statusColor = _getStatusColor(status);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.85) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighWattage
              ? Colors.redAccent.withOpacity(0.5)
              : (isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFE2DACC)),
          width: isHighWattage ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Room & Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC5A358).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.meeting_room, color: Color(0xFFC5A358), size: 22),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Room $roomNo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF1B2B48),
                          ),
                        ),
                        Text(
                          hostelName,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.5)),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Row 2: Metrics Strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0B132B).withOpacity(0.6) : const Color(0xFFF8F6F0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMetricItem('Units Burned', '${unitsConsumed.toStringAsFixed(1)} kWh', const Color(0xFFC5A358), isDark),
                  Container(height: 25, width: 1, color: isDark ? Colors.white12 : Colors.black12),
                  _buildMetricItem('Volts', '${volts.toStringAsFixed(0)} V', Colors.blueAccent, isDark),
                  Container(height: 25, width: 1, color: isDark ? Colors.white12 : Colors.black12),
                  _buildMetricItem(
                    'Load',
                    '${watts.toStringAsFixed(0)} W',
                    isHighWattage ? Colors.redAccent : Colors.teal,
                    isDark,
                  ),
                ],
              ),
            ),

            if (isHighWattage) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'High Wattage Alert: Possible heavy appliance detected!',
                        style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (anomalyTags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: anomalyTags.split(',').map((tag) {
                  final cleanTag = tag.trim();
                  if (cleanTag.isEmpty) return const SizedBox.shrink();
                  return Chip(
                    label: Text(cleanTag, style: const TextStyle(fontSize: 10, color: Colors.white)),
                    backgroundColor: const Color(0xFF475569),
                    padding: const EdgeInsets.all(0),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],

            if (notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Notes: $notes',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],

            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formattedDate,
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38),
                ),
                if (photoUrl != null && photoUrl.isNotEmpty)
                  InkWell(
                    onTap: () => _showPhotoDialog(photoUrl),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC5A358).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.image, size: 14, color: Color(0xFFC5A358)),
                          SizedBox(width: 4),
                          Text('View Photo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFC5A358))),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricItem(String label, String value, Color valueColor, bool isDark) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
