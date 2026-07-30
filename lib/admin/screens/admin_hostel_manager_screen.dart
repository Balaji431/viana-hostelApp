import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/providers/hierarchical_hostel_provider.dart';
import '../../core/styles.dart';

import '../dialogs/add_hostel_dialog.dart';
import 'hostel_detail_screen.dart';
import 'package:vianasoft_stay/core/models/hierarchical_hostel_model.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';

class AdminHostelManagerScreen extends StatefulWidget {
  final void Function(HierarchicalHostel hostel)? onHostelSelected;
  final bool showAppBar;

  const AdminHostelManagerScreen({
    super.key, 
    this.onHostelSelected,
    this.showAppBar = true,
  });

  @override
  State<AdminHostelManagerScreen> createState() => _AdminHostelManagerScreenState();
}

class _AdminHostelManagerScreenState extends State<AdminHostelManagerScreen> {
  List<HierarchicalHostel> _hostels = [];
  bool _isLoading = true;
  String? _error;
  bool _isFetching = false;
  bool _isNavigating = false;
  bool _isDeleting = false;

  bool _isPasswordVerified = true;
  final TextEditingController _passwordController = TextEditingController();
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    // Auto-load hostels as we bypassed password verification
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHostels();
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadHostels() async {
    if (_isFetching) return;
    
    _isFetching = true;
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final provider = Provider.of<HierarchicalHostelProvider>(context, listen: false);
      await provider.loadHostels();
      
      final hostelsData = provider.hostels;
      
      if (kDebugMode) {
        debugPrint('Hostels loaded: ${hostelsData.length}');
      }

      if (!mounted) return;
      setState(() {
        _hostels = hostelsData;
        _isLoading = false;
      });

    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to load hostels: $e');
      }
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    } finally {
      _isFetching = false;
    }
  }

  Widget _buildPasswordGate() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.showAppBar 
          ? SkeuomorphicNavBar(
              title: 'Hostel Manager',
              onBack: () => Navigator.of(context).pop(),
            )
          : null,
      body: LinenGridBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A4A8C).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      color: Color(0xFF2A4A8C),
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Admin Verification',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A2744),
                      fontFamily: 'Lato',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please enter the admin password to access hostel management.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Enter Password',
                      errorText: _passwordError,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                    ),
                    onSubmitted: (_) => _verifyPassword(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _verifyPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2A4A8C),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Verify',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _verifyPassword() {
    if (_passwordController.text.trim() == 'ADMIN@VIANA') {
      setState(() {
        _isPasswordVerified = true;
        _passwordError = null;
      });
      _loadHostels();
    } else {
      setState(() {
        _passwordError = 'Incorrect password';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isPasswordVerified) {
      return _buildPasswordGate();
    }
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: widget.showAppBar 
              ? SkeuomorphicNavBar(
                  title: 'Hostel Manager',
                  onBack: () => Navigator.of(context).pop(),
                  rightAction: IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                    onPressed: _loadHostels,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                )
              : null,
          body: LinenGridBackground(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A2744)))
                : _error != null
                    ? _buildErrorState()
                    : _buildHostelList(),
          ),
        ),
        if (_isDeleting)
          Container(
            color: Colors.black.withValues(alpha: 0.5),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF2D4A7A)),
                    SizedBox(height: 16),
                    Text(
                      'Deleting hostel...',
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 16, 
                        color: Colors.black, 
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          Text('Error: $_error'),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loadHostels, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildHostelList() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFD4AF37).withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.apartment, color: Color(0xFFD4AF37), size: 28),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Hostels', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  Text('${_hostels.length}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A2744))),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _hostels.length + 1,
            itemBuilder: (context, index) {
              if (index < _hostels.length) {
                return _buildHostelCard(_hostels[index], index);
              }
              return _buildAddNewHostelButton();
            },
          ),
        ),
      ],
    );
  }

  static const List<IconData> _hostelIcons = [
    Icons.apartment,
    Icons.villa,
    Icons.home_work,
    Icons.domain,
    Icons.location_city,
    Icons.business,
    Icons.maps_home_work,
  ];

  Widget _buildAddNewHostelButton() {
    return GestureDetector(
      onTap: () async {
        final result = await showDialog<bool>(
          context: context,
          builder: (context) => const AddHostelDialog(),
        );
        if (result == true) _loadHostels();
      },
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 20),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF3FB), 
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF2A4A8C).withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFF2A4A8C),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            const Text(
              'Add New Hostel',
              style: TextStyle(
                color: Color(0xFF2A4A8C),
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'Lato',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHostelCard(HierarchicalHostel hostel, int index) {
    final icon = _hostelIcons[index % _hostelIcons.length];
    final displayName = hostel.name.toLowerCase().contains('hostel')
        ? hostel.name
        : '${hostel.name} Hostel';
    final campus = hostel.campus.isNotEmpty ? hostel.campus : 'Main Campus';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.08), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 5),
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
            // ── Navy & Gold Gradient Header Banner ──────────────────
            GestureDetector(
              onTap: () => _navigateToDetail(hostel),
              child: Container(
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
                    // Cycling Icon Avatar
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
                            'Campus: $campus • ID: ${hostel.id}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.78),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Navigation Arrow
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
            ),
            // ── Footer with Type Badge and Actions ──────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.4)),
                    ),
                    child: Text(
                      'Type: ${hostel.type.isNotEmpty ? hostel.type : 'Mixed'}',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1A2744),
                      ),
                    ),
                  ),
                  const Spacer(),
                  _buildCompactAction(Icons.edit_outlined, 'Edit', const Color(0xFF2D4A7A), () => _editHostel(hostel)),
                  const SizedBox(width: 16),
                  _buildCompactAction(Icons.delete_outline, 'Delete', Colors.red, () => _deleteHostel(hostel)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToDetail(HierarchicalHostel hostel) async {
    if (_isNavigating) return;
    _isNavigating = true;
    final provider = Provider.of<HierarchicalHostelProvider>(context, listen: false);
    await provider.loadHostelHierarchy(hostel);
    if (!mounted) return;
    if (widget.onHostelSelected != null) {
      widget.onHostelSelected!(hostel);
      _isNavigating = false;
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: '/hostel_detail'),
          builder: (context) => HostelDetailScreen(hostel: hostel),
        ),
      ).then((_) {
        _isNavigating = false;
      });
    }
  }

  Future<void> _editHostel(HierarchicalHostel hostel) async {
    final nameController = TextEditingController(text: hostel.name);
    final buildingController = TextEditingController(text: hostel.buildingCode);
    String selectedType = hostel.type;

    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Edit Hostel', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D4A7A))),
            content: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      onChanged: (value) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Hostel Name',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.apartment),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: buildingController,
                      decoration: InputDecoration(
                        labelText: 'Building Code',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.code),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedType,
                      items: ['Girls', 'Boys'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                      onChanged: (val) => setDialogState(() => selectedType = val!),
                      decoration: InputDecoration(
                        labelText: 'Type',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.people),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: nameController.text.trim().isEmpty ? null : () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D4A7A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('Update', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );

    if (updated == true) {
      if (!mounted) return;
      final provider = Provider.of<HierarchicalHostelProvider>(context, listen: false);
      final success = await provider.updateHostel(
        hostel.id, 
        nameController.text, 
        selectedType, 
        buildingController.text
      );
      
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hostel updated successfully')),
        );
        _loadHostels();
      }
    }
  }

  Future<void> _deleteHostel(HierarchicalHostel hostel) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Hostel'),
        content: const Text('Are you sure you want to delete this hostel? All associated rooms will also be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete')
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      setState(() {
        _isDeleting = true;
      });

      final provider = Provider.of<HierarchicalHostelProvider>(context, listen: false);
      final success = await provider.deleteHostel(hostel.id);
      
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
      
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hostel deleted successfully'), backgroundColor: Colors.green),
          );
        }
        _loadHostels();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(provider.error ?? 'Failed to delete hostel'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildCompactAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
