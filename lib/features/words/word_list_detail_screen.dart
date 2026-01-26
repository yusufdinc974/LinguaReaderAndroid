import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/database_service.dart';

// Familiarity level colors matching desktop
const Map<int, Color> levelColors = {
  1: Color(0xFFef4444), // Red - unknown
  2: Color(0xFFf97316), // Orange - seen before
  3: Color(0xFFeab308), // Yellow - learning
  4: Color(0xFF22c55e), // Green - familiar
  5: Color(0xFF3b82f6), // Blue - mastered
};

class WordListDetailScreen extends StatefulWidget {
  final int listId;
  final String listName;

  const WordListDetailScreen({
    super.key,
    required this.listId,
    required this.listName,
  });

  @override
  State<WordListDetailScreen> createState() => _WordListDetailScreenState();
}

class _WordListDetailScreenState extends State<WordListDetailScreen> {
  final _databaseService = DatabaseService();
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _words = [];
  List<Map<String, dynamic>> _filteredWords = [];
  List<Map<String, dynamic>> _allLists = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadWords();
    _loadAllLists();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadWords() async {
    setState(() => _isLoading = true);
    final words = await _databaseService.getWordsInList(widget.listId);
    if (mounted) {
      setState(() {
        _words = words;
        _filteredWords = words;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAllLists() async {
    final lists = await _databaseService.getWordLists();
    if (mounted) {
      setState(() => _allLists = lists);
    }
  }

  void _filterWords(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredWords = _words;
      } else {
        _filteredWords = _words.where((word) {
          final wordText = (word['word'] as String).toLowerCase();
          final translation = (word['translation'] as String).toLowerCase();
          return wordText.contains(query.toLowerCase()) ||
                 translation.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  Future<void> _showMoveDialog(Map<String, dynamic> word) async {
    final otherLists = _allLists.where((l) => l['id'] != widget.listId).toList();
    
    if (otherLists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other lists available')),
      );
      return;
    }

    final selectedList = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to List'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: otherLists.length,
            itemBuilder: (context, index) {
              final list = otherLists[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _parseColor(list['color']),
                  radius: 16,
                ),
                title: Text(list['name']),
                onTap: () => Navigator.pop(context, list),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedList != null) {
      await _moveWord(word, selectedList);
    }
  }

  Future<void> _moveWord(Map<String, dynamic> word, Map<String, dynamic> targetList) async {
    try {
      final db = await _databaseService.database;
      
      // Add to new list
      await db.insert('word_list_items', {
        'word_list_id': targetList['id'],
        'word_id': word['id'],
      });
      
      // Remove from current list
      await db.delete(
        'word_list_items',
        where: 'word_list_id = ? AND word_id = ?',
        whereArgs: [widget.listId, word['id']],
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Moved to "${targetList['name']}"')),
        );
        _loadWords();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Color _parseColor(String? colorStr) {
    if (colorStr == null) return Colors.blue;
    try {
      if (colorStr.startsWith('0x')) {
        return Color(int.parse(colorStr));
      }
      return Color(int.parse(colorStr));
    } catch (e) {
      return Colors.blue;
    }
  }

  Color _getFamiliarityColor(int? level) {
    return levelColors[level ?? 1] ?? levelColors[1]!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.listName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadWords,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search words...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _filterWords('');
                      },
                    )
                  : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: AppColors.surface,
              ),
              onChanged: _filterWords,
            ),
          ),
          
          // Word Count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_filteredWords.length} words',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  Text(
                    'of ${_words.length} total',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Word List
          Expanded(
            child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredWords.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _searchQuery.isNotEmpty ? Icons.search_off : Icons.school_outlined,
                          size: 64,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isNotEmpty 
                            ? 'No words match your search'
                            : 'No words in this list yet',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredWords.length,
                    itemBuilder: (context, index) {
                      final word = _filteredWords[index];
                      final familiarityLevel = word['mastery_level'] as int? ?? 1;
                      
                      return Dismissible(
                        key: Key(word['id'].toString()),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (direction) async {
                          return await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Remove Word?'),
                              content: Text('Remove "${word['word']}" from this list?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                                  child: const Text('Remove'),
                                ),
                              ],
                            ),
                          );
                        },
                        onDismissed: (direction) async {
                          final wordId = word['id'];
                          setState(() {
                            _words.removeWhere((w) => w['id'] == wordId);
                            _filteredWords.removeAt(index);
                          });
                          
                          await _databaseService.removeWordFromList(widget.listId, wordId);
                          
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Word removed from list')),
                            );
                          }
                        },
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: _getFamiliarityColor(familiarityLevel),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: _getFamiliarityColor(familiarityLevel).withOpacity(0.4),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                            title: Text(
                              word['word'],
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(word['translation']),
                                if (word['source_language'] != null && word['target_language'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '${word['source_language']} → ${word['target_language']}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                              onSelected: (value) {
                                if (value == 'move') {
                                  _showMoveDialog(word);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'move',
                                  child: Row(
                                    children: [
                                      Icon(Icons.drive_file_move_outline, size: 20),
                                      SizedBox(width: 8),
                                      Text('Move to...'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
