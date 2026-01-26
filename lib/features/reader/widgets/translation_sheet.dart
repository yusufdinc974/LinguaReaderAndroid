import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../services/translation_service.dart';
import '../../../services/database_service.dart';
import '../../../services/pdf_highlight_service.dart';

// Familiarity level colors matching desktop
const Map<int, Color> levelColors = {
  1: Color(0xFFef4444), // Red - unknown
  2: Color(0xFFf97316), // Orange - seen before
  3: Color(0xFFeab308), // Yellow - learning
  4: Color(0xFF22c55e), // Green - familiar
  5: Color(0xFF3b82f6), // Blue - mastered
};

const Map<int, String> levelLabels = {
  1: 'Unknown',
  2: 'Seen',
  3: 'Learning',
  4: 'Familiar',
  5: 'Mastered',
};

class TranslationSheet extends StatefulWidget {
  final String word;
  final String sentence;
  final ScrollController? scrollController;

  const TranslationSheet({
    super.key,
    required this.word,
    required this.sentence,
    this.scrollController,
  });

  @override
  State<TranslationSheet> createState() => _TranslationSheetState();
}

class _TranslationSheetState extends State<TranslationSheet> {
  final _translationService = TranslationService();
  final _databaseService = DatabaseService();
  String? _translation;
  String? _source;
  bool _isLoading = true;
  String? _error;
  bool _isSaving = false;
  int _selectedLevel = 1; // Default to Unknown
  List<Map<String, dynamic>> _wordLists = [];
  bool _showCreateListForm = false;
  final _newListNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _translate();
    _loadWordLists();
  }

  @override
  void dispose() {
    _newListNameController.dispose();
    super.dispose();
  }

  Future<void> _translate() async {
    try {
      final result = await _translationService.translateText(widget.word);
      if (mounted) {
        setState(() {
          _translation = result.translatedText;
          _source = result.source;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "Could not translate: $e";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadWordLists() async {
    final lists = await _databaseService.getWordLists();
    if (mounted) {
      setState(() => _wordLists = lists);
    }
  }

  Future<Color> _parseColor(String? colorStr) async {
    if (colorStr == null) return const Color(0xFF2196F3);
    try {
      if (colorStr.startsWith('#')) {
        final hex = colorStr.replaceAll('#', '');
        if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
        if (hex.length == 8) return Color(int.parse(hex, radix: 16));
      } else if (colorStr.startsWith('0x')) {
        return Color(int.parse(colorStr));
      }
      return Color(int.parse(colorStr));
    } catch (_) {
      return const Color(0xFF2196F3);
    }
  }

  Future<void> _createNewList() async {
    final name = _newListNameController.text.trim();
    if (name.isEmpty) return;

    final listId = await _databaseService.createWordList(name, '');
    _newListNameController.clear();
    await _loadWordLists();
    
    if (mounted) {
      setState(() => _showCreateListForm = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created list "$name"')),
      );
    }
  }

  Future<void> _saveWord(int listId, String listName, String? colorStr) async {
    if (_translation == null) return;
    
    setState(() => _isSaving = true);
    
    try {
      await _databaseService.addWord(
        listId: listId,
        word: widget.word,
        translation: _translation!,
        context: widget.sentence,
      );
      
      // Update familiarity level
      final db = await _databaseService.database;
      await db.update(
        'word_familiarity',
        {'familiarity_level': _selectedLevel},
        where: 'word_lower = ?',
        whereArgs: [widget.word.toLowerCase()],
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Word saved to $listName')),
        );
        
        final color = await _parseColor(colorStr);
        Navigator.pop(context, WordColor(widget.word, color));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: ListView(
        controller: widget.scrollController,
        children: [
          // Word and translation
          Text(
            widget.word,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.error))
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _translation ?? '',
                  style: const TextStyle(
                    fontSize: 20,
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_source != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.translate, size: 12, color: AppColors.textSecondary.withOpacity(0.7)),
                      const SizedBox(width: 4),
                      Text(
                        'Translated with $_source',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          
          const SizedBox(height: 24),
          
          // Familiarity Level Selector
          const Text(
            'Familiarity Level',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [1, 2, 3, 4, 5].map((level) {
              final isSelected = _selectedLevel == level;
              return GestureDetector(
                onTap: () => setState(() => _selectedLevel = level),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isSelected ? levelColors[level] : levelColors[level]!.withOpacity(0.3),
                        shape: BoxShape.circle,
                        border: isSelected 
                          ? Border.all(color: Colors.white, width: 3) 
                          : null,
                      ),
                      child: Center(
                        child: Text(
                          '$level',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: isSelected ? 18 : 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      levelLabels[level]!,
                      style: TextStyle(
                        fontSize: 10,
                        color: isSelected ? levelColors[level] : AppColors.textSecondary,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          
          const SizedBox(height: 24),
          const Divider(color: AppColors.surfaceHighlight),
          const SizedBox(height: 16),
          
          // Save to List Section
          const Text(
            'Save to Word List',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          
          if (_isSaving)
            const Center(child: CircularProgressIndicator())
          else ...[
            // Word lists
            if (_wordLists.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighlight.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'No word lists yet. Create one below!',
                  style: TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...(_wordLists.map((list) {
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _parseColorSync(list['color']),
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(list['name'] ?? 'Unnamed'),
                  trailing: IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                    onPressed: () => _saveWord(
                      list['id'] as int,
                      list['name'] as String,
                      list['color'] as String?,
                    ),
                  ),
                  onTap: () => _saveWord(
                    list['id'] as int,
                    list['name'] as String,
                    list['color'] as String?,
                  ),
                );
              })),
            
            const SizedBox(height: 16),
            
            // Create new list
            if (_showCreateListForm)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighlight.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _newListNameController,
                      decoration: const InputDecoration(
                        hintText: 'List name',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _showCreateListForm = false),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _createNewList,
                          child: const Text('Create'),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: () => setState(() => _showCreateListForm = true),
                icon: const Icon(Icons.add),
                label: const Text('Create New List'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
          ],
          
          const SizedBox(height: 16),
          const Divider(color: AppColors.surfaceHighlight),
          const SizedBox(height: 8),
          
          // Context
          const Text(
            "Context:",
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.sentence.isNotEmpty ? widget.sentence : "No context available",
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Color _parseColorSync(String? colorStr) {
    if (colorStr == null) return const Color(0xFF2196F3);
    try {
      if (colorStr.startsWith('#')) {
        final hex = colorStr.replaceAll('#', '');
        if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
        if (hex.length == 8) return Color(int.parse(hex, radix: 16));
      } else if (colorStr.startsWith('0x')) {
        return Color(int.parse(colorStr));
      }
      return Color(int.parse(colorStr));
    } catch (_) {
      return const Color(0xFF2196F3);
    }
  }
}
