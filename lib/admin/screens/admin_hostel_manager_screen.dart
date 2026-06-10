import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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

  bool _isPasswordVerified = false;
  final TextEditingController _passwordController = TextEditingController();
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    // Do not auto-load hostels until password is verified
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
                      fontFamily: 'Georgia',
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
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A2744)))
              : _error != null
                  ? _buildErrorState()
                  : _buildHostelList(),
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
                return _buildHostelCard(_hostels[index]);
              }
              return _buildAddNewHostelButton();
            },
          ),
        ),
      ],
    );
  }

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
                fontFamily: 'Georgia',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHostelCard(HierarchicalHostel hostel) {
    final type = 'Mixed';
    final typeColor = type.toLowerCase() == 'girls' ? const Color(0xFFE91E63) : const Color(0xFF2196F3);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.apartment, color: typeColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(hostel.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A2744))),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text('ID: ${hostel.id}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  onPressed: () async {
                    if (_isNavigating) return;
                    _isNavigating = true;
                    final provider = Provider.of<HierarchicalHostelProvider>(context, listen: false);
                    await provider.loadHostelHierarchy(hostel);
                    if (!mounted) return;
                    if (widget.onHostelSelected != null) {
                      widget.onHostelSelected!(hostel);
                      _isNavigating = false;
                    } else {
                      Navigator.of(context).pushNamed(
                        '/hostel_detail',
                        arguments: hostel,
                      ).then((_) {
                        _isNavigating = false;
                      });
                    }
                  },
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildCompactAction(Icons.edit, 'Edit', const Color(0xFF2D4A7A), () async {
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
                }),
                _buildCompactAction(Icons.delete, 'Delete', Colors.red, () async {
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
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
