import 'package:flutter/material.dart';
import 'dart:math';
import '../../services/database_service.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/fox_sprite.dart';
import '../../core/widgets/streak_animation_overlay.dart';

enum QuizType { flashcard, multipleChoice, reverse }

enum ReviewRating {
  again(0, 'Again', AppColors.error, Icons.replay),
  hard(3, 'Hard', AppColors.warning, Icons.trending_flat),
  good(4, 'Good', AppColors.secondary, Icons.check),
  easy(5, 'Easy', AppColors.primary, Icons.bolt);

  const ReviewRating(this.quality, this.label, this.color, this.icon);

  final int quality;
  final String label;
  final Color color;
  final IconData icon;
}

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen>
    with SingleTickerProviderStateMixin {
  final _databaseService = DatabaseService();

  // Setup state
  bool _isSetupMode = true;
  List<Map<String, dynamic>> _wordLists = [];
  Map<int, Map<String, int>> _listWordCounts = {}; // {listId: {total, due}}
  int? _selectedListId;
  QuizType _quizType = QuizType.flashcard;
  int _quizSize = 10;
  bool _isLoading = true;

  // Quiz state
  List<Map<String, dynamic>> _quizWords = [];
  List<Map<String, dynamic>> _allListWords = []; // For generating options
  int _currentIndex = 0;
  bool _isFlipped = false;
  bool _showAnswer = false;
  String? _selectedAnswer;
  bool _lastMultipleChoiceCorrect = false;

  // Anki-like learning progression
  static const int _learningStepsToGraduate = 2;
  Map<int, int> _learningStepByWordId = {};
  Set<int> _attemptedWordIds = {};
  int _initialQuizCount = 0;
  int _graduatedCount = 0;
  int _firstAttemptCorrect = 0;
  int _attemptCount = 0;
  int _correctCount = 0;
  bool _completionPersisted = false;

  // Animation
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _loadWordLists();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadWordLists() async {
    setState(() => _isLoading = true);
    try {
      final lists = await _databaseService.getWordLists();
      final counts = <int, Map<String, int>>{};

      // Get due words for counting
      final dueWords = await _databaseService.getDueWords();
      final dueWordSet = dueWords
          .map((w) => (w['word_lower'] as String).toLowerCase())
          .toSet();

      for (var list in lists) {
        final listId = list['id'] as int;
        final words = await _databaseService.getWordsInList(listId);
        final dueCount = words
            .where(
                (w) => dueWordSet.contains((w['word'] as String).toLowerCase()))
            .length;
        counts[listId] = {'total': words.length, 'due': dueCount};
      }

      if (mounted) {
        setState(() {
          _wordLists = lists;
          _listWordCounts = counts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _startQuiz({bool reviewOnly = false}) async {
    if (_selectedListId == null) return;

    setState(() => _isLoading = true);

    try {
      // Get words and make a deep mutable copy immediately
      final rawWords = await _databaseService.getWordsInList(_selectedListId!);
      final words = rawWords.map((w) => Map<String, dynamic>.from(w)).toList();
      _allListWords = words;

      List<Map<String, dynamic>> quizWords;

      if (reviewOnly) {
        final dueWords = await _databaseService.getDueWords();
        final dueWordSet = dueWords
            .map((w) => (w['word_lower'] as String).toLowerCase())
            .toSet();
        quizWords = words
            .where(
                (w) => dueWordSet.contains((w['word'] as String).toLowerCase()))
            .map((w) => Map<String, dynamic>.from(w))
            .toList();
      } else {
        quizWords = words.map((w) => Map<String, dynamic>.from(w)).toList();
      }

      if (quizWords.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(reviewOnly
                    ? 'No words due for review in this list.'
                    : 'No words in this list.')),
          );
          setState(() => _isLoading = false);
        }
        return;
      }

      // Shuffle and limit - quizWords is already mutable
      quizWords.shuffle();
      quizWords = quizWords.take(_quizSize).toList();

      // Generate options for multiple choice / reverse modes
      for (var word in quizWords) {
        final otherWords =
            _allListWords.where((w) => w['id'] != word['id']).toList();
        otherWords.shuffle();
        final options = otherWords.take(3).toList();

        List<dynamic> optionList;
        if (_quizType == QuizType.reverse) {
          optionList = [word['word'], ...options.map((o) => o['word'])];
        } else {
          optionList = [
            word['translation'],
            ...options.map((o) => o['translation'])
          ];
        }
        optionList.shuffle();
        word['options'] = optionList;
      }

      if (mounted) {
        final learningMap = <int, int>{};
        for (final word in quizWords) {
          final id = _getWordId(word);
          learningMap[id] = 0;
        }

        setState(() {
          _quizWords = quizWords;
          _currentIndex = 0;
          _isSetupMode = false;
          _isLoading = false;
          _initialQuizCount = quizWords.length;
          _graduatedCount = 0;
          _firstAttemptCorrect = 0;
          _attemptCount = 0;
          _correctCount = 0;
          _attemptedWordIds = {};
          _learningStepByWordId = learningMap;
          _isFlipped = false;
          _showAnswer = false;
          _selectedAnswer = null;
          _lastMultipleChoiceCorrect = false;
          _completionPersisted = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _flipCard() {
    if (_isFlipped) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    setState(() => _isFlipped = !_isFlipped);
  }

  int _getWordId(Map<String, dynamic> word) {
    final id = word['id'];
    if (id is int) return id;
    final token =
        (word['word'] as String?)?.toLowerCase() ?? word.hashCode.toString();
    return token.hashCode;
  }

  double _calculateProgress() {
    if (_initialQuizCount == 0) return 0;
    final score = _learningStepByWordId.values.fold<double>(
      0,
      (sum, step) =>
          sum + (step / _learningStepsToGraduate).clamp(0, 1).toDouble(),
    );
    return (score / _initialQuizCount).clamp(0.0, 1.0);
  }

  Future<void> _handleFlashcardRating(ReviewRating rating) async {
    final currentWord = _quizWords[_currentIndex];
    await _applyReviewRating(
      currentWord: currentWord,
      rating: rating,
      countsAsCorrect: rating != ReviewRating.again,
    );
  }

  void _handleMultipleChoiceAnswer(String answer) {
    final currentWord = _quizWords[_currentIndex];
    final correctAnswer = _quizType == QuizType.reverse
        ? currentWord['word']
        : currentWord['translation'];
    final isCorrect = answer == correctAnswer;

    setState(() {
      _selectedAnswer = answer;
      _showAnswer = true;
      _lastMultipleChoiceCorrect = isCorrect;
    });
  }

  Future<void> _submitMultipleChoiceRating(ReviewRating rating) async {
    if (_quizWords.isEmpty) return;
    final currentWord = _quizWords[_currentIndex];
    await _applyReviewRating(
      currentWord: currentWord,
      rating: rating,
      countsAsCorrect: _lastMultipleChoiceCorrect,
    );
  }

  Future<void> _applyReviewRating({
    required Map<String, dynamic> currentWord,
    required ReviewRating rating,
    required bool countsAsCorrect,
  }) async {
    final wordId = _getWordId(currentWord);
    final isFirstAttempt = _attemptedWordIds.add(wordId);
    final currentStep = _learningStepByWordId[wordId] ?? 0;

    _attemptCount++;
    if (countsAsCorrect) {
      _correctCount++;
      if (isFirstAttempt) {
        _firstAttemptCorrect++;
      }
    }

    var nextStep = currentStep;
    var graduated = false;
    var reinsertOffset = 2;

    switch (rating) {
      case ReviewRating.again:
        nextStep = 0;
        reinsertOffset = 1;
        break;
      case ReviewRating.hard:
        nextStep = max(1, currentStep);
        reinsertOffset = 2;
        break;
      case ReviewRating.good:
        nextStep = min(currentStep + 1, _learningStepsToGraduate);
        graduated = nextStep >= _learningStepsToGraduate;
        reinsertOffset = 3;
        break;
      case ReviewRating.easy:
        nextStep = _learningStepsToGraduate;
        graduated = true;
        reinsertOffset = 4;
        break;
    }

    _learningStepByWordId[wordId] = nextStep;
    if (graduated) {
      _graduatedCount++;
    }

    await _updateSRS(currentWord, rating.quality);
    _moveToNext(graduated: graduated, reinsertOffset: reinsertOffset);
  }

  void _moveToNext({required bool graduated, int reinsertOffset = 2}) {
    if (graduated) {
      // Remove from quiz
      _quizWords.removeAt(_currentIndex);
      if (_currentIndex >= _quizWords.length) {
        _currentIndex = 0;
      }
    } else {
      // Reinsert close to the front for failed/hard cards, farther for easier grades.
      final word = _quizWords.removeAt(_currentIndex);
      final insertIndex =
          min(_currentIndex + reinsertOffset, _quizWords.length);
      _quizWords.insert(insertIndex, word);
      if (_currentIndex >= _quizWords.length) {
        _currentIndex = 0;
      }
    }

    setState(() {
      _isFlipped = false;
      _showAnswer = false;
      _selectedAnswer = null;
      _lastMultipleChoiceCorrect = false;
      _controller.reset();
    });

    // Check if quiz complete
    if (_quizWords.isEmpty) {
      _showCompletionDialog();
    }
  }

  Future<void> _updateSRS(Map<String, dynamic> word, int quality) async {
    final wordLower = (word['word'] as String).toLowerCase();
    final familiarityId = await _databaseService.getOrCreateWordFamiliarityId(
      wordLower,
      translation: word['translation'] as String?,
    );

    if (familiarityId != null) {
      await _databaseService.updateWordFamiliarity(familiarityId, quality);
    }
  }

  void _showCompletionDialog() {
    _persistCompletionStats();

    final firstTryAccuracy = _initialQuizCount > 0
        ? ((_firstAttemptCorrect / _initialQuizCount) * 100).round()
        : 0;
    final overallAccuracy =
        _attemptCount > 0 ? ((_correctCount / _attemptCount) * 100).round() : 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.emoji_events, color: Colors.amber, size: 32),
            const SizedBox(width: 12),
            const Text('Quiz Complete!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$firstTryAccuracy%',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: firstTryAccuracy >= 80
                    ? Colors.green
                    : firstTryAccuracy >= 50
                        ? Colors.orange
                        : Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            const Text('First-attempt accuracy'),
            const SizedBox(height: 16),
            Text('Cards mastered: $_graduatedCount / $_initialQuizCount'),
            Text(
                'Overall answer accuracy: $overallAccuracy% ($_correctCount/$_attemptCount)'),
            Text('Correct on first try: $_firstAttemptCorrect'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isSetupMode = true;
                _quizWords = [];
              });
              _loadWordLists();
            },
            child: const Text('Done'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startQuiz();
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Future<void> _persistCompletionStats() async {
    if (_completionPersisted) return;
    if (_selectedListId == null || _initialQuizCount <= 0) return;

    _completionPersisted = true;
    try {
      await _databaseService.saveQuizResult(
        wordListId: _selectedListId!,
        score: _firstAttemptCorrect,
        totalQuestions: _initialQuizCount,
        quizType: _quizType.name,
      );
      final bool bumpedStreak = await _databaseService.logLearningActivity(
        reviewsCompletedDelta: _attemptCount,
      );
      
      if (bumpedStreak && mounted) {
        final streakData = await _databaseService.getLearningStreakStats();
        if (mounted) {
           await _showStreakAnimationOverlay(streakData['current'] ?? 0);
        }
      }
    } catch (_) {
      // Keep quiz UX uninterrupted if persistence fails.
    }
  }

  Future<void> _showStreakAnimationOverlay(int newStreak) async {
    await StreakAnimationOverlay.show(context, newStreak: newStreak);
  }

  void _resetQuiz() {
    setState(() {
      _isSetupMode = true;
      _quizWords = [];
      _currentIndex = 0;
      _showAnswer = false;
      _selectedAnswer = null;
      _isFlipped = false;
      _lastMultipleChoiceCorrect = false;
      _initialQuizCount = 0;
      _graduatedCount = 0;
      _firstAttemptCorrect = 0;
      _attemptCount = 0;
      _correctCount = 0;
      _attemptedWordIds = {};
      _learningStepByWordId = {};
    });
    _loadWordLists();
  }

  @override
  Widget build(BuildContext context) {
    if (_isSetupMode) {
      return _buildSetupScreen();
    } else {
      return _buildQuizScreen();
    }
  }

  Widget _buildSetupScreen() {
    final maxQuizSize = _selectedListId != null
        ? (_listWordCounts[_selectedListId]?['total'] ?? 10)
        : 10;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz Mode'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FoxMascotHeader(
                    title: 'Anki-Style Practice',
                    subtitle:
                        'Use Again / Hard / Good / Easy grading to build long-term retention.',
                    animation: FoxAnimation.jumpEast,
                  ),
                  const SizedBox(height: 24),
                  // Quiz Type Selection
                  const Text(
                    'Select Quiz Type',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                          child: _buildQuizTypeCard(
                        QuizType.flashcard,
                        'Flashcards',
                        'See word, recall translation',
                        Icons.style,
                      )),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildQuizTypeCard(
                        QuizType.multipleChoice,
                        'Multiple Choice',
                        'Choose correct translation',
                        Icons.list,
                      )),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildQuizTypeCard(
                        QuizType.reverse,
                        'Reverse',
                        'See translation, guess word',
                        Icons.swap_horiz,
                      )),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Quiz Size Slider
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Quiz Size',
                                style: TextStyle(fontWeight: FontWeight.w500)),
                            Text(
                              '$_quizSize words',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _quizSize
                              .toDouble()
                              .clamp(4, max(4, maxQuizSize.toDouble())),
                          min: 4,
                          max: max(4, maxQuizSize.toDouble()),
                          divisions: max(1, maxQuizSize - 4),
                          onChanged: (value) {
                            setState(() => _quizSize = value.round());
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Word List Selection
                  const Text(
                    'Select Word List',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  if (_wordLists.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border, width: 2),
                      ),
                      child: const Center(
                        child: Column(
                          children: [
                            Icon(Icons.school_outlined,
                                size: 48, color: AppColors.textSecondary),
                            SizedBox(height: 12),
                            Text('No word lists available',
                                style:
                                    TextStyle(color: AppColors.textSecondary)),
                            Text('Create a list and add words first!',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    )
                  else
                    ...(_wordLists.map((list) {
                      final listId = list['id'] as int;
                      final counts =
                          _listWordCounts[listId] ?? {'total': 0, 'due': 0};
                      final isSelected = _selectedListId == listId;

                      return GestureDetector(
                        onTap: () => setState(() => _selectedListId = listId),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withOpacity(0.2)
                                : Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.border,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Radio<int>(
                                value: listId,
                                groupValue: _selectedListId,
                                onChanged: (v) =>
                                    setState(() => _selectedListId = v),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      list['name'] ?? 'Unnamed',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: isSelected
                                            ? AppColors.primary
                                            : AppColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      '${counts['total']} words',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              if (counts['due']! > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.warning.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                    border:
                                        Border.all(color: AppColors.warning),
                                  ),
                                  child: Text(
                                    '${counts['due']} due',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.warning,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    })),

                  const SizedBox(height: 24),

                  // Start Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          _selectedListId == null ? null : () => _startQuiz(),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Quiz'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),

                  // Review Due Words button
                  if (_selectedListId != null &&
                      (_listWordCounts[_selectedListId]?['due'] ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _startQuiz(reviewOnly: true),
                          icon: const Icon(Icons.schedule,
                              color: AppColors.warning),
                          label: Text(
                            'Review ${_listWordCounts[_selectedListId]!['due']} Due Words',
                            style: const TextStyle(color: AppColors.warning),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: const BorderSide(color: AppColors.warning),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildQuizTypeCard(
      QuizType type, String title, String description, IconData icon) {
    final isSelected = _quizType == type;
    return GestureDetector(
      onTap: () => setState(() => _quizType = type),
      child: Container(
        height: 148,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.2)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: isSelected
                    ? AppColors.primaryLight
                    : AppColors.textSecondary),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? Colors.white70 : AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuizScreen() {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_quizWords.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quiz')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 80, color: Colors.green),
              const SizedBox(height: 16),
              const Text('All done!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _resetQuiz,
                child: const Text('Back to Setup'),
              ),
            ],
          ),
        ),
      );
    }

    final currentWord = _quizWords[_currentIndex];
    final progress = _calculateProgress();
    final progressPercent = (progress * 100).round();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _resetQuiz,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$progressPercent% Complete'),
            Text(
              '$_graduatedCount / $_initialQuizCount mastered',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: AppColors.surfaceHighlight,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.primaryLight),
              ),
            ),
          ),
        ),
      ),
      body: _quizType == QuizType.flashcard
          ? _buildFlashcardMode(currentWord)
          : _buildMultipleChoiceMode(currentWord),
    );
  }

  Widget _buildFlashcardMode(Map<String, dynamic> word) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Row(
            children: [
              _buildStatChip(Icons.repeat, '${_quizWords.length} in queue'),
              const SizedBox(width: 8),
              _buildStatChip(
                  Icons.check_circle_outline, '$_graduatedCount mastered'),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: GestureDetector(
              onTap: _flipCard,
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  final transform = Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateY(_animation.value * pi);

                  return Transform(
                    transform: transform,
                    alignment: Alignment.center,
                    child: _animation.value < 0.5
                        ? _buildCardFront(word)
                        : Transform(
                            transform: Matrix4.identity()..rotateY(pi),
                            alignment: Alignment.center,
                            child: _buildCardBack(word),
                          ),
                  );
                },
              ),
            ),
          ),
        ),
        if (_isFlipped)
          _buildFlashcardButtons()
        else
          const Padding(
            padding: EdgeInsets.only(bottom: 28),
            child: Text(
              'Tap the card to reveal the answer',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }

  Widget _buildCardFront(Map<String, dynamic> word) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceHighlight,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('Translate',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              word['word'] ?? '?',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 48),
          const Text('Tap to flip',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildCardBack(Map<String, dynamic> word) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight.withOpacity(0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              word['translation'] ?? '?',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (word['sentence_context'] != null &&
              (word['sentence_context'] as String).isNotEmpty) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '"${word['sentence_context']}"',
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFlashcardButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: ReviewRating.values
            .map((rating) => _buildReviewButton(
                  rating: rating,
                  onTap: () => _handleFlashcardRating(rating),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildReviewButton({
    required ReviewRating rating,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: compact ? null : 90,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 8,
          vertical: compact ? 10 : 12,
        ),
        decoration: BoxDecoration(
          color: rating.color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: rating.color, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(rating.icon, color: rating.color, size: compact ? 18 : 20),
            const SizedBox(height: 6),
            Text(
              rating.label,
              style: TextStyle(
                color: rating.color,
                fontWeight: FontWeight.w700,
                fontSize: compact ? 12 : 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.surfaceHighlight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultipleChoiceMode(Map<String, dynamic> word) {
    final correctAnswer =
        _quizType == QuizType.reverse ? word['word'] : word['translation'];
    final displayText =
        _quizType == QuizType.reverse ? word['translation'] : word['word'];
    final options = word['options'] as List<dynamic>? ?? [];
    final ratings = _lastMultipleChoiceCorrect
        ? [ReviewRating.hard, ReviewRating.good, ReviewRating.easy]
        : [ReviewRating.again];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        children: [
          Row(
            children: [
              _buildStatChip(Icons.repeat, '${_quizWords.length} in queue'),
              const SizedBox(width: 8),
              _buildStatChip(
                  Icons.check_circle_outline, '$_graduatedCount mastered'),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border, width: 2),
            ),
            child: Column(
              children: [
                Text(
                  _quizType == QuizType.reverse
                      ? 'What word means:'
                      : 'What is the translation?',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                Text(
                  displayText ?? '?',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: ListView.builder(
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options[index].toString();
                final isCorrect = option == correctAnswer;
                final isSelected = option == _selectedAnswer;

                Color bgColor = Theme.of(context).colorScheme.surface;
                Color borderColor = AppColors.surfaceHighlight;
                Color labelColor = AppColors.textPrimary;
                Color bulletColor = AppColors.surfaceHighlight;

                if (_showAnswer) {
                  if (isCorrect) {
                    bgColor = AppColors.success.withOpacity(0.2);
                    borderColor = AppColors.success;
                    labelColor = AppColors.success;
                    bulletColor = AppColors.success;
                  } else if (isSelected && !isCorrect) {
                    bgColor = AppColors.error.withOpacity(0.2);
                    borderColor = AppColors.error;
                    labelColor = AppColors.error;
                    bulletColor = AppColors.error;
                  }
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: _showAnswer
                        ? null
                        : () => _handleMultipleChoiceAnswer(option),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: borderColor,
                            width: _showAnswer && (isCorrect || isSelected)
                                ? 2
                                : 1),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: bulletColor,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                String.fromCharCode(65 + index),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              option,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: labelColor,
                              ),
                            ),
                          ),
                          if (_showAnswer && isCorrect)
                            const Icon(Icons.check_circle,
                                color: AppColors.success),
                          if (_showAnswer && isSelected && !isCorrect)
                            const Icon(Icons.cancel, color: AppColors.error),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_showAnswer)
            Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _lastMultipleChoiceCorrect
                        ? 'How difficult was this card?'
                        : 'Incorrect. Repeat soon.',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: ratings
                      .map(
                        (rating) => _buildReviewButton(
                          rating: rating,
                          compact: true,
                          onTap: () => _submitMultipleChoiceRating(rating),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
