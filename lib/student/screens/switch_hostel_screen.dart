import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api_service.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';

class Hostel {
  final int id;
  final String campus;
  final String hostelName;
  final String hostelType;
  final String buildingCode;

  Hostel({
    required this.id,
    required this.campus,
    required this.hostelName,
    required this.hostelType,
    required this.buildingCode,
  });

  factory Hostel.fromJson(Map<String, dynamic> json) {
    return Hostel(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      campus: json['campus'] ?? '',
      hostelName: json['hostel_name'] ?? '',
      hostelType: json['hostel_type'] ?? '',
      buildingCode: json['building_code'] ?? '',
    );
  }
}

class SwitchHostelScreen extends StatefulWidget {
  const SwitchHostelScreen({super.key});

  @override
  State<SwitchHostelScreen> createState() => _SwitchHostelScreenState();
}

class _SwitchHostelScreenState extends State<SwitchHostelScreen> {
  List<Hostel> _allHostels = [];
  List<Hostel> _cityCampusHostels = [];
  List<Hostel> _thandalamCampusHostels = [];
  bool _isLoading = true;
  String? _error;
  int? _selectedHostelId;

  @override
  void initState() {
    super.initState();
    _loadHostels();
  }

  Future<void> _loadHostels() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final response = await ApiService.getHostels();

      if (response.isNotEmpty) {
        final List<dynamic> allHostelsJson = response;

        setState(() {
          _allHostels = allHostelsJson.map((json) => Hostel.fromJson(json)).toList();
          _cityCampusHostels = [];
          _thandalamCampusHostels = [];
          _isLoading = false;
        });
      } else {
        throw Exception('No hostels found');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _selectHostel(Hostel hostel) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selectedHostelId = hostel.id;
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFF9F6F0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Switch to ${hostel.hostelName}?',
          style: const TextStyle(
            fontFamily: 'Georgia',
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A2744),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Campus', hostel.campus),
            const SizedBox(height: 8),
            _buildInfoRow('Type', hostel.hostelType),
            const SizedBox(height: 8),
            _buildInfoRow('Building', hostel.buildingCode),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmHostelSwitch(hostel);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              'Confirm',
              style: TextStyle(color: Color(0xFF1A2744), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmHostelSwitch(Hostel hostel) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Switched to ${hostel.hostelName} successfully!'),
        backgroundColor: const Color(0xFF43A047),
        duration: const Duration(seconds: 2),
      ),
    );

    Future.delayed(const Duration(seconds: 1), () {
      Navigator.pop(context);
    });
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A2744),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: SkeuomorphicNavBar(
        title: 'Switch Hostel',
        onBack: () => Navigator.pop(context),
        rightAction: IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
          onPressed: _loadHostels,
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        ),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFFD4AF37)),
                  SizedBox(height: 16),
                  Text('Loading hostels...'),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadHostels,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4AF37).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.apartment, color: Color(0xFFD4AF37), size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Select Your Hostel',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1A2744),
                                    ),
                                  ),
                                  Text(
                                    '${_allHostels.length} hostels available',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      if (_cityCampusHostels.isNotEmpty) ...[
                        _buildCampusHeader('City Campus', Icons.location_city),
                        const SizedBox(height: 12),
                        ..._cityCampusHostels.map((hostel) => _buildHostelCard(hostel)),
                        const SizedBox(height: 24),
                      ],

                      if (_thandalamCampusHostels.isNotEmpty) ...[
                        _buildCampusHeader('Thandalam Campus', Icons.school),
                        const SizedBox(height: 12),
                        ..._thandalamCampusHostels.map((hostel) => _buildHostelCard(hostel)),
                      ],
                      
                      if (_cityCampusHostels.isEmpty && _thandalamCampusHostels.isEmpty)
                        ..._allHostels.map((hostel) => _buildHostelCard(hostel)),
                    ],
                  ),
                ),
    );
  }

  Widget _buildCampusHeader(String campusName, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D4A7A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(
            campusName,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostelCard(Hostel hostel) {
    final isSelected = _selectedHostelId == hostel.id;
    final isGirls = hostel.hostelType.toLowerCase() == 'girls';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _selectHostel(hostel),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFD4AF37).withOpacity(0.1) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? const Color(0xFFD4AF37) : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isGirls
                      ? const Color(0xFFE91E63).withOpacity(0.1)
                      : const Color(0xFF2196F3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isGirls ? Icons.female : Icons.male,
                  color: isGirls ? const Color(0xFFE91E63) : const Color(0xFF2196F3),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hostel.hostelName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2744),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isGirls
                                ? const Color(0xFFE91E63).withOpacity(0.1)
                                : const Color(0xFF2196F3).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            hostel.hostelType,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isGirls ? const Color(0xFFE91E63) : const Color(0xFF2196F3),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.business, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          hostel.buildingCode,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFD4AF37) : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? const Color(0xFFD4AF37) : Colors.grey.shade400,
                    width: 2,
                  ),
                  shape: BoxShape.circle,
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
