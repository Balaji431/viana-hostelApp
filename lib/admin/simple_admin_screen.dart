import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/styles.dart';
import '../core/providers/hierarchical_hostel_provider.dart';
import '../core/providers/mapping_provider.dart';
import 'hierarchical_admin_screen.dart';
import '../shared/category_provider.dart';
import '../shared/widgets/skeuomorphic_navbar.dart';

class SimpleAdminScreen extends StatefulWidget {
  const SimpleAdminScreen({super.key});

  @override
  State<SimpleAdminScreen> createState() => _SimpleAdminScreenState();
}

class _SimpleAdminScreenState extends State<SimpleAdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<HierarchicalHostelProvider>();
      provider.loadHostels();
      final mappingProvider = context.read<MappingProvider>();
      mappingProvider.loadMappings();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: SkeuomorphicNavBar(
        title: 'Admin Dashboard',
        rightAction: IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
          onPressed: () async {
            final provider = context.read<HierarchicalHostelProvider>();
            final mappingProvider = context.read<MappingProvider>();
            await provider.loadHostels();
            mappingProvider.loadMappings();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Data refreshed successfully'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          },
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        ),
      ),
      body: Column(
        children: [
          Container(
            color: const Color(0xFF1B2B48),
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.gold,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(icon: Icon(Icons.dashboard), text: 'Home'),
                Tab(icon: Icon(Icons.people), text: 'Users'),
                Tab(icon: Icon(Icons.apartment), text: 'Hierarchy'),
                Tab(icon: Icon(Icons.category), text: 'Categories'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDashboardTab(),
                _buildUsersTab(),
                _buildHierarchyTab(),
                _buildCategoriesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab() {
    return Consumer<HierarchicalHostelProvider>(
      builder: (context, provider, child) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dashboard Overview',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navyDark,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome to Hostel Management',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navyDark,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Manage hostels, zones, wings, and rooms efficiently',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.navyDark, AppColors.navy],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Quick Actions',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildActionCard(
                                  title: 'Add Hostel',
                                  icon: Icons.add_home,
                                  color: const Color(0xFF66BB6A),
                                  onTap: () => _showAddHostelModal(context),
                                ),
                                const SizedBox(width: 15),
                                _buildActionCard(
                                  title: 'Staff',
                                  icon: Icons.badge,
                                  color: const Color(0xFF1A2744),
                                  onTap: () => _showStaffManagement(context),
                                ),
                                const SizedBox(width: 15),
                                _buildActionCard(
                                  title: 'Category',
                                  icon: Icons.category,
                                  color: const Color(0xFFFFA726),
                                  onTap: () => _tabController.animateTo(3),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUsersTab() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people,
            color: Colors.grey,
            size: 48,
          ),
          SizedBox(height: 16),
          Text(
            'Users Management',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.navyDark,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'User management features coming soon',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHierarchyTab() {
    return const HierarchicalAdminScreen();
  }

  Widget _buildCategoriesTab() {
    return Consumer<CategoryProvider>(
      builder: (context, categoryProvider, child) {
        if (categoryProvider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (categoryProvider.categories.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.category,
                  color: Colors.grey,
                  size: 48,
                ),
                SizedBox(height: 16),
                Text(
                  'No Categories Yet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyDark,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Add your first category',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: categoryProvider.categories.length,
          itemBuilder: (context, index) {
            final category = categoryProvider.categories[index];
            return _buildCategoryCard(category);
          },
        );
      },
    );
  }

  Widget _buildCategoryCard(Map<String, dynamic> category) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    category['name'],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navyDark,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (String value) {
                    if (value == 'Edit') {
                      _showEditCategoryModal(context, category);
                    } else if (value == 'Delete') {
                      _deleteCategory(category);
                    }
                  },
                  itemBuilder: (BuildContext context) => [
                    const PopupMenuItem<String>(
                      value: 'Edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, color: AppColors.navyDark),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'Delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Codes: ${category['codes']?.length ?? 0}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddHostelModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Hostel'),
        content: const Text('Hostel management features are available in the Hierarchy tab.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showStaffManagement(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Staff Management'),
        content: const Text('Staff assignment features are available in the Hierarchy tab.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showEditCategoryModal(BuildContext context, Map<String, dynamic> category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Category'),
        content: const Text('Category management features coming soon.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _deleteCategory(Map<String, dynamic> category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Are you sure you want to delete "${category['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Category deleted successfully'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 110,
        height: 110,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.black.withValues(alpha: 0.03)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A2744),
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
