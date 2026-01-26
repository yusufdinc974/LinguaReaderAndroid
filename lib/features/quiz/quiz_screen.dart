import 'package:flutter/material.dart';
import 'dart:math';
import '../../services/database_service.dart';
import '../../core/constants/app_colors.dart';

enum QuizType { flashcard, multipleChoice, reverse }

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> with SingleTickerProviderStateMixin {
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
  
  // Graduation system
  Map<int, int> _consecutiveCorrect = {}; // wordIndex -> consecutive correct count
  static const int graduationThreshold = 2;
  int _graduatedCount = 0;
  int _firstAttemptCorrect = 0;
  
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
      final dueWordSet = dueWords.map((w) => (w['word_lower'] as String).toLowerCase()).toSet();
      
      for (var list in lists) {
        final listId = list['id'] as int;
        final words = await _databaseService.getWordsInList(listId);
        final dueCount = words.where((w) => 
          dueWordSet.contains((w['word'] as String).toLowerCase())
        ).length;
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
        final dueWordSet = dueWords.map((w) => (w['word_lower'] as String).toLowerCase()).toSet();
        quizWords = words.where((w) => 
          dueWordSet.contains((w['word'] as String).toLowerCase())
        ).map((w) => Map<String, dynamic>.from(w)).toList();
      } else {
        quizWords = words.map((w) => Map<String, dynamic>.from(w)).toList();
      }
      
      if (quizWords.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(reviewOnly 
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
        final otherWords = _allListWords.where((w) => w['id'] != word['id']).toList();
        otherWords.shuffle();
        final options = otherWords.take(3).toList();
        
        List<dynamic> optionList;
        if (_quizType == QuizType.reverse) {
          optionList = [word['word'], ...options.map((o) => o['word'])];
        } else {
          optionList = [word['translation'], ...options.map((o) => o['translation'])];
        }
        optionList.shuffle();
        word['options'] = optionList;
      }
      
      if (mounted) {
        setState(() {
          _quizWords = quizWords;
          _currentIndex = 0;
          _isSetupMode = false;
          _isLoading = false;
          _graduatedCount = 0;
          _firstAttemptCorrect = 0;
          _consecutiveCorrect = {};
          _isFlipped = false;
          _showAnswer = false;
          _selectedAnswer = null;
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

  Future<void> _handleFlashcardGrade(int grade) async {
    // grade: 1 = didn't know, 2 = not sure, 3 = knew it
    final wordIndex = _currentIndex;
    final currentWord = _quizWords[wordIndex];
    final isFirstAttempt = !_consecutiveCorrect.containsKey(wordIndex);
    
    if (grade == 3) {
      // Knew it - increase consecutive count
      _consecutiveCorrect[wordIndex] = (_consecutiveCorrect[wordIndex] ?? 0) + 1;
      
      if (isFirstAttempt) {
        _firstAttemptCorrect++;
      }
      
      if (_consecutiveCorrect[wordIndex]! >= graduationThreshold) {
        // Graduated!
        _graduatedCount++;
        await _updateSRS(currentWord, grade);
        _moveToNext(graduated: true);
        return;
      }
    } else {
      // Didn't know or not sure - reset consecutive
      _consecutiveCorrect[wordIndex] = 0;
    }
    
    await _updateSRS(currentWord, grade);
    _moveToNext(graduated: false);
  }

  void _handleMultipleChoiceAnswer(String answer) {
    final currentWord = _quizWords[_currentIndex];
    final correctAnswer = _quizType == QuizType.reverse 
      ? currentWord['word'] 
      : currentWord['translation'];
    
    setState(() {
      _selectedAnswer = answer;
      _showAnswer = true;
    });
    
    // Track first attempt
    final isFirstAttempt = !_consecutiveCorrect.containsKey(_currentIndex);
    if (answer == correctAnswer && isFirstAttempt) {
      _firstAttemptCorrect++;
    }
    
    // Grade: correct = 3, incorrect = 1
    final grade = answer == correctAnswer ? 3 : 1;
    
    // Store grade for when user taps "Continue"
    _quizWords[_currentIndex]['lastGrade'] = grade;
  }

  Future<void> _continueAfterAnswer() async {
    final currentWord = _quizWords[_currentIndex];
    final grade = currentWord['lastGrade'] ?? 1;
    
    if (grade == 3) {
      _consecutiveCorrect[_currentIndex] = 
        (_consecutiveCorrect[_currentIndex] ?? 0) + 1;
      
      if (_consecutiveCorrect[_currentIndex]! >= graduationThreshold) {
        _graduatedCount++;
        await _updateSRS(currentWord, grade);
        _moveToNext(graduated: true);
        return;
      }
    } else {
      _consecutiveCorrect[_currentIndex] = 0;
    }
    
    await _updateSRS(currentWord, grade);
    _moveToNext(graduated: false);
  }

  void _moveToNext({required bool graduated}) {
    if (graduated) {
      // Remove from quiz
      _quizWords.removeAt(_currentIndex);
      if (_currentIndex >= _quizWords.length) {
        _currentIndex = 0;
      }
    } else {
      // Move to end of queue
      final word = _quizWords.removeAt(_currentIndex);
      _quizWords.add(word);
      // Keep _currentIndex same (now pointing to next word)
      if (_currentIndex >= _quizWords.length) {
        _currentIndex = 0;
      }
    }
    
    setState(() {
      _isFlipped = false;
      _showAnswer = false;
      _selectedAnswer = null;
      _controller.reset();
    });
    
    // Check if quiz complete
    if (_quizWords.isEmpty) {
      _showCompletionDialog();
    }
  }

  Future<void> _updateSRS(Map<String, dynamic> word, int grade) async {
    // Find the familiarity record by word_lower
    final wordLower = (word['word'] as String).toLowerCase();
    final dueWords = await _databaseService.getDueWords();
    final familiarity = dueWords.firstWhere(
      (w) => (w['word_lower'] as String).toLowerCase() == wordLower,
      orElse: () => {},
    );
    
    if (familiarity.isNotEmpty && familiarity['id'] != null) {
      // Map our 1-3 grade to SM-2's 0-5 scale
      int sm2Grade;
      if (grade == 1) sm2Grade = 0; // Didn't know -> forgot
      else if (grade == 2) sm2Grade = 3; // Not sure -> hard
      else sm2Grade = 5; // Knew it -> easy
      
      await _databaseService.updateWordFamiliarity(familiarity['id'], sm2Grade);
    }
  }

  void _showCompletionDialog() {
    final totalWords = _graduatedCount;
    final accuracy = totalWords > 0 
      ? ((_firstAttemptCorrect / totalWords) * 100).round() 
      : 0;
    
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
              '$accuracy%',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: accuracy >= 80 ? Colors.green : 
                       accuracy >= 50 ? Colors.orange : Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Text('First-attempt accuracy'),
            const SizedBox(height: 16),
            Text('Words mastered: $totalWords'),
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

  void _resetQuiz() {
    setState(() {
      _isSetupMode = true;
      _quizWords = [];
      _currentIndex = 0;
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
                // Quiz Type Selection
                const Text(
                  'Select Quiz Type',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildQuizTypeCard(
                      QuizType.flashcard, 
                      'Flashcards', 
                      'See word, recall translation',
                      Icons.style,
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: _buildQuizTypeCard(
                      QuizType.multipleChoice, 
                      'Multiple Choice', 
                      'Choose correct translation',
                      Icons.list,
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: _buildQuizTypeCard(
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
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Quiz Size', style: TextStyle(fontWeight: FontWeight.w500)),
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
                        value: _quizSize.toDouble().clamp(4, max(4, maxQuizSize.toDouble())),
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
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Column(
                        children: [
                          Icon(Icons.school_outlined, size: 48, color: AppColors.textSecondary),
                          SizedBox(height: 12),
                          Text('No word lists available', style: TextStyle(color: AppColors.textSecondary)),
                          Text('Create a list and add words first!', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  )
                else
                  ...(_wordLists.map((list) {
                    final listId = list['id'] as int;
                    final counts = _listWordCounts[listId] ?? {'total': 0, 'due': 0};
                    final isSelected = _selectedListId == listId;
                    
                    return GestureDetector(
                      onTap: () => setState(() => _selectedListId = listId),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary.withOpacity(0.1) : Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? AppColors.primary : Theme.of(context).colorScheme.outline.withOpacity(0.2),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Radio<int>(
                              value: listId,
                              groupValue: _selectedListId,
                              onChanged: (v) => setState(() => _selectedListId = v),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    list['name'] ?? 'Unnamed',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    '${counts['total']} words',
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            if (counts['due']! > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${counts['due']} due',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange,
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
                    onPressed: _selectedListId == null ? null : () => _startQuiz(),
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
                        icon: const Icon(Icons.schedule, color: Colors.orange),
                        label: Text(
                          'Review ${_listWordCounts[_selectedListId]!['due']} Due Words',
                          style: const TextStyle(color: Colors.orange),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: Colors.orange),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
    );
  }

  Widget _buildQuizTypeCard(QuizType type, String title, String description, IconData icon) {
    final isSelected = _quizType == type;
    return GestureDetector(
      onTap: () => setState(() => _quizType = type),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.1) : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : Theme.of(context).colorScheme.outline.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? AppColors.primary : AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
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
              const Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
              const SizedBox(height: 16),
              const Text('All done!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
    final progress = _graduatedCount / (_graduatedCount + _quizWords.length);
    
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _resetQuiz,
        ),
        title: Text('${_graduatedCount} / ${_graduatedCount + _quizWords.length} mastered'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.surfaceHighlight,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
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
        if (_isFlipped) _buildFlashcardButtons() 
        else const SizedBox(height: 120),
      ],
    );
  }

  Widget _buildCardFront(Map<String, dynamic> word) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Translate this:', style: TextStyle(color: AppColors.textSecondary)),
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
          const Text('Tap to flip', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildCardBack(Map<String, dynamic> word) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 2),
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
                color: AppColors.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (word['sentence_context'] != null && (word['sentence_context'] as String).isNotEmpty) ...[
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
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildGradeButton("Didn't know", Colors.red, 1, Icons.close),
          _buildGradeButton("Not sure", Colors.orange, 2, Icons.help_outline),
          _buildGradeButton("I knew it", Colors.green, 3, Icons.check),
        ],
      ),
    );
  }

  Widget _buildGradeButton(String label, Color color, int grade, IconData icon) {
    return GestureDetector(
      onTap: () => _handleFlashcardGrade(grade),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildMultipleChoiceMode(Map<String, dynamic> word) {
    final correctAnswer = _quizType == QuizType.reverse 
      ? word['word'] 
      : word['translation'];
    final displayText = _quizType == QuizType.reverse 
      ? word['translation'] 
      : word['word'];
    final options = word['options'] as List<dynamic>? ?? [];
    
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Question
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                Text(
                  _quizType == QuizType.reverse ? 'What word means:' : 'What is the translation?',
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
          
          const SizedBox(height: 24),
          
          // Options
          Expanded(
            child: ListView.builder(
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options[index].toString();
                final isCorrect = option == correctAnswer;
                final isSelected = option == _selectedAnswer;
                
                Color bgColor = AppColors.surface;
                Color borderColor = AppColors.surfaceHighlight;
                
                if (_showAnswer) {
                  if (isCorrect) {
                    bgColor = Colors.green.withOpacity(0.2);
                    borderColor = Colors.green;
                  } else if (isSelected && !isCorrect) {
                    bgColor = Colors.red.withOpacity(0.2);
                    borderColor = Colors.red;
                  }
                }
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: _showAnswer ? null : () => _handleMultipleChoiceAnswer(option),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor, width: _showAnswer && (isCorrect || isSelected) ? 2 : 1),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _showAnswer && isCorrect 
                                ? Colors.green 
                                : (_showAnswer && isSelected && !isCorrect ? Colors.red : AppColors.surfaceHighlight),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                String.fromCharCode(65 + index),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _showAnswer && (isCorrect || isSelected) ? Colors.white : AppColors.textPrimary,
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
                                color: _showAnswer && isCorrect ? Colors.green : AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (_showAnswer && isCorrect)
                            const Icon(Icons.check_circle, color: Colors.green),
                          if (_showAnswer && isSelected && !isCorrect)
                            const Icon(Icons.cancel, color: Colors.red),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          if (_showAnswer)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _continueAfterAnswer,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: AppColors.primary,
                ),
                child: Text(
                  _selectedAnswer == correctAnswer ? 'Continue' : 'Try Again Later',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
