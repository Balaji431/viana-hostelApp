import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../warden/widgets/warden_widgets.dart' show LinenBackground;
import '../../shared/widgets/skeuomorphic_navbar.dart';
import 'eb_reading_history_screen.dart';

class EBMeterReadingScreen extends StatefulWidget {
  final String? initialRoomNo;
  final String? initialHostelName;
  final String? initialFloorName;

  const EBMeterReadingScreen({
    super.key,
    this.initialRoomNo,
    this.initialHostelName,
    this.initialFloorName,
  });

  @override
  State<EBMeterReadingScreen> createState() => _EBMeterReadingScreenState();
}

class _EBMeterReadingScreenState extends State<EBMeterReadingScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _hostelController = TextEditingController();
  final TextEditingController _floorController = TextEditingController();
  final TextEditingController _roomNoController = TextEditingController();
  final TextEditingController _currentReadingController = TextEditingController();

  // Hierarchy Dropdown State
  Map<String, Map<String, List<String>>> _hierarchyTree = {};
  bool _isLoadingHierarchy = true;
  String? _selectedHostel;
  String? _selectedFloor;
  String? _selectedRoom;

  // State
  bool _isSubmitting = false;
  double _previousReading = 0.0;

  @override
  void initState() {
    super.initState();
    _loadHierarchy();
  }

  Future<void> _loadHierarchy() async {
    setState(() => _isLoadingHierarchy = true);
    try {
      final user = Provider.of<UserProvider>(context, listen: false);
      final res = await ApiService.getHostelHierarchyEB(
        staffUsername: user.username,
        role: user.roleName,
      );
      if (mounted && res['status'] == 'success' && res['data'] is Map) {
        final raw = res['data'] as Map;
        final Map<String, Map<String, List<String>>> parsed = {};
        raw.forEach((hKey, fVal) {
          if (fVal is Map) {
            final Map<String, List<String>> floors = {};
            fVal.forEach((floorKey, roomVal) {
              if (roomVal is List) {
                floors[floorKey.toString()] = roomVal.map((r) => r.toString()).toList();
              }
            });
            parsed[hKey.toString()] = floors;
          }
        });

        setState(() {
          _hierarchyTree = parsed;
          _isLoadingHierarchy = false;

          // Auto-select if only 1 hostel assigned
          if (_selectedHostel == null) {
            if (widget.initialHostelName != null && _hierarchyTree.containsKey(widget.initialHostelName)) {
              _selectedHostel = widget.initialHostelName;
              _hostelController.text = widget.initialHostelName!;
            } else if (_hierarchyTree.length == 1) {
              _selectedHostel = _hierarchyTree.keys.first;
              _hostelController.text = _selectedHostel!;
            }
          }

          // Auto-select if only 1 floor assigned
          if (_selectedHostel != null && _hierarchyTree.containsKey(_selectedHostel)) {
            final floors = _hierarchyTree[_selectedHostel]!;
            if (_selectedFloor == null) {
              if (widget.initialFloorName != null && floors.containsKey(widget.initialFloorName)) {
                _selectedFloor = widget.initialFloorName;
                _floorController.text = widget.initialFloorName!;
              } else if (floors.length == 1) {
                _selectedFloor = floors.keys.first;
                _floorController.text = _selectedFloor!;
              }
            }
          }

          if (widget.initialRoomNo != null) {
            _roomNoController.text = widget.initialRoomNo!;
            _selectedRoom = widget.initialRoomNo;
            _fetchRoomInfo();
          }
        });
        return;
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoadingHierarchy = false);
  }

  void _onHostelSelected(String? hostel) {
    setState(() {
      _selectedHostel = hostel;
      _hostelController.text = hostel ?? '';
      _selectedFloor = null;
      _floorController.clear();
      _selectedRoom = null;
      _roomNoController.clear();
      _previousReading = 0.0;
    });
  }

  void _onFloorSelected(String? floor) {
    setState(() {
      _selectedFloor = floor;
      _floorController.text = floor ?? '';
      _selectedRoom = null;
      _roomNoController.clear();
      _previousReading = 0.0;
    });
  }

  void _onRoomSelected(String? room) {
    if (room == null || room.isEmpty) return;
    setState(() {
      _selectedRoom = room;
      _roomNoController.text = room;
    });
    _fetchRoomInfo();
  }

  @override
  void dispose() {
    _hostelController.dispose();
    _floorController.dispose();
    _roomNoController.dispose();
    _currentReadingController.dispose();
    super.dispose();
  }

  double get _unitsBurned {
    final current = double.tryParse(_currentReadingController.text.trim()) ?? 0.0;
    if (current < _previousReading) return 0.0;
    return double.parse((current - _previousReading).toStringAsFixed(2));
  }

  Future<void> _fetchRoomInfo() async {
    final room = _roomNoController.text.trim();
    if (room.isEmpty) return;

    try {
      final res = await ApiService.getRoomMeterInfo(
        roomNo: room,
        hostelName: _hostelController.text.trim().isNotEmpty ? _hostelController.text.trim() : null,
      );

      if (mounted && res['status'] == 'success') {
        final data = res['data'] ?? {};
        setState(() {
          _previousReading = double.tryParse(data['previous_reading']?.toString() ?? '0') ?? 0.0;
          if (data['hostel_name'] != null && _hostelController.text.isEmpty) {
            _hostelController.text = data['hostel_name'].toString();
          }
          if (data['floor_no'] != null && _floorController.text.isEmpty) {
            _floorController.text = data['floor_no'].toString();
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _submitReading() async {
    if (!_formKey.currentState!.validate()) return;

    final currentReading = double.tryParse(_currentReadingController.text.trim()) ?? 0.0;
    if (currentReading < _previousReading) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Current units cannot be less than previous reading (${_previousReading.toStringAsFixed(2)} kWh)'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final user = context.read<UserProvider>();
    final payload = {
      'hostel_name': _hostelController.text.trim(),
      'floor_no': _floorController.text.trim(),
      'room_no': _roomNoController.text.trim(),
      'meter_no': '',
      'previous_reading': _previousReading,
      'current_reading': currentReading,
      'volts': 230.0,
      'watts': 0.0,
      'photo_base64': null,
      'anomaly_tags': 'Normal',
      'notes': '',
      'recorded_by': user.username.isNotEmpty ? user.username : 'maintenance',
      'inspector_name': user.userName.isNotEmpty ? user.userName : 'Maintenance Staff',
    };

    final res = await ApiService.submitEBMeterReading(payload);

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (res['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Room ${_roomNoController.text} verified! ($currentReading units logged)'),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Failed to submit reading'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: 'Enter Room EB Units',
        onHomeTap: () => Navigator.pop(context),
        rightAction: IconButton(
          icon: const Icon(Icons.history, color: Colors.white),
          tooltip: 'Inspection History',
          onPressed: () {
            final user = context.read<UserProvider>();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EBReadingHistoryScreen(recordedBy: user.username),
              ),
            );
          },
        ),
      ),
      body: LinenBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader('Enter Meter Units', Icons.electric_meter, isDark),
                const SizedBox(height: 12),
                _buildCardContainer(
                  isDark: isDark,
                  child: _isLoadingHierarchy
                      ? Container(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: const Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Color(0xFFC5A358), strokeWidth: 2),
                                ),
                                SizedBox(width: 14),
                                Text(
                                  'Loading Hostels, Floors & Rooms...',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Hostel Name Selection (Full Width)
                            _buildDropdownField<String>(
                              value: _selectedHostel,
                              label: 'Hostel / Building *',
                              hint: 'Select Hostel',
                              icon: Icons.business,
                              isDark: isDark,
                              items: (_hierarchyTree.keys.toList()..sort()).map((h) {
                                return DropdownMenuItem<String>(
                                  value: h,
                                  child: Text(h, overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                              onChanged: _onHostelSelected,
                              validator: (val) => (val == null || val.isEmpty) ? 'Please select a hostel' : null,
                            ),
                            const SizedBox(height: 14),

                            // 2. Hostel Floor Selection (Full Width)
                            _buildDropdownField<String>(
                              value: _selectedFloor,
                              enabled: _selectedHostel != null,
                              label: 'Hostel Floor *',
                              hint: _selectedHostel == null ? 'Select Hostel first' : 'Select Floor',
                              icon: Icons.layers,
                              isDark: isDark,
                              items: (_selectedHostel != null && _hierarchyTree.containsKey(_selectedHostel))
                                  ? (_hierarchyTree[_selectedHostel]!.keys.toList()..sort()).map((f) {
                                      return DropdownMenuItem<String>(
                                        value: f,
                                        child: Text(f, overflow: TextOverflow.ellipsis),
                                      );
                                    }).toList()
                                  : [],
                              onChanged: _onFloorSelected,
                              validator: (val) => (val == null || val.isEmpty) ? 'Please select a floor' : null,
                            ),
                            const SizedBox(height: 14),

                            // 3. Hostel Room Selection (Full Width)
                            _buildDropdownField<String>(
                              value: _selectedRoom,
                              enabled: _selectedFloor != null,
                              label: 'Hostel Room *',
                              hint: _selectedFloor == null ? 'Select Floor first' : 'Select Room',
                              icon: Icons.meeting_room,
                              isDark: isDark,
                              items: (_selectedHostel != null &&
                                      _selectedFloor != null &&
                                      _hierarchyTree.containsKey(_selectedHostel) &&
                                      _hierarchyTree[_selectedHostel]!.containsKey(_selectedFloor))
                                  ? (_hierarchyTree[_selectedHostel]![_selectedFloor]!..sort()).map((rm) {
                                      return DropdownMenuItem<String>(
                                        value: rm,
                                        child: Text(rm, overflow: TextOverflow.ellipsis),
                                      );
                                    }).toList()
                                  : [],
                              onChanged: _onRoomSelected,
                              validator: (val) => (val == null || val.isEmpty) ? 'Please select a room' : null,
                            ),

                            // EMPTY SECTION WITH 75% UNITS INPUT + 25% SUBMIT BUTTON IN THE SAME SECTION
                            const SizedBox(height: 18),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 75% Enter Units Input
                                Expanded(
                                  flex: 3,
                                  child: _buildTextField(
                                    controller: _currentReadingController,
                                    label: 'Units (kWh) *',
                                    hint: 'e.g. 1450',
                                    icon: Icons.electric_meter,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    isDark: isDark,
                                    validator: (val) {
                                      if (val == null || val.trim().isEmpty) return 'Enter units';
                                      if (double.tryParse(val.trim()) == null) return 'Invalid';
                                      return null;
                                    },
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // 25% Submit Button
                                Expanded(
                                  flex: 1,
                                  child: SizedBox(
                                    height: 52,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFC5A358),
                                        foregroundColor: Colors.white,
                                        elevation: 3,
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      onPressed: _isSubmitting ? null : _submitReading,
                                      child: _isSubmitting
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                            )
                                          : const Text(
                                              'Submit',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // Burned Units Preview Indicator if units entered
                            if (_currentReadingController.text.trim().isNotEmpty && _unitsBurned > 0) ...[
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  '⚡ Consumed: +${_unitsBurned.toStringAsFixed(2)} kWh this period',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFC5A358),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, bool isDark) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFC5A358), size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF1B2B48),
          ),
        ),
      ],
    );
  }

  Widget _buildCardContainer({required Widget child, required bool isDark}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.85) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFE2DACC),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      onChanged: onChanged,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFFC5A358), size: 20),
        labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13),
        hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38, fontSize: 13),
        filled: true,
        fillColor: isDark ? const Color(0xFF0F172A).withOpacity(0.6) : const Color(0xFFFBF9F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFC5A358), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildDropdownField<T>({
    required T? value,
    required String label,
    required String hint,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?)? onChanged,
    required bool isDark,
    bool enabled = true,
    String? Function(T?)? validator,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: enabled ? onChanged : null,
      validator: validator,
      isExpanded: true,
      dropdownColor: isDark ? const Color(0xFF131D2E) : Colors.white,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black87,
        fontSize: 14,
      ),
      icon: Icon(
        Icons.arrow_drop_down,
        color: enabled ? const Color(0xFFC5A358) : (isDark ? Colors.white24 : Colors.black26),
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(
          icon,
          color: enabled ? const Color(0xFFC5A358) : (isDark ? Colors.white24 : Colors.black26),
          size: 20,
        ),
        labelStyle: TextStyle(
          color: enabled
              ? (isDark ? Colors.white70 : Colors.black54)
              : (isDark ? Colors.white30 : Colors.black26),
          fontSize: 13,
        ),
        hintStyle: TextStyle(
          color: isDark ? Colors.white30 : Colors.black38,
          fontSize: 13,
        ),
        filled: true,
        fillColor: enabled
            ? (isDark ? const Color(0xFF0F172A).withOpacity(0.6) : const Color(0xFFFBF9F5))
            : (isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.04)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFC5A358), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
