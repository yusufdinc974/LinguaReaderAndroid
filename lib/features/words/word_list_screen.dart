import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/database_service.dart';
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

  final List<Color> _availableColors = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.amber,
    Colors.brown,
    Colors.indigo,
    Colors.cyan,
    Colors.blueGrey,
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
    final TextEditingController nameController = TextEditingController();
    Color selectedColor = _availableColors[0];

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('New Word List'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: "List Name",
                      hintText: "e.g. French Verbs"
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  const Text("Color Code:", style: TextStyle(fontWeight: FontWeight.bold)),
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
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: selectedColor == color 
                                ? Border.all(color: Colors.black, width: 2)
                                : null,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                              )
                            ]
                          ),
                          child: selectedColor == color 
                              ? const Icon(Icons.check, color: Colors.white, size: 20)
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
                  onPressed: () async {
                    if (nameController.text.isNotEmpty) {
                      await _databaseService.createWordList(
                        nameController.text, 
                        "",
                        color: "0x${selectedColor.value.toRadixString(16).toUpperCase()}"
                      );
                      if (mounted) Navigator.of(context).pop();
                      _loadLists();
                    }
                  },
                ),
              ],
            );
          }
        );
      },
    );
  }

  Color _getColor(String? colorStr) {
    if (colorStr == null) return Colors.blue;
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
      return Colors.blue;
    }
  }

  Future<void> _deleteList(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete List?'),
        content: Text('Are you sure you want to delete "$name"? All words in this list will be unlinked (but not deleted from database).'), // Clarify behavior
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
                        const Text("No word lists yet."),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _showCreateListDialog,
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
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(
                            list['name'] as String,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          subtitle: Text(
                            list['description'] ?? '',
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppColors.textSecondary),
                            onPressed: () => _deleteList(list['id'], list['name']),
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
        onPressed: _showCreateListDialog,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
      ),
    );
  }
}
