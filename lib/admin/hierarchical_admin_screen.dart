import 'package:flutter/material.dart';
import '../shared/widgets/skeuomorphic_navbar.dart';

class HierarchicalAdminScreen extends StatelessWidget {
  const HierarchicalAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SkeuomorphicNavBar(
        title: 'Hierarchical Admin',
        onBack: () => Navigator.pop(context),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.admin_panel_settings, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Hierarchical Admin Screen',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'This screen is temporarily disabled during UI fixes',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
