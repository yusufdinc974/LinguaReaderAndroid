import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/constants/app_colors.dart';
import '../../../services/translation_service.dart';
import '../../../services/database_service.dart';
import '../../../services/pdf_highlight_service.dart';
import '../../../services/gemini_service.dart';
import '../../../services/sync_service.dart';
import '../../subscription/paywall_screen.dart';

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

const Map<String, String> translationTargetLanguages = {
  'English': 'EN',
  'Spanish': 'ES',
  'French': 'FR',
  'German': 'DE',
  'Italian': 'IT',
  'Portuguese': 'PT',
  'Dutch': 'NL',
  'Polish': 'PL',
  'Russian': 'RU',
  'Japanese': 'JA',
  'Chinese (Simplified)': 'ZH',
  'Turkish': 'TR',
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

class _TranslationSheetState extends State<TranslationSheet>
    with SingleTickerProviderStateMixin {
  final _translationService = TranslationService();
  final _databaseService = DatabaseService();
  final _geminiService = GeminiService();

  late final TabController _tabController;

  // ── Translate tab state ──
  String? _translation;
  String? _source;
  bool _isTranslating = true;
  String? _translationError;
  bool _isSaving = false;
  int _selectedLevel = 1;
  List<Map<String, dynamic>> _wordLists = [];
  bool _showCreateListForm = false;
  final _newListNameController = TextEditingController();
  final _noteController = TextEditingController();

  // ── Gemini tab state ──
  String? _geminiResult;
  bool _isAskingGemini = false;
  String?
      _geminiError; // 'not_logged_in', 'premium_required', or free-form error
  bool _geminiTabLoaded = false;
  String _selectedTargetLanguageCode = 'TR';
  String _geminiTargetLanguage = 'Turkish';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadUserSettings();
    _loadWordLists();
    _loadExistingNote();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _newListNameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    // Lazy-load Gemini on first switch
    if (_tabController.index == 1 && !_geminiTabLoaded) {
      _askGemini();
    }
    setState(() {});
  }

  Future<void> _loadUserSettings() async {
    final targetLanguageCode =
        await _databaseService.getSetting('target_language');
    final normalizedCode = _normalizeTargetLanguageCode(targetLanguageCode);
    final mappedTarget = _languageCodeToName(normalizedCode);

    if (mounted) {
      setState(() {
        _selectedTargetLanguageCode = normalizedCode;
        _geminiTargetLanguage = mappedTarget;
      });
    }

    await _translate();
  }

  String _normalizeTargetLanguageCode(String? code) {
    final normalized = (code ?? '').trim().toUpperCase();
    if (translationTargetLanguages.containsValue(normalized)) {
      return normalized;
    }
    return 'TR';
  }

  String _languageCodeToName(String? code) {
    switch ((code ?? '').toLowerCase()) {
      case 'tr':
        return 'Turkish';
      case 'en':
        return 'English';
      case 'de':
        return 'German';
      case 'fr':
        return 'French';
      case 'es':
        return 'Spanish';
      case 'it':
        return 'Italian';
      case 'pt':
        return 'Portuguese';
      case 'nl':
        return 'Dutch';
      case 'pl':
        return 'Polish';
      case 'ru':
        return 'Russian';
      case 'ja':
        return 'Japanese';
      case 'zh':
      case 'zh-cn':
      case 'zh-tw':
        return 'Chinese (Simplified)';
      default:
        return 'Turkish';
    }
  }

  // ── Translate ──────────────────────────────────────────────────────────────

  Future<void> _translate() async {
    if (mounted) {
      setState(() {
        _isTranslating = true;
        _translationError = null;
      });
    }

    try {
      final result = await _translationService.translateText(
        widget.word,
        targetLang: _selectedTargetLanguageCode,
      );
      if (mounted) {
        setState(() {
          _translation = result.translatedText;
          _source = result.source;
          _isTranslating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _translationError = 'Could not translate: $e';
          _isTranslating = false;
        });
      }
    }
  }

  Future<void> _onTargetLanguageChanged(String? code) async {
    if (code == null) return;
    if (code == _selectedTargetLanguageCode) return;

    setState(() {
      _selectedTargetLanguageCode = code;
      _geminiTargetLanguage = _languageCodeToName(code);
      _geminiResult = null;
      _geminiError = null;
      _geminiTabLoaded = false;
    });

    await _databaseService.saveSetting('target_language', code);
    await _translate();
  }

  Future<void> _loadWordLists() async {
    final lists = await _databaseService.getWordLists();
    if (mounted) setState(() => _wordLists = lists);
  }

  Future<void> _loadExistingNote() async {
    final existingNote =
        await _databaseService.getLatestNoteForWord(widget.word);
    if (!mounted || existingNote == null || existingNote.trim().isEmpty) return;
    _noteController.text = existingNote;
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

  Future<void> _createNewList() async {
    final name = _newListNameController.text.trim();
    if (name.isEmpty) return;
    await _databaseService.createWordList(name, '');
    await SyncService.pushToCloud();
    _newListNameController.clear();
    await _loadWordLists();
    if (mounted) {
      setState(() => _showCreateListForm = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Created list "$name"')));
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
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );
      final db = await _databaseService.database;
      await db.update(
        'word_familiarity',
        {'familiarity_level': _selectedLevel},
        where: 'word_lower = ?',
        whereArgs: [widget.word.toLowerCase()],
      );
      await SyncService.pushToCloud();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Word saved to $listName')));
        final color = await _parseColor(colorStr);
        Navigator.pop(context, WordColor(widget.word, color));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveGeminiAnswerAsNote(String answer) async {
    final note = answer.trim();
    if (note.isEmpty) return;
    try {
      final updatedRows = await _databaseService.updateNoteForWord(
        widget.word,
        note,
      );
      if (updatedRows > 0) {
        await SyncService.pushToCloud();
      }
    } catch (_) {
      // Do not interrupt Gemini UX for note persistence failures.
    }
  }

  // ── Ask Gemini ─────────────────────────────────────────────────────────────

  Future<void> _askGemini() async {
    setState(() {
      _isAskingGemini = true;
      _geminiError = null;
      _geminiTabLoaded = true;
    });
    try {
      final result = await _geminiService.explainPhrase(
        widget.word,
        targetLanguage: _geminiTargetLanguage,
      );
      if (mounted) {
        if (_noteController.text.trim().isEmpty) {
          _noteController.text = result.trim();
        }
        setState(() {
          _geminiResult = result;
          _isAskingGemini = false;
        });
      }
      await _saveGeminiAnswerAsNote(result);
    } catch (e) {
      if (mounted) {
        // Normalize "premium_required: ..." to "premium_required" for UI state handling.
        final msg = e.toString().replaceFirst('Exception: ', '').trim();
        final normalized =
            msg == 'premium_required' || msg.startsWith('premium_required:')
                ? 'premium_required'
                : (msg == 'not_logged_in' ? 'not_logged_in' : msg);
        setState(() {
          _geminiError = normalized;
          _isAskingGemini = false;
        });
      }
    }
  }

  Widget _buildScrollableCenter(Widget child, {EdgeInsets? padding}) {
    return ListView(
      controller: widget.scrollController,
      padding: padding ?? const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: child,
          ),
        ),
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ──
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Word title ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.word,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),

          // ── Tabs ──
          TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: 'Translate'),
              Tab(text: 'Ask Gemini'),
            ],
          ),

          // ── Tab content ──
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTranslateTab(),
                _buildGeminiTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Translate Tab ──────────────────────────────────────────────────────────

  Widget _buildTranslateTab() {
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        DropdownButtonFormField<String>(
          value: _selectedTargetLanguageCode,
          decoration: const InputDecoration(
            labelText: 'Translation Language',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.language),
            helperText: 'Saved as your last preference.',
          ),
          items: translationTargetLanguages.entries
              .map(
                (entry) => DropdownMenuItem(
                  value: entry.value,
                  child: Text('${entry.key} (${entry.value})'),
                ),
              )
              .toList(),
          onChanged: _onTargetLanguageChanged,
        ),
        const SizedBox(height: 16),
        if (_isTranslating)
          const Center(child: CircularProgressIndicator())
        else if (_translationError != null)
          Text(_translationError!,
              style: const TextStyle(color: AppColors.error))
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _translation ?? '',
                style: const TextStyle(
                    fontSize: 20,
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w500),
              ),
              if (_source != null) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.translate,
                        size: 12,
                        color: AppColors.textSecondary.withOpacity(0.7)),
                    const SizedBox(width: 4),
                    Text(
                      'Translated with $_source',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary.withOpacity(0.7)),
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
              color: AppColors.textSecondary),
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
                      color: isSelected
                          ? levelColors[level]
                          : levelColors[level]!.withOpacity(0.3),
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
                      color: isSelected
                          ? levelColors[level]
                          : AppColors.textSecondary,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
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

        const Text(
          'Note (optional)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _noteController,
          minLines: 3,
          maxLines: 7,
          decoration: InputDecoration(
            hintText:
                'Add your own note. Gemini answers will be saved here automatically.',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),

        const SizedBox(height: 24),
        const Divider(color: AppColors.surfaceHighlight),
        const SizedBox(height: 16),

        // Save to List Section
        const Text('Save to Word List',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 12),

        if (_isSaving)
          const Center(child: CircularProgressIndicator())
        else ...[
          if (_wordLists.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceHighlight.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('No word lists yet. Create one below!',
                  style: TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center),
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
                  icon: const Icon(Icons.add_circle_outline,
                      color: AppColors.primary),
                  onPressed: () => _saveWord(list['id'] as int,
                      list['name'] as String, list['color'] as String?),
                ),
                onTap: () => _saveWord(list['id'] as int,
                    list['name'] as String, list['color'] as String?),
              );
            })),
          const SizedBox(height: 16),
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
                        isDense: true),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                          onPressed: () =>
                              setState(() => _showCreateListForm = false),
                          child: const Text('Cancel')),
                      const SizedBox(width: 8),
                      ElevatedButton(
                          onPressed: _createNewList,
                          child: const Text('Create')),
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
                  padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
        ],

        const SizedBox(height: 16),
        const Divider(color: AppColors.surfaceHighlight),
        const SizedBox(height: 8),

        const Text('Context:',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Text(
          widget.sentence.isNotEmpty ? widget.sentence : 'No context available',
          style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Gemini Tab ─────────────────────────────────────────────────────────────

  Widget _buildGeminiTab() {
    // Loading
    if (_isAskingGemini) {
      return _buildScrollableCenter(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Asking Gemini about "${widget.word}"…',
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    // Not logged in
    if (_geminiError == 'not_logged_in') {
      return _buildScrollableCenter(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_circle_outlined,
                size: 60, color: AppColors.primary),
            const SizedBox(height: 16),
            const Text(
              'Sign In to Use Gemini',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'You need to be signed in to use AI-powered explanations.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.login),
                label: const Text('Go to Sign In'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Not premium
    if (_geminiError == 'premium_required') {
      return _buildScrollableCenter(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C3DE4), Color(0xFF9B59B6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child:
                  const Icon(Icons.auto_awesome, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 20),
            const Text(
              'Premium Feature',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'AI-powered explanations with Gemini are available for Premium subscribers.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF6C3DE4).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: const Color(0xFF6C3DE4).withOpacity(0.3)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PremiumBullet(
                      icon: Icons.auto_awesome,
                      text: 'Detailed word & phrase explanations'),
                  SizedBox(height: 8),
                  _PremiumBullet(
                      icon: Icons.translate,
                      text: 'Example sentences in your language'),
                  SizedBox(height: 8),
                  _PremiumBullet(
                      icon: Icons.lightbulb_outline,
                      text: 'Usage tips & collocations'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final upgraded = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (_) => const PaywallScreen()),
                  );
                  if (!mounted) return;
                  if (upgraded == true) {
                    setState(() {
                      _geminiError = null;
                      _geminiResult = null;
                      _geminiTabLoaded = false;
                    });
                    _askGemini();
                  }
                },
                icon: const Icon(Icons.workspace_premium),
                label: const Text('Upgrade to Premium'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFF6C3DE4),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Generic error
    if (_geminiError != null) {
      return _buildScrollableCenter(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            Text(
              _geminiError!,
              style: const TextStyle(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _geminiError = null;
                  _geminiTabLoaded = false;
                });
                _askGemini();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Not yet asked (connected but tab not switched yet)
    if (_geminiResult == null) {
      return _buildScrollableCenter(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 48, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              'Ask Gemini about "${widget.word}"',
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _askGemini,
              icon: const Icon(Icons.send),
              label: const Text('Get Explanation'),
            ),
          ],
        ),
      );
    }

    // Result
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Header row
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            const Text('Gemini',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                    fontSize: 13)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh,
                  size: 18, color: AppColors.textSecondary),
              tooltip: 'Ask again',
              onPressed: () {
                setState(() {
                  _geminiResult = null;
                  _geminiTabLoaded = false;
                });
                _askGemini();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Render full markdown response
        _buildGeminiContent(_geminiResult!),
      ],
    );
  }

  Widget _buildGeminiContent(String text) {
    return MarkdownBody(
      selectable: true,
      data: text,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          height: 1.5,
        ),
        h1: const TextStyle(
          color: AppColors.primary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        h2: const TextStyle(
          color: AppColors.primary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
        h3: const TextStyle(
          color: AppColors.primary,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        strong: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.bold,
        ),
        listBullet: const TextStyle(
          color: AppColors.secondary,
          fontSize: 14,
        ),
        blockSpacing: 10,
      ),
    );
  }
}

/// Small icon + text row used in the Gemini premium upgrade banner.
class _PremiumBullet extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PremiumBullet({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF6C3DE4)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}
