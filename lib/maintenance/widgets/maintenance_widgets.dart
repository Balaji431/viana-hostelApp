import 'package:flutter/material.dart';
import '../../core/styles.dart';

// Re-export common widgets from warden widgets for maintenance use
export '../../warden/widgets/warden_widgets.dart';

// Maintenance-specific widgets can be added here
class MaintenanceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  
  const MaintenanceCard({
    super.key, 
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: SkeuomorphicStyles.skeuomorphicCard,
      child: child,
    );
  }
}

class MaintenanceHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  
  const MaintenanceHeader({
    super.key,
    required this.title,
    required this.icon,
  });
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFD4AF37), size: 18),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
