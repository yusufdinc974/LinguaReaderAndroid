import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/fox_sprite.dart';
import '../../services/database_service.dart';
import '../../services/subscription_service.dart';
import '../../services/sync_service.dart';
import '../subscription/paywall_screen.dart';
import 'word_list_detail_screen.dart';

class WordListScreen extends StatefulWidget {
  const WordListScreen({super.key});

  @override
  State<WordListScreen> createState() => _WordListScreenState();
}

class _WordListScreenState extends State<WordListScreen> {
  final _databaseService = DatabaseService();
  List<Map<String, dynamic>> _wordLists = [];
  bool _isLoading = true;
  bool _isCreatingList = false;

  final List<Color> _availableColors = [
    AppColors.primary,
    AppColors.primaryDark,
    AppColors.primaryLight,
    AppColors.secondary,
    AppColors.success,
    AppColors.warning,
    const Color(0xFF8D633C),
    const Color(0xFFAA7D4A),
    const Color(0xFF5A4030),
  ];

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  Future<void> _loadLists() async {
    setState(() => _isLoading = true);
    final lists = await _databaseService.getWordLists();
    if (mounted) {
      setState(() {
        _wordLists = lists;
        _isLoading = false;
      });
    }
  }

  Future<void> _showCreateListDialog() async {
    final isPremium = await SubscriptionService.isPremium();
    if (!isPremium && _wordLists.length >= 3) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PaywallScreen()),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Free tier is limited to 3 word lists. Upgrade to Premium for unlimited!')),
        );
      }
      return;
    }

    final TextEditingController nameController = TextEditingController();
    Color selectedColor = _availableColors[0];
    bool isCreating = false;

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('New Word List'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                      labelText: "List Name", hintText: "e.g. French Verbs"),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                const Text("Color Code:",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _availableColors.map((color) {
                    return GestureDetector(
                      onTap: () {
                        setState(() => selectedColor = color);
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                            border: selectedColor == color
                                ? Border.all(
                                    color: AppColors.textPrimary, width: 2)
                                : Border.all(color: AppColors.border)),
                        child: selectedColor == color
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 18)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: const Text('Create'),
                onPressed: isCreating
                    ? null
                    : () async {
                        final rawName = nameController.text.trim();
                        if (rawName.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Please enter a list name.')),
                          );
                          return;
                        }

                        final exists = _wordLists.any((list) {
                          final existingName =
                              (list['name'] as String?)?.trim() ?? '';
                          return existingName.toLowerCase() ==
                              rawName.toLowerCase();
                        });

                        if (exists) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'A list with this name already exists.')),
                          );
                          return;
                        }

                        setState(() => isCreating = true);
                        if (mounted) {
                          this.setState(() => _isCreatingList = true);
                        }

                        try {
                          await _databaseService.createWordList(
                            rawName,
                            "",
                            color:
                                "0x${selectedColor.value.toRadixString(16).toUpperCase()}",
                          );
                          await SyncService.pushToCloud();
                          if (mounted) Navigator.of(context).pop();
                          _loadLists();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Could not create list: $e')),
                            );
                          }
                        } finally {
                          if (mounted) {
                            this.setState(() => _isCreatingList = false);
                          }
                          if (context.mounted) {
                            setState(() => isCreating = false);
                          }
                        }
                      },
              ),
            ],
          );
        });
      },
    );
  }

  Color _getColor(String? colorStr) {
    if (colorStr == null) return AppColors.primary;
    try {
      if (colorStr.startsWith('#')) {
        // Handle CSS hex (#RRGGBB)
        String hex = colorStr.substring(1);
        if (hex.length == 6) {
          return Color(int.parse('0xFF$hex'));
        }
      }
      // Handle Flutter 0x... or plain int
      return Color(int.parse(colorStr));
    } catch (e) {
      return AppColors.primary;
    }
  }

  Future<void> _deleteList(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete List?'),
        content: Text(
            'Are you sure you want to delete "$name"? All words in this list will be unlinked (but not deleted from database).'), // Clarify behavior
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _databaseService.deleteWordList(id);
      await SyncService.pushToCloud();
      _loadLists();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vocabulary')),
      body: RefreshIndicator(
        onRefresh: _loadLists,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _wordLists.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const FoxSpriteAnimator(
                          animation: FoxAnimation.idleSouth,
                          size: 84,
                        ),
                        const SizedBox(height: 8),
                        const Text("No word lists yet."),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed:
                              _isCreatingList ? null : _showCreateListDialog,
                          child: const Text("Create First List"),
                        )
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _wordLists.length,
                    itemBuilder: (context, index) {
                      final list = _wordLists[index];
                      final color = _getColor(list['color']);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: CircleAvatar(
                            backgroundColor: color,
                            child: Text(
                              (list['name'] as String).isNotEmpty
                                  ? (list['name'] as String)[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(
                            list['name'] as String,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          subtitle: Text(
                            list['description'] ?? '',
                            style:
                                const TextStyle(color: AppColors.textSecondary),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: AppColors.textSecondary),
                            onPressed: () =>
                                _deleteList(list['id'], list['name']),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => WordListDetailScreen(
                                  listId: list['id'],
                                  listName: list['name'],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isCreatingList ? null : _showCreateListDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
