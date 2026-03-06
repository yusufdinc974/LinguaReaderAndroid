import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/fox_sprite.dart';
import '../../services/database_service.dart';
import '../../services/sync_service.dart';

// Familiarity level colors matching desktop
const Map<int, Color> levelColors = {
  1: AppColors.error,
  2: AppColors.warning,
  3: AppColors.secondary,
  4: AppColors.primary,
  5: AppColors.success,
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
    final otherLists =
        _allLists.where((l) => l['id'] != widget.listId).toList();

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

  Future<void> _moveWord(
      Map<String, dynamic> word, Map<String, dynamic> targetList) async {
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
      await SyncService.pushToCloud();

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
    if (colorStr == null) return AppColors.primary;
    try {
      if (colorStr.startsWith('0x')) {
        return Color(int.parse(colorStr));
      }
      return Color(int.parse(colorStr));
    } catch (e) {
      return AppColors.primary;
    }
  }

  Color _getFamiliarityColor(int? level) {
    return levelColors[level ?? 1] ?? levelColors[1]!;
  }

  String _notePreview(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    var text = raw;
    text = text.replaceAllMapped(
      RegExp(r'^\s{0,3}(#{1,6}\s*|[-*+]\s+|\d+\.\s+)', multiLine: true),
      (_) => '',
    );
    text = text.replaceAll(RegExp(r'(\*\*|__|`|~~)'), '');
    text = text.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
      (m) => m.group(1) ?? '',
    );
    text = text.replaceAll(RegExp(r'\n+'), ' ').replaceAll(RegExp(r'\s+'), ' ');
    return text.trim();
  }

  Future<void> _saveWordNote(int wordId, String note) async {
    final db = await _databaseService.database;
    final trimmed = note.trim();
    await db.update(
      'words',
      {'note': trimmed.isEmpty ? null : trimmed},
      where: 'id = ?',
      whereArgs: [wordId],
    );
    await SyncService.pushToCloud();

    if (!mounted) return;
    setState(() {
      for (final item in _words) {
        if (item['id'] == wordId) {
          item['note'] = trimmed.isEmpty ? null : trimmed;
        }
      }
      for (final item in _filteredWords) {
        if (item['id'] == wordId) {
          item['note'] = trimmed.isEmpty ? null : trimmed;
        }
      }
    });
  }

  Future<void> _removeWordFromCurrentList(Map<String, dynamic> word) async {
    final wordId = word['id'] as int;
    await _databaseService.removeWordFromList(widget.listId, wordId);
    await SyncService.pushToCloud();
    await _loadWords();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Word removed from list')),
    );
  }

  Future<void> _showWordDetails(Map<String, dynamic> word) async {
    final noteController =
        TextEditingController(text: (word['note'] as String?) ?? '');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.62,
          minChildSize: 0.4,
          maxChildSize: 1.0,
          expand: false,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setModalState) {
                final noteText = noteController.text.trim();
                final hasContext =
                    (word['sentence_context'] as String?)?.trim().isNotEmpty ==
                        true;
                return Container(
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(10)),
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHighlight,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        word['word'] as String? ?? '',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        word['translation'] as String? ?? '',
                        style: const TextStyle(
                          fontSize: 18,
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _WordMetaChip(
                            icon: Icons.flag_circle_outlined,
                            text: 'Level ${word['mastery_level'] ?? 0}',
                            color: _getFamiliarityColor(
                              (word['mastery_level'] as int?) ?? 1,
                            ),
                          ),
                          if ((word['source_language'] as String?) != null &&
                              (word['target_language'] as String?) != null)
                            _WordMetaChip(
                              icon: Icons.translate,
                              text:
                                  '${word['source_language']} → ${word['target_language']}',
                              color: AppColors.primary,
                            ),
                          if ((word['created_at'] as String?) != null)
                            _WordMetaChip(
                              icon: Icons.schedule,
                              text: (word['created_at'] as String)
                                  .split('T')
                                  .first,
                              color: AppColors.textSecondary,
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Note',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (noteText.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHighlight.withOpacity(0.45),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: MarkdownBody(
                            data: noteText,
                            selectable: true,
                            styleSheet: MarkdownStyleSheet(
                              p: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                height: 1.4,
                              ),
                              h1: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                              h2: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                              h3: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                              listBullet: const TextStyle(
                                color: AppColors.secondary,
                                fontSize: 13,
                              ),
                              blockSpacing: 8,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      TextField(
                        controller: noteController,
                        minLines: 5,
                        maxLines: 12,
                        onChanged: (_) => setModalState(() {}),
                        decoration: InputDecoration(
                          hintText:
                              'No note yet. Write details for this word...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      if (hasContext) ...[
                        const SizedBox(height: 18),
                        const Text(
                          'Context',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          (word['sentence_context'] as String?) ?? '',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (Navigator.of(modalContext).canPop()) {
                              Navigator.of(modalContext).pop();
                            }
                            await _saveWordNote(word['id'] as int, noteText);
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(content: Text('Note saved')),
                            );
                          },
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save Note'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            if (Navigator.of(modalContext).canPop()) {
                              Navigator.of(modalContext).pop();
                            }
                            await _showMoveDialog(word);
                          },
                          icon: const Icon(Icons.drive_file_move_outline),
                          label: const Text('Move to Another List'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: () async {
                            if (Navigator.of(modalContext).canPop()) {
                              Navigator.of(modalContext).pop();
                            }
                            await _removeWordFromCurrentList(word);
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove from This List'),
                          style:
                              TextButton.styleFrom(foregroundColor: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );

    noteController.dispose();
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
                            FoxSpriteAnimator(
                              animation: _searchQuery.isNotEmpty
                                  ? FoxAnimation.yawnSouth
                                  : FoxAnimation.idleSouth,
                              size: 82,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'No words match your search'
                                  : 'No words in this list yet',
                              style: const TextStyle(
                                  color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _filteredWords.length,
                        itemBuilder: (context, index) {
                          final word = _filteredWords[index];
                          final familiarityLevel =
                              word['mastery_level'] as int? ?? 1;

                          return Dismissible(
                            key: Key(word['id'].toString()),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: AppColors.error,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child:
                                  const Icon(Icons.delete, color: Colors.white),
                            ),
                            confirmDismiss: (direction) async {
                              return await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Remove Word?'),
                                  content: Text(
                                      'Remove "${word['word']}" from this list?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      style: TextButton.styleFrom(
                                          foregroundColor: Colors.red),
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

                              await _databaseService.removeWordFromList(
                                  widget.listId, wordId);
                              await SyncService.pushToCloud();

                              if (mounted) {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Word removed from list')),
                                );
                              }
                            },
                            child: Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                onTap: () => _showWordDetails(word),
                                leading: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color:
                                        _getFamiliarityColor(familiarityLevel),
                                    borderRadius: BorderRadius.circular(2),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                ),
                                title: Text(
                                  word['word'],
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(word['translation']),
                                    if (word['note'] != null &&
                                        (word['note'] as String)
                                            .trim()
                                            .isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          _notePreview(word['note'] as String?),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                    if (word['source_language'] != null &&
                                        word['target_language'] != null)
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
                                  icon: const Icon(Icons.more_vert,
                                      color: AppColors.textSecondary),
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
                                          Icon(Icons.drive_file_move_outline,
                                              size: 20),
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

class _WordMetaChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _WordMetaChip({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
