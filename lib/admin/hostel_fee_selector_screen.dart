import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/providers/hierarchical_hostel_provider.dart';
import 'fee_manager_screen.dart';
import '../shared/widgets/skeuomorphic_navbar.dart';
import '../core/styles.dart';

class HostelFeeSelectorScreen extends StatefulWidget {
  final bool isEmbedded;
  const HostelFeeSelectorScreen({super.key, this.isEmbedded = false});

  @override
  State<HostelFeeSelectorScreen> createState() => _HostelFeeSelectorScreenState();
}

class _HostelFeeSelectorScreenState extends State<HostelFeeSelectorScreen> {
  List<dynamic> _hostels = [];
  bool _isLoading = true;

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
      setState(() => _hostels = provider.hostels.map((h) => {
        'id': h.id,
        'name': h.name,
        'campus': h.campus,
      }).toList());
    } catch (e) {
      debugPrint("Load hostels error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _hostels.isEmpty
            ? const Center(child: Text('No hostels found'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                shrinkWrap: widget.isEmbedded,
                physics: widget.isEmbedded ? const NeverScrollableScrollPhysics() : null,
                itemCount: _hostels.length,
                itemBuilder: (context, index) {
                  final hostel = _hostels[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.apartment, color: Color(0xFF1A2744), size: 28),
                      ),
                      title: Text(
                        hostel['name'] ?? 'Unknown Hostel',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1A2744)),
                      ),
                      subtitle: Text(
                        'ID: ${hostel['id']} | Campus: ${hostel['campus'] ?? 'N/A'}',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                      trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
                      onTap: () {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => FeeManagerScreen(
                              hostelId: int.parse(hostel['id'].toString()),
                              hostelName: hostel['name'],
                            ),
                            transitionDuration: Duration.zero,
                            reverseTransitionDuration: Duration.zero,
                          ),
                        );
                      },
                    ),
                  );
                },
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
