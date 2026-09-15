import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../config/app_theme.dart';
import 'new_category_screen.dart';

import '../widgets/search_bar_widget.dart';

class ItemParentsScreen extends StatefulWidget {
  final List<String> allParents;
  final List<String> newParents;

  const ItemParentsScreen({
    super.key,
    required this.allParents,
    required this.newParents,
  });

  @override
  State<ItemParentsScreen> createState() => _ItemParentsScreenState();
}

class _ItemParentsScreenState extends State<ItemParentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _filteredParents = [];

  @override
  void initState() {
    super.initState();
    _filteredParents = widget.allParents;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String? query) {
    setState(() {
      final safeQuery = query ?? '';
      if (safeQuery.isEmpty) {
        _filteredParents = widget.allParents;
      } else {
        final lowerQuery = safeQuery.toLowerCase();
        _filteredParents = widget.allParents
            .where((p) => p.toLowerCase().contains(lowerQuery))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: const Text('Item Parents', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SearchBarWidget(
              controller: _searchController,
              hintText: 'Search parents...',
              onChanged: _onSearchChanged,
              margin: EdgeInsets.zero,
            ),
          ),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_filteredParents.isEmpty) {
      return const Center(
        child: Text('No item parents found.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredParents.length,
      itemBuilder: (context, index) {
        final parent = _filteredParents[index];
        final isNew = widget.newParents.contains(parent);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    parent,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                if (isNew)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: const Text(
                      'NEW',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => NewCategoryScreen(
                    newCategories: [parent],
                    screenTitle: parent,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
