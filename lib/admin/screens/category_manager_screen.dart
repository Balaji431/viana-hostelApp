import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/category_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../core/styles.dart';

class CategoryManagerScreen extends StatefulWidget {
  final bool showAppBar;
  const CategoryManagerScreen({super.key, this.showAppBar = true});

  @override
  State<CategoryManagerScreen> createState() => _CategoryManagerScreenState();
}

class _CategoryManagerScreenState extends State<CategoryManagerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CategoryProvider>().fetchCategories();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CategoryProvider>();

    Widget content = LinenGridBackground(
      child: provider.isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A2744)))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              children: [
                ...provider.categories.map((cat) => _buildEnhancedCategoryCard(cat, provider)),
                const SizedBox(height: 16),
                _buildAddCategoryButton(),
                const SizedBox(height: 80),
              ],
            ),
    );

    if (!widget.showAppBar) return content;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: 'Category Management',
        onBack: () => Navigator.of(context).pop(),
        rightAction: IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
          onPressed: () => provider.fetchCategories(),
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        ),
      ),
      body: content,
    );
  }

  Widget _buildAddCategoryButton() {
    return GestureDetector(
      onTap: () => _showEditCategoryDialog(null),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEE),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFB08900).withValues(alpha: 0.55),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFE8C84A), Color(0xFFB08900)],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            const Text(
              'Add New Category',
              style: TextStyle(
                color: Color(0xFFB08900),
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

  Widget _buildEnhancedCategoryCard(Map<String, dynamic> cat, CategoryProvider provider) {
    final Color accentColor = provider.getColor(cat['color_hex'] ?? cat['color']);
    final List<dynamic> codes = cat['codes'] ?? [];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 15, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(provider.getIconData(cat['icon_name'] ?? cat['icon'] ?? ''), color: accentColor, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cat['name'] ?? 'Unnamed',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1A2744)),
                          ),
                          Text(
                            '${codes.length} request types',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          if ((cat['is_staff_role'] ?? 1) == 1)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                              child: Text('STAFF ROLE', style: TextStyle(color: Colors.blue.shade700, fontSize: 9, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                    ),
                    _buildSubActionBtn(
                      icon: Icons.edit_outlined,
                      color: Colors.grey.shade50,
                      iconColor: Colors.grey.shade700,
                      onTap: () => _showEditCategoryDialog(cat),
                    ),
                    const SizedBox(width: 8),
                    _buildSubActionBtn(
                      icon: Icons.delete_outline,
                      color: const Color(0xFFFFEBEE),
                      iconColor: Colors.redAccent,
                      onTap: () => _confirmDelete(cat),
                    ),
                  ],
                ),
                if (codes.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: codes.map((code) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.label_outline, color: accentColor, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            code is Map ? (code['code_name'] ?? '') : code.toString(),
                            style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    )).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubActionBtn({required IconData icon, required Color color, required Color iconColor, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: iconColor, size: 20),
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> cat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category?'),
        content: Text('Are you sure you want to remove "${cat['name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      context.read<CategoryProvider>().deleteCategory(cat['id'].toString());
    }
  }

  void _showEditCategoryDialog(Map<String, dynamic>? category) {
    final provider = context.read<CategoryProvider>();
    
    // If editing an existing category, fetch the latest data from the provider
    Map<String, dynamic>? categoryData = category;
    if (category != null && category['id'] != null) {
      try {
        final latestCat = provider.categories.firstWhere(
          (c) => c['id'] == category['id'],
          orElse: () => category,
        );
        categoryData = latestCat;
      } catch (e) {
        categoryData = category;
      }
    }
    
    final nameController = TextEditingController(text: categoryData?['name'] ?? '');
    bool isStaffRole = (categoryData?['is_staff_role'] ?? 1) == 1;
    final newCodeController = TextEditingController();
    String? errorMessage;

    final List<Map<String, dynamic>> availableIcons = [
      {'name': 'group', 'icon': Icons.group},
      {'name': 'shield', 'icon': Icons.shield},
      {'name': 'build', 'icon': Icons.build},
      {'name': 'wifi', 'icon': Icons.wifi},
      {'name': 'restaurant', 'icon': Icons.restaurant},
      {'name': 'local_laundry_service', 'icon': Icons.local_laundry_service},
      {'name': 'bolt', 'icon': Icons.bolt},
      {'name': 'water_drop', 'icon': Icons.water_drop},
      {'name': 'phone', 'icon': Icons.phone},
      {'name': 'favorite', 'icon': Icons.favorite},
      {'name': 'local_shipping', 'icon': Icons.local_shipping},
      {'name': 'school', 'icon': Icons.school},
    ];

    String rawIcon = 'group';
    try {
      rawIcon = categoryData?['icon']?.toString() ?? categoryData?['icon_name']?.toString() ?? 'group';
    } catch (e) {
      rawIcon = 'group';
    }
    String selectedIcon = rawIcon.toLowerCase();

    // Handle different icon formats
    if (selectedIcon.contains('.')) {
      selectedIcon = selectedIcon.split('.').last;
    }
    if (selectedIcon.contains('group')) selectedIcon = 'group';
    else if (selectedIcon.contains('security') || selectedIcon.contains('shield')) selectedIcon = 'shield';
    else if (selectedIcon.contains('maintenance') || selectedIcon.contains('build') || selectedIcon.contains('0e148')) selectedIcon = 'build';
    else if (!availableIcons.any((i) => i['name'] == selectedIcon)) {
      // Fallback to group if icon not found in available list
      selectedIcon = 'group';
    }

    String rawColor = '#4CAF50';
    try {
      rawColor = categoryData?['color']?.toString() ?? categoryData?['color_hex']?.toString() ?? '#4CAF50';
    } catch (e) {
      rawColor = '#4CAF50';
    }
    String selectedColor = rawColor;

    // Handle different color formats
    if (selectedColor.startsWith('0x') || selectedColor.startsWith('0X')) {
      selectedColor = selectedColor.substring(2);
    }
    if (!selectedColor.startsWith('#')) {
      selectedColor = '#$selectedColor';
    }
    // Ensure it's a valid hex color
    if (selectedColor.length == 7 && selectedColor.startsWith('#')) {
      // Valid format like #4CAF50
    } else {
      // Fallback to default green if format is invalid
      selectedColor = '#4CAF50';
    }

    List<String> codes = [];
    try {
      if (categoryData != null && categoryData['codes'] != null) {
        codes = (categoryData['codes'] as List).map((e) => e is Map ? (e['code_name']?.toString() ?? e.toString()) : e.toString()).toList();
      }
    } catch (e) {
      codes = [];
    }

    final List<Map<String, dynamic>> availableColors = [
      {'name': 'Green', 'hex': '#4CAF50'},
      {'name': 'Red', 'hex': '#F44336'},
      {'name': 'Amber', 'hex': '#FFC107'},
      {'name': 'Blue', 'hex': '#2196F3'},
      {'name': 'Purple', 'hex': '#9C27B0'},
      {'name': 'Teal', 'hex': '#009688'},
      {'name': 'Pink', 'hex': '#E91E63'},
      {'name': 'Brown', 'hex': '#795548'},
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          try {
            final currentAccentColor = provider.getColor(selectedColor);
            
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: 550,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1A2744),
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          category == null ? 'New Category' : 'Edit Category',
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                  ),
                  
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Category Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: nameController,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              hintText: 'e.g. Warden',
                              errorText: errorMessage,
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                          const Text('Icon', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                          const SizedBox(height: 12),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, crossAxisSpacing: 8, mainAxisSpacing: 8),
                            itemCount: availableIcons.length,
                            itemBuilder: (context, idx) {
                              final item = availableIcons[idx];
                              bool isSelected = selectedIcon == item['name'];
                              return InkWell(
                                onTap: () => setDialogState(() => selectedIcon = item['name']),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected ? currentAccentColor : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: isSelected ? currentAccentColor : Colors.grey.shade200),
                                  ),
                                  child: Icon(
                                    item['icon'] as IconData?,
                                    color: isSelected ? Colors.white : Colors.grey.shade600,
                                    size: 20,
                                  ),
                                ),
                              );
                            },
                          ),
                          
                          const SizedBox(height: 24),
                          const Text('Color Theme', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: availableColors.map((c) {
                              bool isSelected = selectedColor == c['hex'];
                              return InkWell(
                                onTap: () => setDialogState(() => selectedColor = c['hex']),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: provider.getColor(c['hex']).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: provider.getColor(c['hex']).withValues(alpha: 1.0), width: isSelected ? 2 : 1),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(width: 12, height: 12, decoration: BoxDecoration(color: provider.getColor(c['hex']), shape: BoxShape.circle)),
                                      const SizedBox(width: 8),
                                      Text(c['name'], style: TextStyle(color: provider.getColor(c['hex']), fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          
                          const SizedBox(height: 32),
                          SwitchListTile(
                            title: const Text('Available as Staff Role', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            subtitle: const Text('Enable this to allow registering staff members for this role.', style: TextStyle(fontSize: 12)),
                            value: isStaffRole,
                            activeThumbColor: currentAccentColor,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (val) => setDialogState(() => isStaffRole = val),
                          ),
                          
                          const SizedBox(height: 32),
                          const Text('Preview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: currentAccentColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                                  child: Icon(
                                    availableIcons.firstWhere(
                                      (i) => i['name'] == selectedIcon,
                                      orElse: () => availableIcons[0],
                                    )['icon'],
                                    color: currentAccentColor,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(nameController.text.isEmpty ? 'Category Name' : nameController.text, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    Text('${codes.length} request types', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 32),
                          const Text('Request Types', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                          const SizedBox(height: 12),
                          ...codes.asMap().entries.map((entry) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
                            child: Row(
                              children: [
                                const Icon(Icons.label_outline, size: 14, color: Colors.grey),
                                const SizedBox(width: 12),
                                Expanded(child: Text(entry.value, style: const TextStyle(fontSize: 14))),
                                IconButton(icon: const Icon(Icons.close, size: 16, color: Colors.redAccent), onPressed: () => setDialogState(() => codes.removeAt(entry.key))),
                              ],
                            ),
                          )),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: newCodeController,
                                  decoration: InputDecoration(
                                    hintText: 'New request type...',
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: const Icon(Icons.add_circle, color: Color(0xFF1A2744), size: 32),
                                onPressed: () {
                                  if (newCodeController.text.isNotEmpty) {
                                    setDialogState(() {
                                      codes.add(newCodeController.text);
                                      newCodeController.clear();
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              if (nameController.text.isNotEmpty) {
                                setDialogState(() => errorMessage = null);
                                final data = {
                                  'id': categoryData?['id'],
                                  'name': nameController.text,
                                  'icon_name': selectedIcon,
                                  'color_hex': selectedColor,
                                  'is_staff_role': isStaffRole ? 1 : 0,
                                  'codes': codes,
                                };
                                final nav = Navigator.of(context);
                                final result = await provider.saveCategory(data);
                                if (!mounted) return;
                                if (result['success'] == true) {
                                  await provider.fetchCategories();
                                  if (!mounted) return;
                                  nav.pop();
                                } else {
                                  if (!mounted) return;
                                  setDialogState(() => errorMessage = result['message']);
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A2744),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
          } catch (e) {
            // Fallback dialog in case of any rendering errors
            return Dialog(
              backgroundColor: Colors.white,
              child: Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Error loading category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Text('An error occurred: $e'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            );
          }
        },
      ),
    );
  }
}
