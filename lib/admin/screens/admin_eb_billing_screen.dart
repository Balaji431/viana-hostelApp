import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../warden/widgets/warden_widgets.dart' show LinenBackground;
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../dialogs/generate_eb_bill_dialog.dart';

class AdminEBBillingScreen extends StatefulWidget {
  final bool showAppBar;

  const AdminEBBillingScreen({super.key, this.showAppBar = true});

  @override
  State<AdminEBBillingScreen> createState() => _AdminEBBillingScreenState();
}

class _AdminEBBillingScreenState extends State<AdminEBBillingScreen> {
  List<Map<String, dynamic>> _readings = [];
  Map<String, dynamic> _metrics = {};
  bool _isLoading = true;
  String _statusFilter = 'all';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchReadings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchReadings() async {
    setState(() => _isLoading = true);

    final res = await ApiService.getEBReadings(
      status: _statusFilter,
      roomNo: _searchController.text.trim().isNotEmpty ? _searchController.text.trim() : null,
      limit: 100,
    );

    if (mounted) {
      if (res['status'] == 'success') {
        setState(() {
          _readings = List<Map<String, dynamic>>.from(res['data'] ?? []);
          _metrics = res['metrics'] ?? {};
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
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

  void _openBillingDialog(Map<String, dynamic> reading) {
    final user = context.read<UserProvider>();
    showDialog(
      context: context,
      builder: (ctx) => GenerateEBBillDialog(
        reading: reading,
        adminUsername: user.username.isNotEmpty ? user.username : 'admin',
        onBillGenerated: _fetchReadings,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.showAppBar
          ? SkeuomorphicNavBar(
              title: 'EB & Power Billing Manager',
              onHomeTap: () => Navigator.pop(context),
              rightAction: IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                tooltip: 'Refresh',
                onPressed: _fetchReadings,
              ),
            )
          : null,
      body: LinenBackground(
        child: RefreshIndicator(
          onRefresh: _fetchReadings,
          color: const Color(0xFFC5A358),
          child: Column(
            children: [
              // Top Stats Banner
              _buildMetricsStrip(isDark),

              // Search & Filter Bar
              _buildFilterBar(isDark),

              // List of Readings
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
                                  'No meter readings recorded yet',
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
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                            itemCount: _readings.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final item = _readings[index];
                              return _buildReadingAdminCard(item, isDark);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricsStrip(bool isDark) {
    final total = _metrics['total_inspections'] ?? 0;
    final pending = _metrics['pending_count'] ?? 0;
    final billed = _metrics['billed_count'] ?? 0;
    final highLoad = _metrics['high_load_count'] ?? 0;
    final totalUnits = _metrics['total_units'] ?? 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.85) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2DACC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Total Checked', '$total', isDark ? Colors.white : Colors.black87),
          Container(height: 30, width: 1, color: isDark ? Colors.white12 : Colors.black12),
          _buildStatItem('Pending Review', '$pending', const Color(0xFFE65100)),
          Container(height: 30, width: 1, color: isDark ? Colors.white12 : Colors.black12),
          _buildStatItem('Billed', '$billed', const Color(0xFF2E7D32)),
          Container(height: 30, width: 1, color: isDark ? Colors.white12 : Colors.black12),
          _buildStatItem('High Load (>1.5kW)', '$highLoad', highLoad > 0 ? Colors.redAccent : Colors.teal),
          Container(height: 30, width: 1, color: isDark ? Colors.white12 : Colors.black12),
          _buildStatItem('Total Units', '${(totalUnits as num).toStringAsFixed(0)} kWh', const Color(0xFFC5A358)),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildFilterBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search Room No...',
                  prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFFC5A358)),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            _fetchReadings();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF0F172A).withOpacity(0.6) : Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFC5A358)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                ),
                onSubmitted: (_) => _fetchReadings(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatusTab('All', 'all', isDark),
                const SizedBox(width: 6),
                _buildStatusTab('Pending', 'pending', isDark),
                const SizedBox(width: 6),
                _buildStatusTab('Billed', 'billed', isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTab(String label, String value, bool isDark) {
    final isSelected = _statusFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _statusFilter = value);
          _fetchReadings();
        }
      },
      selectedColor: const Color(0xFFC5A358),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected ? const Color(0xFFC5A358) : (isDark ? Colors.white12 : Colors.black12),
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildReadingAdminCard(Map<String, dynamic> item, bool isDark) {
    final roomNo = item['room_no'] ?? '-';
    final hostelName = item['hostel_name'] ?? 'Hostel';
    final status = (item['status'] ?? 'pending').toString().toLowerCase();
    final unitsConsumed = double.tryParse(item['units_consumed']?.toString() ?? '0') ?? 0.0;
    final prevReading = double.tryParse(item['previous_reading']?.toString() ?? '0') ?? 0.0;
    final currReading = double.tryParse(item['current_reading']?.toString() ?? '0') ?? 0.0;
    final volts = double.tryParse(item['volts']?.toString() ?? '230') ?? 230.0;
    final watts = double.tryParse(item['watts']?.toString() ?? '0') ?? 0.0;
    final isHighWattage = watts >= 1500;
    final photoUrl = item['photo_url']?.toString();
    final inspectorName = item['inspector_name'] ?? item['recorded_by'] ?? 'Staff';
    final createdAt = item['created_at']?.toString() ?? '';
    final notes = item['notes']?.toString() ?? '';
    final anomalyTags = item['anomaly_tags']?.toString() ?? '';
    final billedAmount = item['billed_amount'];

    String formattedDate = createdAt;
    try {
      final dt = DateTime.parse(createdAt);
      formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(dt.toLocal());
    } catch (_) {}

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.85) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighWattage
              ? Colors.redAccent.withOpacity(0.6)
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
            // Row 1: Room, Hostel & Actions
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
                      child: const Icon(Icons.meeting_room, color: Color(0xFFC5A358), size: 24),
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
                          '$hostelName • By $inspectorName',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Status or Action Button
                if (status == 'pending')
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC5A358),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    onPressed: () => _openBillingDialog(item),
                    icon: const Icon(Icons.receipt_long, size: 16),
                    label: const Text('Issue Bill', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2E7D32)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, size: 14, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 4),
                        Text(
                          billedAmount != null ? 'BILLED: ₹$billedAmount' : 'BILLED',
                          style: const TextStyle(
                            color: Color(0xFF2E7D32),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Row 2: Reading Details & Electrical Metrics
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A).withOpacity(0.7) : const Color(0xFFFBF9F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildReadingDetail('Meter Reading', '${prevReading.toStringAsFixed(1)} → ${currReading.toStringAsFixed(1)}', isDark),
                  Container(height: 25, width: 1, color: isDark ? Colors.white12 : Colors.black12),
                  _buildReadingDetail('Units Burned', '${unitsConsumed.toStringAsFixed(1)} kWh', isDark, highlight: true),
                  Container(height: 25, width: 1, color: isDark ? Colors.white12 : Colors.black12),
                  _buildReadingDetail('Volts', '${volts.toStringAsFixed(0)} V', isDark),
                  Container(height: 25, width: 1, color: isDark ? Colors.white12 : Colors.black12),
                  _buildReadingDetail(
                    'Load (W)',
                    '${watts.toStringAsFixed(0)} W',
                    isDark,
                    color: isHighWattage ? Colors.redAccent : Colors.teal,
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
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Excessive Load Detected: Over 1500 Watts burned simultaneously in this room!',
                        style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
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
                    backgroundColor: cleanTag == 'Normal' ? const Color(0xFF475569) : Colors.redAccent.shade700,
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
                          Icon(Icons.photo_camera, size: 14, color: Color(0xFFC5A358)),
                          SizedBox(width: 4),
                          Text('Meter Photo Proof', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFC5A358))),
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

  Widget _buildReadingDetail(String label, String val, bool isDark, {bool highlight = false, Color? color}) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.black54)),
        const SizedBox(height: 2),
        Text(
          val,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color ?? (highlight ? const Color(0xFFC5A358) : (isDark ? Colors.white : Colors.black87)),
          ),
        ),
      ],
    );
  }
}
