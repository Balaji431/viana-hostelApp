import 'package:flutter/material.dart';

// Re-export common modals from warden modals for maintenance use
export '../../warden/widgets/warden_modals.dart';

// Maintenance-specific modals can be added here
class MaintenanceRequestModal extends StatelessWidget {
  final Function(String title, String description) onSubmit;
  
  const MaintenanceRequestModal({
    super.key,
    required this.onSubmit,
  });
  
  @override
  Widget build(BuildContext context) {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    
    return AlertDialog(
      title: const Text('New Maintenance Request'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: titleController,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'Enter request title',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: descController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'Enter request details',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            onSubmit(titleController.text, descController.text);
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A2744),
          ),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
