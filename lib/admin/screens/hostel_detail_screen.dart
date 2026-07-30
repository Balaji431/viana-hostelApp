import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'dart:convert';
import '../../core/api_service.dart';
import '../../core/styles.dart';

import '../../core/providers/hierarchical_hostel_provider.dart';
import 'package:vianasoft_stay/core/models/hierarchical_hostel_model.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';

class HostelDetailScreen extends StatefulWidget {
  final HierarchicalHostel hostel;
  final bool showAppBar;

  const HostelDetailScreen({
    super.key,
    required this.hostel,
    this.showAppBar = true,
  });

  @override
  State<HostelDetailScreen> createState() => HostelDetailScreenState();
}

class HostelDetailScreenState extends State<HostelDetailScreen> {

  BuildContext? _loadingContext;

  Future<void> _refreshData() async {
    if (!mounted) return;
    try {
      final provider = context.read<HierarchicalHostelProvider>();
      await provider.loadHostelHierarchy(widget.hostel);
    } catch (e) {
      debugPrint('Error refreshing data: $e');
    }
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        _loadingContext = dialogCtx;
        return Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF2D4A7A)),
                SizedBox(height: 16),
                Text('Updating hierarchy...', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _hideLoadingDialog() {
    if (_loadingContext != null && Navigator.canPop(_loadingContext!)) {
      Navigator.pop(_loadingContext!);
      _loadingContext = null;
    }
  }
  @override
  Widget build(BuildContext context) {
    final body = widget.hostel.zones.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.stairs_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'No floors created',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _addFloorAtRoot,
                  icon: const Icon(Icons.add),
                  label: const Text('Add First Floor'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: widget.hostel.zones.length + 1,
            itemBuilder: (context, index) {
              if (index == widget.hostel.zones.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 80),
                  child: OutlinedButton.icon(
                    onPressed: _addFloorAtRoot,
                    icon: const Icon(Icons.add),
                    label: const Text('Add New Floor'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      side: const BorderSide(color: Color(0xFFD4AF37)),
                      foregroundColor: const Color(0xFFD4AF37),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                );
              }
              final zone = widget.hostel.zones[index];
              return _buildFloorCard(zone, index);
            },
          );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.showAppBar
          ? SkeuomorphicNavBar(
              title: widget.hostel.name,
              onBack: () => Navigator.pop(context),
              rightAction: IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                onPressed: _refreshData,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            )
          : null,
      body: LinenGridBackground(child: body),
    );
  }

  static const List<IconData> _floorIcons = [
    Icons.stairs,
    Icons.layers_outlined,
    Icons.apartment,
    Icons.deck_outlined,
    Icons.balcony_outlined,
  ];

  Widget _buildFloorCard(Zone zone, int index) {
    final icon = _floorIcons[index % _floorIcons.length];
    return _FloorCardWidget(
      zone: zone,
      index: index,
      icon: icon,
      onEdit: () => _editFloor(zone),
      onDelete: () => _deleteFloor(zone),
      onAddWing: () => _addWingToFloor(zone),
      buildWingTile: (subZone, parentZone) => _buildWingTile(subZone, parentZone),
    );
  }

  Widget _buildWingTile(SubZone subZone, Zone parentZone) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9F8F5),
        border: Border(
          left: const BorderSide(color: Color(0xFFD4AF37), width: 3),
          bottom: BorderSide(color: Colors.black.withOpacity(0.06), width: 1),
        ),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.only(left: 20, right: 16, top: 6, bottom: 6),
        iconColor: const Color(0xFF1A2744),
        collapsedIconColor: Colors.grey.shade600,
        title: Row(
          children: [
            Expanded(
              child: Text(
                subZone.name,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A2744),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 30,
              height: 30,
              child: IconButton(
                icon: const Icon(Icons.edit, size: 14, color: Colors.blue),
                onPressed: () => _editWing(subZone, parentZone),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
            SizedBox(
              width: 30,
              height: 30,
              child: IconButton(
                icon: const Icon(Icons.delete, size: 14, color: Colors.red),
                onPressed: () => _deleteWing(subZone, parentZone),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${subZone.rooms.length} Rooms',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
        ),
        children: [
          ...subZone.rooms.map((room) => _buildRoomTile(room)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _addRoomToWing(subZone, parentZone),
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text(
                      'Add Room',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF2D4A7A),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextButton(
                    onPressed: () => _bulkAddRoomsToWing(subZone, parentZone),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFD4AF37),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Bulk Add',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextButton(
                    onPressed: () => _bulkAddRoomsFromCSV(subZone, parentZone),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF2E7D32),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'CSV',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomTile(Room room) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF2D4A7A).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.bed,
              color: Color(0xFF2D4A7A),
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        room.roomCode,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A2744),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (room.amount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '₹${room.amount.toStringAsFixed(0)}',
                          style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  'Vacancy: ${room.availableRooms}/${room.capacity} (${room.facility})',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              icon: const Icon(Icons.edit, size: 16, color: Colors.blue),
              onPressed: () => _editRoom(room),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              icon: const Icon(Icons.delete, size: 16, color: Colors.red),
              onPressed: () => _deleteRoom(room),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  void _addFloorAtRoot() async {
    final controller = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add New Floor', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D4A7A))),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Floor Name',
            hintText: 'e.g. 1st Floor, 2nd Floor',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: const Icon(Icons.stairs),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37)),
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (added == true && controller.text.isNotEmpty) {
      _showLoadingDialog();
      try {
        if (!mounted) return;
        final provider = context.read<HierarchicalHostelProvider>();
        final response = await provider.addFloor(widget.hostel.id, controller.text);
        if (mounted) _hideLoadingDialog();
        if (response['success'] == true) {
          await _refreshData();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Floor added successfully'), backgroundColor: Colors.green));
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${response['message'] ?? 'Unknown error'}'), backgroundColor: Colors.red));
        }
      } catch (e) {
        if (mounted) _hideLoadingDialog();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _addWingToFloor(Zone floor) async {
    final controller = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Add Wing to ${floor.name}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D4A7A))),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Wing Name',
            hintText: 'e.g. Wing A, Wing B',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: const Icon(Icons.business),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37)),
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (added == true && controller.text.isNotEmpty) {
      _showLoadingDialog();
      try {
        if (!mounted) return;
        final provider = context.read<HierarchicalHostelProvider>();
        final response = await provider.addWing(widget.hostel.id, floor.name, controller.text);
        if (mounted) _hideLoadingDialog();
        if (response['success'] == true) {
          await _refreshData();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wing added successfully'), backgroundColor: Colors.green));
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${response['message'] ?? 'Unknown error'}'), backgroundColor: Colors.red));
        }
      } catch (e) {
        if (mounted) _hideLoadingDialog();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _addRoomToWing(SubZone wing, Zone floor) async {
    final noController = TextEditingController();
    final capController = TextEditingController(text: '4');
    final amtController = TextEditingController(text: '5000');
    String selectedFacility = 'AC';
    
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Add Room to ${wing.name}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D4A7A))),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: noController,
                  decoration: InputDecoration(
                    labelText: 'Room Number',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.bed),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedFacility,
                  decoration: InputDecoration(
                    labelText: 'Facility',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.ac_unit),
                  ),
                  items: ['AC', 'NON AC'].map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                  onChanged: (v) => setDialogState(() => selectedFacility = v!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: capController,
                  decoration: InputDecoration(
                    labelText: 'Capacity',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.people),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amtController,
                  decoration: InputDecoration(
                    labelText: 'Amount (₹)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.currency_rupee),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D4A7A)),
              child: const Text('Create', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (added == true && noController.text.isNotEmpty) {
      _showLoadingDialog();
      try {
        if (!mounted) return;
        final provider = context.read<HierarchicalHostelProvider>();
        final response = await provider.addRoomWithFacility(
          widget.hostel.id, 
          floor.name, 
          floor.code,
          wing.name, 
          wing.code,
          noController.text, 
          int.parse(capController.text), 
          double.parse(amtController.text),
          selectedFacility
        );
        if (mounted) _hideLoadingDialog();
        if (response['success'] == true) {
          await _refreshData();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Room added successfully'), backgroundColor: Colors.green));
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${response['message'] ?? 'Unknown error'}'), backgroundColor: Colors.red));
        }
      } catch (e) {
        if (mounted) _hideLoadingDialog();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _bulkAddRoomsToWing(SubZone wing, Zone floor) async {
    final prefixController = TextEditingController();
    final startController = TextEditingController(text: '101');
    final endController = TextEditingController(text: '120');
    final capController = TextEditingController(text: '4');
    final amountController = TextEditingController(text: '5000');
    final cautionController = TextEditingController(text: '5000');
    String selectedFacility = 'AC';
    String selectedBath = 'Yes';
    List<String> preview = _buildBulkPreview('', 101, 120);

    void updatePreview(StateSetter setDialogState) {
      final start = int.tryParse(startController.text.trim());
      final end = int.tryParse(endController.text.trim());
      setDialogState(() {
        preview = _buildBulkPreview(prefixController.text.trim(), start, end);
      });
    }

    final added = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Bulk Add Rooms to ${wing.name}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D4A7A),
            ),
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: prefixController,
                          decoration: InputDecoration(
                            labelText: 'Prefix',
                            hintText: 'Optional, e.g. A',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.text_fields),
                          ),
                          onChanged: (_) => updatePreview(setDialogState),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: startController,
                          decoration: InputDecoration(
                            labelText: 'Start No',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.first_page),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => updatePreview(setDialogState),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: endController,
                          decoration: InputDecoration(
                            labelText: 'End No',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.last_page),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => updatePreview(setDialogState),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: capController,
                          decoration: InputDecoration(
                            labelText: 'Capacity',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.people),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: amountController,
                          decoration: InputDecoration(
                            labelText: 'Amount',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.currency_rupee),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: cautionController,
                          decoration: InputDecoration(
                            labelText: 'Caution',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.savings),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedFacility,
                          decoration: InputDecoration(
                            labelText: 'Facility',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.ac_unit),
                          ),
                          items: ['AC', 'NON AC']
                              .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => selectedFacility = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedBath,
                          decoration: InputDecoration(
                            labelText: 'Bath Attached',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.bathtub),
                          ),
                          items: ['Yes', 'No']
                              .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => selectedBath = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F3E8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD4AF37)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Preview (${preview.length} rooms)',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2D4A7A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          preview.isEmpty
                              ? 'Enter a valid start and end number.'
                              : preview.take(24).join(', ') +
                                  (preview.length > 24 ? '...' : ''),
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed:
                  preview.isEmpty ? null : () => Navigator.pop(context, true),
              icon: const Icon(Icons.playlist_add, color: Colors.white),
              label: Text(
                'Create ${preview.length} Rooms',
                style: const TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2D4A7A),
              ),
            ),
          ],
        ),
      ),
    );

    if (added != true) return;

    final start = int.tryParse(startController.text.trim());
    final end = int.tryParse(endController.text.trim());
    final capacity = int.tryParse(capController.text.trim());
    final amount = double.tryParse(amountController.text.trim());
    final caution = double.tryParse(cautionController.text.trim());

    if (start == null ||
        end == null ||
        start > end ||
        capacity == null ||
        capacity <= 0 ||
        amount == null ||
        caution == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter valid room range, capacity, and fees.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    _showLoadingDialog();
    try {
      final rooms = _generateBulkRoomPayloads(
        floor: floor,
        wing: wing,
        prefix: prefixController.text.trim(),
        start: start,
        end: end,
        capacity: capacity,
        amount: amount,
        caution: caution,
        facility: selectedFacility,
        bathAttached: selectedBath,
      );
      final response = await ApiService.adminBulkAddRooms(rooms);
      if (mounted) _hideLoadingDialog();

      if (response['success'] == true) {
        await _refreshData();
        final inserted = response['count'] ?? rooms.length;
        final skipped = response['skipped'] ?? 0;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Created $inserted rooms${skipped > 0 ? ', skipped $skipped duplicates' : ''}.',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${response['message'] ?? 'Unknown error'}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) _hideLoadingDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<String> _buildBulkPreview(String prefix, int? start, int? end) {
    if (start == null || end == null || start > end || end - start > 500) {
      return [];
    }
    return [
      for (var number = start; number <= end; number++) '$prefix$number',
    ];
  }

  List<Map<String, dynamic>> _generateBulkRoomPayloads({
    required Zone floor,
    required SubZone wing,
    required String prefix,
    required int start,
    required int end,
    required int capacity,
    required double amount,
    required double caution,
    required String facility,
    required String bathAttached,
  }) {
    final campus = widget.hostel.campus.isNotEmpty
        ? widget.hostel.campus
        : 'SIMATS';
    final buildingCode = widget.hostel.buildingCode.isNotEmpty
        ? widget.hostel.buildingCode
        : _compactCode(widget.hostel.name);
    final floorCode = floor.code.isNotEmpty ? floor.code : floor.name;
    final wingCode = wing.code.isNotEmpty ? wing.code : wing.name;

    return [
      for (var number = start; number <= end; number++)
        {
          'hostel_id': widget.hostel.id.toString(),
          'campus': campus,
          'campus_code': campus.length > 10 ? campus.substring(0, 10) : campus,
          'hostel_name': widget.hostel.name,
          'building_code': buildingCode,
          'hostel_type': widget.hostel.type.isNotEmpty
              ? widget.hostel.type
              : 'Girls',
          'room_type': '$capacity-sharing',
          'location_name': 'Main',
          'floor_code': floorCode,
          'floor': floor.name,
          'room_no': '$prefix$number',
          'wing_code': wingCode,
          'room_code': '$buildingCode-$floorCode-$wingCode-R$prefix$number',
          'facility': facility,
          'bath_attached': bathAttached,
          'amount': amount,
          'caution_dept': caution,
          'total_capacity': capacity,
          'available_rooms': capacity,
          'occupied_rooms': 0,
        },
    ];
  }

  String _compactCode(String value) {
    final code = value
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '')
        .trim();
    if (code.isEmpty) return 'HOSTEL';
    return code.length > 8 ? code.substring(0, 8) : code;
  }

  int _extractCapacity(String name) {
    if (name.contains('8 IN 1')) return 8;
    if (name.contains('6 IN 1')) return 6;
    if (name.contains('4 IN 1')) return 4;
    if (name.contains('2 IN 1')) return 2;
    return 0; // Default
  }

  void _editFloor(Zone zone) async {
    final controller = TextEditingController(text: zone.name);
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Floor Name', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D4A7A))),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: TextField(
            controller: controller, 
            decoration: InputDecoration(
              labelText: 'Floor Name',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.stairs),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37)),
            child: const Text('Update', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (updated == true) {
      if (!mounted) return;
      final provider = Provider.of<HierarchicalHostelProvider>(context, listen: false);
      final success = await provider.updateFloor(widget.hostel.id, zone.name, controller.text);
      if (!mounted) return;
      if (success) {
        setState(() { zone.name = controller.text; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Floor updated successfully')));
      }
    }
  }

  void _editWing(SubZone subZone, Zone parentZone) async {
    final controller = TextEditingController(text: subZone.name);
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Wing Name', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D4A7A))),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: TextField(
            controller: controller, 
            decoration: InputDecoration(
              labelText: 'Wing Name',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.business),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D4A7A)),
            child: const Text('Update', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (updated == true) {
      if (!mounted) return;
      final provider = Provider.of<HierarchicalHostelProvider>(context, listen: false);
      final success = await provider.updateWing(widget.hostel.id, parentZone.name, subZone.name, controller.text);
      if (!mounted) return;
      if (success) {
        setState(() { 
          subZone.name = controller.text; 
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wing updated successfully')));
      }
    }
  }

  void _deleteFloor(Zone zone) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Floor'),
        content: Text('Are you sure you want to delete the floor "${zone.name}" and all its rooms?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
 
    if (confirmed == true) {
      if (!mounted) return;
      _showLoadingDialog();
      final provider = Provider.of<HierarchicalHostelProvider>(context, listen: false);
      final success = await provider.deleteFloor(widget.hostel.id, zone.name);
      if (mounted) _hideLoadingDialog(); // Hide loading
      if (success) {
        await _refreshData();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Floor deleted successfully'), backgroundColor: Colors.green));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete floor: ${provider.error ?? "Unknown error"}'), backgroundColor: Colors.red));
      }
    }
  }
   void _deleteWing(SubZone subZone, Zone parentFloor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Wing'),
        content: Text('Are you sure you want to delete the wing "${subZone.name}" and all its rooms?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
 
    if (confirmed == true) {
      if (!mounted) return;
      _showLoadingDialog();
      final provider = Provider.of<HierarchicalHostelProvider>(context, listen: false);
      final success = await provider.deleteWing(widget.hostel.id, parentFloor.name, subZone.name);
      if (mounted) _hideLoadingDialog(); // Hide loading
      if (success) {
        await _refreshData();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wing deleted successfully'), backgroundColor: Colors.green));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete wing: ${provider.error ?? "Unknown error"}'), backgroundColor: Colors.red));
      }
    }
  }

  void _deleteRoom(Room room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Room'),
        content: Text('Are you sure you want to delete room "${room.roomNumber}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      _showLoadingDialog();
      final provider = Provider.of<HierarchicalHostelProvider>(context, listen: false);
      final success = await provider.deleteRoom(room.id);
      if (mounted) _hideLoadingDialog(); // Hide loading
      if (success) {
        await _refreshData();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Room deleted successfully'), backgroundColor: Colors.green));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete room: ${provider.error ?? "Unknown error"}'), backgroundColor: Colors.red));
      }
    }
  }

  void _editRoom(Room room) async {
    final noController = TextEditingController(text: room.roomCode.isNotEmpty ? room.roomCode : room.roomNumber);
    final capController = TextEditingController(text: room.capacity.toString());
    final amtController = TextEditingController(text: room.amount.toStringAsFixed(0));
    
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Room Details', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D4A7A))),
        content: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: noController, 
                  decoration: InputDecoration(
                    labelText: 'Room Number',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.bed),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: capController, 
                  decoration: InputDecoration(
                    labelText: 'Capacity',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.people),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amtController, 
                  decoration: InputDecoration(
                    labelText: 'Amount (₹)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.currency_rupee),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D4A7A)),
            child: const Text('Update', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (updated == true) {
      if (!mounted) return;
      final provider = Provider.of<HierarchicalHostelProvider>(context, listen: false);
      final success = await provider.updateRoom(
        room.id, 
        {
          'room_number': noController.text, 
          'capacity': int.parse(capController.text),
          'amount': double.parse(amtController.text),
        }
      );
      if (!mounted) return;
      if (success) {
        setState(() { 
          String input = noController.text;
          room.roomCode = input;
          if (input.contains('-R')) {
            room.roomNumber = input.split('-R').last;
          } else {
            room.roomNumber = input;
          }
          room.capacity = int.parse(capController.text);
          room.amount = double.parse(amtController.text);
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Room updated successfully')));
      }
    }
  }

  void _bulkAddRoomsFromCSV(SubZone wing, Zone floor) async {
    try {
      // Pick CSV file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null || result.files.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No file selected'), backgroundColor: Colors.red),
        );
        return;
      }

      final file = result.files.first;
      final fileBytes = file.bytes;

      if (fileBytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to read file'), backgroundColor: Colors.red),
        );
        return;
      }

      // Parse CSV
      final csvString = utf8.decode(fileBytes);
      final List<List<dynamic>> csvData = const CsvToListConverter().convert(csvString);

      if (csvData.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV file is empty'), backgroundColor: Colors.red),
        );
        return;
      }

      // Parse rooms from CSV
      final rooms = _parseRoomsFromCSV(csvData, wing, floor);

      if (rooms.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No valid rooms found in CSV. Check headers and data format.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Show preview and confirmation
      final confirmed = await _showCSVPreviewDialog(rooms);

      if (confirmed != true) return;

      // Upload
      if (!mounted) return;
      _showLoadingDialog();
      try {
        final response = await ApiService.adminBulkAddRooms(rooms);
        if (mounted) _hideLoadingDialog();

        if (response['success'] == true) {
          await _refreshData();
          final inserted = response['count'] ?? rooms.length;
          final skipped = response['skipped'] ?? 0;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Imported $inserted rooms${skipped > 0 ? ', skipped $skipped duplicates' : ''}.',
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed: ${response['message'] ?? 'Unknown error'}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (mounted) _hideLoadingDialog();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  List<Map<String, dynamic>> _parseRoomsFromCSV(
    List<List<dynamic>> csvData,
    SubZone wing,
    Zone floor,
  ) {
    if (csvData.length < 2) return [];

    // Parse header
    final header = csvData[0].map((h) => h.toString().toLowerCase().trim()).toList();

    // Find column indices (flexible, case-insensitive)
    int? roomNoIdx, capacityIdx, amountIdx, cautionIdx, facilityIdx, bathIdx;

    for (int i = 0; i < header.length; i++) {
      final col = header[i];
      if (col.contains('room') && (col.contains('no') || col.contains('number'))) {
        roomNoIdx = i;
      } else if (col.contains('capacity') || col.contains('persons')) {
        capacityIdx = i;
      } else if (col.contains('amount') || col.contains('price') || col.contains('rent')) {
        amountIdx = i;
      } else if (col.contains('caution') || col.contains('deposit')) {
        cautionIdx = i;
      } else if (col.contains('facility') || col.contains('ac')) {
        facilityIdx = i;
      } else if (col.contains('bath')) {
        bathIdx = i;
      }
    }

    // Default indices if not found
    roomNoIdx ??= 0;
    capacityIdx ??= 1;
    amountIdx ??= 2;
    cautionIdx ??= 3;
    facilityIdx ??= 4;
    bathIdx ??= 5;

    // Parse data rows
    final campus = widget.hostel.campus.isNotEmpty ? widget.hostel.campus : 'SIMATS';
    final buildingCode = widget.hostel.buildingCode.isNotEmpty
        ? widget.hostel.buildingCode
        : _compactCode(widget.hostel.name);
    final floorCode = floor.code.isNotEmpty ? floor.code : floor.name;
    final wingCode = wing.code.isNotEmpty ? wing.code : wing.name;

    final rooms = <Map<String, dynamic>>[];

    for (int i = 1; i < csvData.length; i++) {
      final row = csvData[i];
      if (row.isEmpty || (row.first?.toString().trim() ?? '').isEmpty) continue;

      try {
        final roomNo = row.length > roomNoIdx
            ? row[roomNoIdx]?.toString().trim() ?? ''
            : '';
        final facility = row.length > facilityIdx
            ? row[facilityIdx]?.toString().trim() ?? 'AC'
            : 'AC';
        final capacity = row.length > capacityIdx
            ? (int.tryParse(row[capacityIdx]?.toString().trim() ?? '') ?? _extractCapacity(facility))
            : _extractCapacity(facility);
        final amount = row.length > amountIdx
            ? double.parse(row[amountIdx]?.toString().trim() ?? '0')
            : 0.0;
        final caution = row.length > cautionIdx
            ? double.parse(row[cautionIdx]?.toString().trim() ?? '0')
            : 0.0;
        final bathAttached = row.length > bathIdx
            ? row[bathIdx]?.toString().trim() ?? 'Yes'
            : 'Yes';

        if (roomNo.isEmpty || capacity <= 0) continue;

        rooms.add({
          'hostel_id': widget.hostel.id.toString(),
          'campus': campus,
          'campus_code': campus.length > 10 ? campus.substring(0, 10) : campus,
          'hostel_name': widget.hostel.name,
          'building_code': buildingCode,
          'hostel_type': widget.hostel.type.isNotEmpty ? widget.hostel.type : 'Girls',
          'room_type': '$capacity-sharing',
          'location_name': 'Main',
          'floor_code': floorCode,
          'floor': floor.name,
          'room_no': roomNo,
          'wing_code': wingCode,
          'room_code': '$buildingCode-$floorCode-$wingCode-R$roomNo',
          'facility': facility,
          'bath_attached': bathAttached,
          'amount': amount,
          'caution_dept': caution,
          'total_capacity': capacity,
          'available_rooms': capacity,
          'occupied_rooms': 0,
        });
      } catch (e) {
        debugPrint('Error parsing row $i: $e');
        continue;
      }
    }

    return rooms;
  }

  Future<bool?> _showCSVPreviewDialog(List<Map<String, dynamic>> rooms) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'CSV Import Preview',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D4A7A),
          ),
        ),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Found ${rooms.length} rooms to import:',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F3E8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD4AF37)),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Room No')),
                        DataColumn(label: Text('Capacity')),
                        DataColumn(label: Text('Amount')),
                        DataColumn(label: Text('Facility')),
                      ],
                      rows: rooms
                          .take(10)
                          .map(
                            (room) => DataRow(
                              cells: [
                                DataCell(Text(room['room_no']?.toString() ?? '')),
                                DataCell(Text(room['total_capacity']?.toString() ?? '')),
                                DataCell(Text(room['amount']?.toString() ?? '')),
                                DataCell(Text(room['facility']?.toString() ?? '')),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                if (rooms.length > 10)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      '... and ${rooms.length - 10} more',
                      style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.upload, color: Colors.white),
            label: Text(
              'Import ${rooms.length} Rooms',
              style: const TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FloorCardWidget extends StatefulWidget {
  final Zone zone;
  final int index;
  final IconData icon;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddWing;
  final Widget Function(SubZone subZone, Zone parentZone) buildWingTile;

  const _FloorCardWidget({
    required this.zone,
    required this.index,
    required this.icon,
    required this.onEdit,
    required this.onDelete,
    required this.onAddWing,
    required this.buildWingTile,
  });

  @override
  State<_FloorCardWidget> createState() => _FloorCardWidgetState();
}

class _FloorCardWidgetState extends State<_FloorCardWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.12), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.8),
            blurRadius: 1,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // ── 100% Full Width Gradient Header Banner ──────────────────
            InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A2744), Color(0xFF2D4A7A)],
                  ),
                ),
                child: Row(
                  children: [
                    // Full-Color 3D Glossy Gold Icon Badge
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFF7EAAD), Color(0xFFD4AF37), Color(0xFFA8801A)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFF6D6), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(widget.icon, color: const Color(0xFF1A2744), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.zone.name,
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.zone.subZones.length} Wings',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Stylish Edit Button Badge
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: widget.onEdit,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withOpacity(0.35)),
                          ),
                          child: Text(
                            'Edit',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Delete Action Button
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: widget.onDelete,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                          ),
                          child: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFFF8A80)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Expand/Collapse Chevron Indicator
                    AnimatedRotation(
                      turns: _isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4AF37).withOpacity(0.2),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.5)),
                        ),
                        child: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Color(0xFFD4AF37),
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ── Expanded Content ───────────────────────────────────────
            if (_isExpanded) ...[
              ...widget.zone.subZones.map((subZone) => widget.buildWingTile(subZone, widget.zone)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: TextButton.icon(
                  onPressed: widget.onAddWing,
                  icon: const Icon(Icons.add_business, size: 18),
                  label: Text('Add New Wing', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFD4AF37),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    backgroundColor: const Color(0xFF1A2744).withOpacity(0.05),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
