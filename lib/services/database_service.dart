import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'linguareader.db');
    return await openDatabase(
      path,
      version: 6,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS word_lists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        color TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS words (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word TEXT NOT NULL,
        translation TEXT NOT NULL,
        source_language TEXT NOT NULL,
        target_language TEXT NOT NULL,
        sentence_context TEXT,
        pdf_name TEXT,
        note TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        mastery_level INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS word_list_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_list_id INTEGER NOT NULL,
        word_id INTEGER NOT NULL,
        added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (word_list_id) REFERENCES word_lists(id) ON DELETE CASCADE,
        FOREIGN KEY (word_id) REFERENCES words(id) ON DELETE CASCADE,
        UNIQUE(word_list_id, word_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS quiz_results (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_list_id INTEGER NOT NULL,
        score INTEGER NOT NULL,
        total_questions INTEGER NOT NULL,
        quiz_type TEXT NOT NULL,
        completed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (word_list_id) REFERENCES word_lists(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS recent_pdfs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        path TEXT NOT NULL UNIQUE,
        last_opened TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS word_familiarity (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_lower TEXT NOT NULL UNIQUE,
        familiarity_level INTEGER DEFAULT 1,
        translation TEXT,
        easiness_factor REAL DEFAULT 2.5,
        interval INTEGER DEFAULT 0,
        repetitions INTEGER DEFAULT 0,
        next_review_date TEXT,
        last_review_date TEXT,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_profile (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        display_name TEXT NOT NULL,
        native_language TEXT,
        target_language TEXT,
        learning_goal TEXT NOT NULL,
        discovery_source TEXT NOT NULL,
        daily_goal_words INTEGER DEFAULT 10,
        onboarding_completed INTEGER DEFAULT 1,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS learning_activity (
        activity_date TEXT PRIMARY KEY,
        words_learned INTEGER DEFAULT 0,
        reviews_completed INTEGER DEFAULT 0,
        reading_minutes INTEGER DEFAULT 0,
        translations_looked_up INTEGER DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_word_familiarity_next_review
      ON word_familiarity(next_review_date)
    ''');

    // AI Language Partner tables
    await _createAiPartnerTables(db);

    // Default Settings
    await db.insert('user_settings', {'key': 'target_language', 'value': 'tr'},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('user_settings', {'key': 'theme', 'value': 'dark'},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _createAiPartnerTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        language TEXT DEFAULT 'en',
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        sender TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS correction_metadata (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id INTEGER,
        session_id INTEGER,
        original_text TEXT NOT NULL,
        corrected_text TEXT NOT NULL,
        explanation TEXT NOT NULL,
        category TEXT DEFAULT 'grammar',
        user_note TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (message_id) REFERENCES chat_messages(id) ON DELETE SET NULL,
        FOREIGN KEY (session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_corrections_created_at ON correction_metadata(created_at)'
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_corrections_category ON correction_metadata(category)'
    );
  }

  // --- Settings ---
  Future<String?> getSetting(String key) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'user_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (maps.isNotEmpty) {
      return maps.first['value'] as String;
    }
    return null;
  }

  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'user_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add color column to word_lists if missing
      // Check if column exists first (some sqlite versions don't support ADD COLUMN IF NOT EXISTS)
      try {
        await db.execute('ALTER TABLE word_lists ADD COLUMN color TEXT');
      } catch (e) {
        // Ignore if column already exists
        print("Migration error (might be okay if column exists): $e");
      }
    }
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE words ADD COLUMN note TEXT');
      } catch (e) {
        // Ignore if column already exists
        print("Migration error (might be okay if column exists): $e");
      }
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_profile (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          display_name TEXT NOT NULL,
          native_language TEXT,
          target_language TEXT,
          learning_goal TEXT NOT NULL,
          discovery_source TEXT NOT NULL,
          daily_goal_words INTEGER DEFAULT 10,
          onboarding_completed INTEGER DEFAULT 1,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS learning_activity (
          activity_date TEXT PRIMARY KEY,
          words_learned INTEGER DEFAULT 0,
          reviews_completed INTEGER DEFAULT 0,
          reading_minutes INTEGER DEFAULT 0,
          translations_looked_up INTEGER DEFAULT 0,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_word_familiarity_next_review
        ON word_familiarity(next_review_date)
      ''');
    }
    if (oldVersion < 5) {
      try {
        await db.execute('ALTER TABLE learning_activity ADD COLUMN translations_looked_up INTEGER DEFAULT 0');
      } catch (e) {
        print("Migration error config 5: $e");
      }
    }
    if (oldVersion < 6) {
      await _createAiPartnerTables(db);
    }
  }

  String _dayKey(DateTime date) => date.toIso8601String().split('T').first;

  // --- Profile & Retention ---
  Future<Map<String, dynamic>?> getUserProfile() async {
    final db = await database;
    final rows = await db.query(
      'user_profile',
      orderBy: 'updated_at DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<bool> isUserProfileComplete() async {
    final profile = await getUserProfile();
    if (profile == null) return false;
    return (profile['onboarding_completed'] as int? ?? 0) == 1;
  }

  Future<void> saveUserProfile({
    required String displayName,
    required String learningGoal,
    required String discoverySource,
    String? nativeLanguage,
    String? targetLanguage,
    int dailyGoalWords = 10,
    bool onboardingCompleted = true,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final existing = await getUserProfile();

    final values = <String, dynamic>{
      'display_name': displayName.trim(),
      'native_language': nativeLanguage?.trim(),
      'target_language': targetLanguage?.trim(),
      'learning_goal': learningGoal.trim(),
      'discovery_source': discoverySource.trim(),
      'daily_goal_words': dailyGoalWords < 1 ? 1 : dailyGoalWords,
      'onboarding_completed': onboardingCompleted ? 1 : 0,
      'updated_at': now,
    };

    if (existing == null) {
      values['created_at'] = now;
      await db.insert('user_profile', values);
    } else {
      await db.update(
        'user_profile',
        values,
        where: 'id = ?',
        whereArgs: [existing['id']],
      );
    }
  }

  Future<bool> logLearningActivity({
    int wordsLearnedDelta = 0,
    int reviewsCompletedDelta = 0,
    int readingMinutesDelta = 0,
    int translationsLookedUpDelta = 0,
  }) async {
    if (wordsLearnedDelta == 0 &&
        reviewsCompletedDelta == 0 &&
        readingMinutesDelta == 0 &&
        translationsLookedUpDelta == 0) {
      return false;
    }

    final db = await database;
    final day = _dayKey(DateTime.now());
    final now = DateTime.now().toIso8601String();

    final existing = await db.query(
      'learning_activity',
      where: 'activity_date = ?',
      whereArgs: [day],
      limit: 1,
    );

    if (existing.isEmpty) {
      // First activity of the day -> Streak increases!
      await db.insert('learning_activity', {
        'activity_date': day,
        'words_learned': wordsLearnedDelta < 0 ? 0 : wordsLearnedDelta,
        'reviews_completed':
            reviewsCompletedDelta < 0 ? 0 : reviewsCompletedDelta,
        'reading_minutes': readingMinutesDelta < 0 ? 0 : readingMinutesDelta,
        'translations_looked_up': translationsLookedUpDelta < 0 ? 0 : translationsLookedUpDelta,
        'created_at': now,
        'updated_at': now,
      });
      return true;
    }

    final row = existing.first;
    await db.update(
      'learning_activity',
      {
        'words_learned':
            (row['words_learned'] as int? ?? 0) + wordsLearnedDelta,
        'reviews_completed':
            (row['reviews_completed'] as int? ?? 0) + reviewsCompletedDelta,
        'reading_minutes':
            (row['reading_minutes'] as int? ?? 0) + readingMinutesDelta,
        'translations_looked_up':
            (row['translations_looked_up'] as int? ?? 0) + translationsLookedUpDelta,
        'updated_at': now,
      },
      where: 'activity_date = ?',
      whereArgs: [day],
    );
    
    // Already existed, so streak was already bumped earlier today
    return false;
  }

  Future<Map<String, int>> getTodayLearningActivity() async {
    final db = await database;
    final day = _dayKey(DateTime.now());
    final rows = await db.query(
      'learning_activity',
      where: 'activity_date = ?',
      whereArgs: [day],
      limit: 1,
    );
    if (rows.isEmpty) {
      return {
        'words_learned': 0,
        'reviews_completed': 0,
        'reading_minutes': 0,
        'translations_looked_up': 0,
      };
    }
    final row = rows.first;
    return {
      'words_learned': row['words_learned'] as int? ?? 0,
      'reviews_completed': row['reviews_completed'] as int? ?? 0,
      'reading_minutes': row['reading_minutes'] as int? ?? 0,
      'translations_looked_up': row['translations_looked_up'] as int? ?? 0,
    };
  }

  Future<Map<String, int>> getLearningStreakStats() async {
    final db = await database;
    final rows = await db.query(
      'learning_activity',
      columns: [
        'activity_date',
        'words_learned',
        'reviews_completed',
        'reading_minutes'
      ],
      orderBy: 'activity_date ASC',
    );

    final activeDays = rows
        .where((row) {
          final words = row['words_learned'] as int? ?? 0;
          final reviews = row['reviews_completed'] as int? ?? 0;
          final reading = row['reading_minutes'] as int? ?? 0;
          return words > 0 || reviews > 0 || reading > 0;
        })
        .map((row) => row['activity_date'] as String)
        .toSet();

    if (activeDays.isEmpty) {
      return {'current': 0, 'longest': 0};
    }

    final sortedDates = activeDays.toList()..sort();
    int longest = 1;
    int run = 1;

    for (int i = 1; i < sortedDates.length; i++) {
      final prev = DateTime.parse(sortedDates[i - 1]);
      final curr = DateTime.parse(sortedDates[i]);
      if (curr.difference(prev).inDays == 1) {
        run += 1;
      } else {
        run = 1;
      }
      if (run > longest) longest = run;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime? anchor;
    if (activeDays.contains(_dayKey(today))) {
      anchor = today;
    } else {
      final yesterday = today.subtract(const Duration(days: 1));
      if (activeDays.contains(_dayKey(yesterday))) {
        anchor = yesterday;
      }
    }

    int current = 0;
    if (anchor != null) {
      var cursor = anchor;
      while (activeDays.contains(_dayKey(cursor))) {
        current += 1;
        cursor = cursor.subtract(const Duration(days: 1));
      }
    }

    return {'current': current, 'longest': longest};
  }

  Future<Map<String, dynamic>> getRetentionOverview() async {
    final profile = await getUserProfile();
    final today = await getTodayLearningActivity();
    final streak = await getLearningStreakStats();
    final goal = (profile?['daily_goal_words'] as int?) ?? 10;
    final wordsLearned = today['words_learned'] ?? 0;
    final goalProgress =
        goal <= 0 ? 0.0 : (wordsLearned / goal).clamp(0.0, 1.0);

    return {
      'daily_goal_words': goal,
      'today_words_learned': wordsLearned,
      'today_reviews_completed': today['reviews_completed'] ?? 0,
      'today_reading_minutes': today['reading_minutes'] ?? 0,
      'goal_progress': goalProgress,
      'streak_current': streak['current'] ?? 0,
      'streak_longest': streak['longest'] ?? 0,
    };
  }

  Future<void> saveQuizResult({
    required int wordListId,
    required int score,
    required int totalQuestions,
    required String quizType,
  }) async {
    final db = await database;
    await db.insert('quiz_results', {
      'word_list_id': wordListId,
      'score': score < 0 ? 0 : score,
      'total_questions': totalQuestions < 0 ? 0 : totalQuestions,
      'quiz_type': quizType,
      'completed_at': DateTime.now().toIso8601String(),
    });
  }

  // --- Word Lists ---
  Future<List<Map<String, dynamic>>> getWordLists() async {
    final db = await database;
    return await db.query('word_lists', orderBy: 'created_at DESC');
  }

  Future<int> createWordList(String name, String description,
      {String? color}) async {
    final db = await database;
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError('Word list name cannot be empty');
    }

    final existing = await db.rawQuery(
      'SELECT id FROM word_lists WHERE LOWER(TRIM(name)) = ? LIMIT 1',
      [normalizedName.toLowerCase()],
    );
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }
    return await db.insert('word_lists', {
      'name': normalizedName,
      'description': description,
      'color': color ?? '0xFF2196F3', // Default Blue
    });
  }

  Future<void> deleteWordList(int id) async {
    final db = await database;

    // 2. Delete words specific to this list (orphans)
    // Desktop logic: Deletes words that are ONLY in this list (orphaned after list deletion)
    // To do this safely, we first delete the list items, then check for orphans.

    await db
        .delete('word_list_items', where: 'word_list_id = ?', whereArgs: [id]);

    // 3. Find and delete orphaned words
    await db.rawDelete('''
      DELETE FROM words 
      WHERE id IN (
        SELECT w.id FROM words w 
        LEFT JOIN word_list_items wli ON w.id = wli.word_id 
        WHERE wli.word_id IS NULL
      )
    ''');

    // 4. Cleanup familiarity table for deleted words
    // Note: Since we don't have a direct FK from familiarity to words in the current schema (it uses word_lower),
    // we should ideally clean this up. Desktop regex removes special chars, we will do a simpler check.
    // Ideally, familiarity should be cleaned up if the word doesn't exist in 'words' table anymore?
    // Or we can leave it for history. Desktop deletes it.

    await db.rawDelete('''
      DELETE FROM word_familiarity 
      WHERE word_lower NOT IN (
          SELECT LOWER(word) FROM words
      )
    ''');

    // 5. Delete the list
    await db.delete('word_lists', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getWordsWithColors(
      {List<int>? listIds}) async {
    final db = await database;

    // If listIds is explicitly empty list (not null), return nothing
    if (listIds != null && listIds.isEmpty) {
      return [];
    }

    String query = '''
      SELECT w.word, wl.color 
      FROM words w
      INNER JOIN word_list_items wli ON w.id = wli.word_id
      INNER JOIN word_lists wl ON wl.id = wli.word_list_id
    ''';

    if (listIds != null && listIds.isNotEmpty) {
      final ids = listIds.join(',');
      query += ' WHERE wl.id IN ($ids)';
    }

    // Order by most recently added list to prioritize colors
    query += ' ORDER BY wl.created_at DESC';

    return await db.rawQuery(query);
  }

  // --- Words ---
  Future<List<Map<String, dynamic>>> getWordsInList(int listId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT w.* 
      FROM words w
      INNER JOIN word_list_items wli ON w.id = wli.word_id
      WHERE wli.word_list_id = ?
      ORDER BY wli.added_at DESC
    ''', [listId]);
  }

  Future<int> addWord({
    required int listId,
    required String word,
    required String translation,
    required String context,
    String? pdfName,
    String? note,
  }) async {
    final db = await database;
    // 0. Get target language
    final targetLang = await getSetting('target_language') ?? 'tr';

    // 1. Insert into words table
    final wordId = await db.insert('words', {
      'word': word,
      'translation': translation,
      'source_language': 'auto',
      'target_language': targetLang,
      'sentence_context': context,
      'pdf_name': pdfName,
      'note': note,
    });

    // 2. Link to list
    await db.insert('word_list_items', {
      'word_list_id': listId,
      'word_id': wordId,
    });

    // 3. Initialize SRS (Familiarity)
    await db.insert(
        'word_familiarity',
        {
          'word_lower': word.toLowerCase(),
          'translation': translation,
          'next_review_date': DateTime.now()
              .toIso8601String(), // Start review immediately or next day
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);

    await logLearningActivity(wordsLearnedDelta: 1);

    return wordId;
  }

  Future<String?> getLatestNoteForWord(String word) async {
    final db = await database;
    final rows = await db.query(
      'words',
      columns: ['note'],
      where: 'LOWER(word) = ? AND note IS NOT NULL AND TRIM(note) != ""',
      whereArgs: [word.toLowerCase()],
      orderBy: 'created_at DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['note'] as String?;
  }

  Future<int> updateNoteForWord(String word, String note) async {
    final db = await database;
    return db.update(
      'words',
      {'note': note},
      where: 'LOWER(word) = ?',
      whereArgs: [word.toLowerCase()],
    );
  }

  Future<void> deleteWord(int id) async {
    final db = await database;

    // Get word text for familiarity cleanup
    final wordMaps = await db.query('words',
        columns: ['word'], where: 'id = ?', whereArgs: [id]);
    if (wordMaps.isNotEmpty) {
      final wordLower = (wordMaps.first['word'] as String).toLowerCase();
      await db.delete('word_familiarity',
          where: 'word_lower = ?', whereArgs: [wordLower]);
    }

    await db.delete('words', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> removeWordFromList(int listId, int wordId) async {
    final db = await database;

    // Remove link
    await db.delete('word_list_items',
        where: 'word_list_id = ? AND word_id = ?', whereArgs: [listId, wordId]);

    // Check if word is now an orphan (not in any list)
    final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM word_list_items WHERE word_id = ?', [wordId]));

    if (count == 0) {
      // It's an orphan, delete it fully
      await deleteWord(wordId);
    }
  }

  // --- Recent PDFs ---
  Future<List<Map<String, dynamic>>> getRecentPdfs() async {
    final db = await database;
    return await db.query('recent_pdfs', orderBy: 'last_opened DESC', limit: 5);
  }

  Future<int> getPdfCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM recent_pdfs');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> addRecentPdf(String name, String path) async {
    final db = await database;
    await db.insert(
        'recent_pdfs',
        {
          'name': name,
          'path': path,
          'last_opened': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // --- Stats ---
  Future<int> getWordsToReviewCount() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM word_familiarity WHERE next_review_date <= ?',
        [now]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Map<String, int>> getFamiliarityStats() async {
    final db = await database;
    // 1=Unknown, 2=Seen, 3=Learning, 4=Familiar, 5=Mastered
    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT familiarity_level, COUNT(*) as count 
      FROM word_familiarity 
      GROUP BY familiarity_level
    ''');

    final stats = <String, int>{
      'Unknown': 0,
      'Seen': 0,
      'Learning': 0,
      'Mastered':
          0, // Combining Familiar and Mastered for simplicity or keeping separate
    };

    for (var row in result) {
      final level = row['familiarity_level'] as int;
      final count = row['count'] as int;
      if (level <= 1)
        stats['Unknown'] = (stats['Unknown'] ?? 0) + count;
      else if (level == 2)
        stats['Seen'] = (stats['Seen'] ?? 0) + count;
      else if (level == 3)
        stats['Learning'] = (stats['Learning'] ?? 0) + count;
      else
        stats['Mastered'] = (stats['Mastered'] ?? 0) + count;
    }
    return stats;
  }

  Future<List<Map<String, dynamic>>> getUpcomingReviews() async {
    final db = await database;
    final now = DateTime.now();

    // Get all future reviews
    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT next_review_date 
      FROM word_familiarity 
      WHERE next_review_date IS NOT NULL
    ''');

    // Buckets matching Desktop logic
    final buckets = <String, int>{
      'Overdue': 0,
      'Today': 0,
      'Soon (1-3d)': 0,
      'Later (4-7d)': 0,
      'Mastered (7+d)': 0,
    };

    final todayDate = DateTime(now.year, now.month, now.day);

    for (var row in result) {
      final dateStr = row['next_review_date'] as String;
      final date = DateTime.parse(dateStr);
      final reviewDate = DateTime(date.year, date.month, date.day);

      final diff = reviewDate.difference(todayDate).inDays;

      if (diff < 0) {
        buckets['Overdue'] = (buckets['Overdue'] ?? 0) + 1;
        // Also counts as due today effectively for review purposes, but for chart we split
      } else if (diff == 0) {
        buckets['Today'] = (buckets['Today'] ?? 0) + 1;
      } else if (diff <= 3) {
        buckets['Soon (1-3d)'] = (buckets['Soon (1-3d)'] ?? 0) + 1;
      } else if (diff <= 7) {
        buckets['Later (4-7d)'] = (buckets['Later (4-7d)'] ?? 0) + 1;
      } else {
        buckets['Mastered (7+d)'] = (buckets['Mastered (7+d)'] ?? 0) + 1;
      }
    }

    // Format for chart: List of maps
    return buckets.entries
        .map((e) => {'review_day': e.key, 'count': e.value})
        .toList();
  }

  Future<List<Map<String, dynamic>>> getDueWords() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return await db.rawQuery('''
      SELECT wf.*, w.translation as original_translation, w.sentence_context
      FROM word_familiarity wf
      LEFT JOIN words w ON LOWER(w.word) = LOWER(wf.word_lower)
      WHERE wf.next_review_date <= ?
      ORDER BY wf.next_review_date ASC
      LIMIT 20
    ''', [now]);
  }

  Future<Map<String, dynamic>> getQuizPerformanceStats() async {
    final db = await database;

    final summaryRows = await db.rawQuery('''
      SELECT
        COUNT(*) as total_sessions,
        AVG(CASE WHEN total_questions > 0 THEN (score * 100.0 / total_questions) END) as avg_accuracy,
        MAX(CASE WHEN total_questions > 0 THEN (score * 100.0 / total_questions) END) as best_accuracy
      FROM quiz_results
    ''');

    final summary =
        summaryRows.isNotEmpty ? summaryRows.first : <String, Object?>{};

    final lastRows = await db.rawQuery('''
      SELECT score, total_questions, quiz_type, completed_at
      FROM quiz_results
      ORDER BY completed_at DESC
      LIMIT 1
    ''');
    final last = lastRows.isNotEmpty ? lastRows.first : <String, Object?>{};

    final totalSessions = (summary['total_sessions'] as int?) ?? 0;
    final avgAccuracy = (summary['avg_accuracy'] as num?)?.toDouble() ?? 0;
    final bestAccuracy = (summary['best_accuracy'] as num?)?.toDouble() ?? 0;

    return {
      'total_sessions': totalSessions,
      'avg_accuracy': avgAccuracy,
      'best_accuracy': bestAccuracy,
      'last_score': (last['score'] as int?) ?? 0,
      'last_total_questions': (last['total_questions'] as int?) ?? 0,
      'last_quiz_type': (last['quiz_type'] as String?) ?? '',
      'last_completed_at': (last['completed_at'] as String?) ?? '',
    };
  }

  Future<List<Map<String, dynamic>>> getDailyQuizActivity(
      {int days = 7}) async {
    final db = await database;
    final safeDays = days < 1 ? 1 : days;
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: safeDays - 1));
    final startIso = startDate.toIso8601String();

    final rows = await db.rawQuery('''
      SELECT
        substr(completed_at, 1, 10) as day,
        COUNT(*) as sessions,
        AVG(CASE WHEN total_questions > 0 THEN (score * 100.0 / total_questions) END) as avg_accuracy
      FROM quiz_results
      WHERE completed_at >= ?
      GROUP BY day
      ORDER BY day ASC
    ''', [startIso]);

    final byDay = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final day = (row['day'] as String?) ?? '';
      if (day.isEmpty) continue;
      byDay[day] = {
        'sessions': (row['sessions'] as int?) ?? 0,
        'avg_accuracy': (row['avg_accuracy'] as num?)?.toDouble() ?? 0,
      };
    }

    final output = <Map<String, dynamic>>[];
    for (var i = 0; i < safeDays; i++) {
      final date = startDate.add(Duration(days: i));
      final dayKey = date.toIso8601String().split('T').first;
      final item = byDay[dayKey];
      output.add({
        'day': dayKey,
        'sessions': item?['sessions'] ?? 0,
        'avg_accuracy': item?['avg_accuracy'] ?? 0.0,
      });
    }

    return output;
  }

  Future<int?> getOrCreateWordFamiliarityId(String wordLower,
      {String? translation}) async {
    final db = await database;
    final normalizedWord = wordLower.toLowerCase();

    final existing = await db.query(
      'word_familiarity',
      columns: ['id'],
      where: 'word_lower = ?',
      whereArgs: [normalizedWord],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }

    await db.insert(
      'word_familiarity',
      {
        'word_lower': normalizedWord,
        'translation': translation,
        'next_review_date': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    final created = await db.query(
      'word_familiarity',
      columns: ['id'],
      where: 'word_lower = ?',
      whereArgs: [normalizedWord],
      limit: 1,
    );

    if (created.isEmpty) return null;
    return created.first['id'] as int;
  }

  Future<void> updateWordFamiliarity(int id, int quality) async {
    // Quality: 0=Forgot, 3=Hard, 4=Good, 5=Easy
    final db = await database;

    // Get current state
    final List<Map<String, dynamic>> maps = await db.query(
      'word_familiarity',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return;

    final current = maps.first;
    double easeFactor = current['easiness_factor'] as double;
    int interval = current['interval'] as int;
    int repetitions = current['repetitions'] as int;

    // SM-2 Algorithm Implementation
    if (quality >= 3) {
      if (repetitions == 0) {
        interval = 1;
      } else if (repetitions == 1) {
        interval = 6;
      } else {
        interval = (interval * easeFactor).round();
      }
      repetitions++;
    } else {
      repetitions = 0;
      interval = 1;
    }

    easeFactor =
        easeFactor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
    if (easeFactor < 1.3) easeFactor = 1.3;

    final nextReview = DateTime.now().add(Duration(days: interval));

    await db.update(
      'word_familiarity',
      {
        'easiness_factor': easeFactor,
        'interval': interval,
        'repetitions': repetitions,
        'next_review_date': nextReview.toIso8601String(),
        'last_review_date': DateTime.now().toIso8601String(),
        'familiarity_level': quality // simplified level tracking
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    // Also update words table mastery if linked
    // We match by word string since there isn't a direct ID link in the schema shown earlier (word_lower vs word text)
    // Ideally we should fix the schema to have a foreign key, but for now we look up by word
    final wordLower = current['word_lower'] as String;

    // Update mastery_level in words table (0-5 scale)
    await db.rawUpdate('''
      UPDATE words 
      SET mastery_level = ? 
      WHERE LOWER(word) = ?
    ''', [repetitions > 5 ? 5 : repetitions, wordLower]);
  }

  // --- Data Management (Export/Import) ---
  Future<Map<String, dynamic>> getAllData() async {
    final db = await database;
    return {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'wordLists': await db.query('word_lists'),
      'words': await db.query('words'),
      'wordListItems': await db.query('word_list_items'),
      'quizResults': await db.query('quiz_results'),
      'userSettings': await db.query('user_settings'),
      'wordFamiliarity': await db.query('word_familiarity'),
      'userProfile': await db.query('user_profile'),
      'learningActivity': await db.query('learning_activity'),
    };
  }

  Future<void> importData(Map<String, dynamic> data) async {
    final db = await database;

    // Use transaction to ensure data integrity
    await db.transaction((txn) async {
      // --- 1. Import Word Lists (Map IDs by Name) ---
      final listIdMap = <int, int>{}; // Remote ID -> Local ID

      if (data['wordLists'] != null) {
        for (var item in data['wordLists']) {
          final remoteId = item['id'] as int;
          final name = item['name'] as String;

          // Check if list exists by name
          final List<Map<String, dynamic>> existing = await txn.query(
            'word_lists',
            columns: ['id'],
            where: 'name = ?',
            whereArgs: [name],
          );

          if (existing.isNotEmpty) {
            final localId = existing.first['id'] as int;
            listIdMap[remoteId] = localId;

            // Update color/desc if present
            if (item['color'] != null || item['description'] != null) {
              await txn.update(
                  'word_lists',
                  {
                    if (item['color'] != null) 'color': item['color'],
                    if (item['description'] != null)
                      'description': item['description'],
                  },
                  where: 'id = ?',
                  whereArgs: [localId]);
            }
          } else {
            // Insert new list (ignoring ID to let AutoIncrement work)
            final newItem = Map<String, dynamic>.from(item);
            newItem.remove('id'); // Allow local DB to assign new ID
            final newId = await txn.insert('word_lists', newItem);
            listIdMap[remoteId] = newId;
          }
        }
      }

      // --- 2. Import Words (Map IDs by Word+Translation) ---
      final wordIdMap = <int, int>{}; // Remote ID -> Local ID

      if (data['words'] != null) {
        for (var item in data['words']) {
          final remoteId = item['id'] as int;
          final word = (item['word'] as String).trim();
          final translation = (item['translation'] as String).trim();

          // Check if word exists (Case-insensitive check)
          final List<Map<String, dynamic>> existing = await txn.rawQuery(
            'SELECT id FROM words WHERE LOWER(TRIM(word)) = ? AND LOWER(TRIM(translation)) = ?',
            [word.toLowerCase(), translation.toLowerCase()],
          );

          if (existing.isNotEmpty) {
            final existingId = existing.first['id'] as int;
            wordIdMap[remoteId] = existingId;
            if (item['note'] != null) {
              await txn.update(
                'words',
                {'note': item['note']},
                where: 'id = ?',
                whereArgs: [existingId],
              );
            }
          } else {
            // Insert new word
            final newItem = Map<String, dynamic>.from(item);
            newItem.remove('id');
            newItem['word'] = word; // Ensure trimmed
            newItem['translation'] = translation; // Ensure trimmed
            final newId = await txn.insert('words', newItem);
            wordIdMap[remoteId] = newId;
          }
        }
      }

      // --- 3. Import List Items (Use Mapped IDs) ---
      if (data['wordListItems'] != null) {
        for (var item in data['wordListItems']) {
          final remoteListId = item['word_list_id'] as int;
          final remoteWordId = item['word_id'] as int;

          final localListId = listIdMap[remoteListId];
          final localWordId = wordIdMap[remoteWordId];

          if (localListId != null && localWordId != null) {
            // Check if link already exists
            final List<Map<String, dynamic>> existing = await txn.query(
              'word_list_items',
              where: 'word_list_id = ? AND word_id = ?',
              whereArgs: [localListId, localWordId],
            );

            if (existing.isEmpty) {
              await txn.insert('word_list_items', {
                'word_list_id': localListId,
                'word_id': localWordId,
                'added_at':
                    item['added_at'] ?? DateTime.now().toIso8601String(),
              });
            }
          }
        }
      }

      // --- 4. Import Quiz Results (Map List IDs) ---
      if (data['quizResults'] != null) {
        for (var item in data['quizResults']) {
          final remoteListId = item['word_list_id'] as int;
          final localListId = listIdMap[remoteListId];

          if (localListId != null) {
            final newItem = Map<String, dynamic>.from(item);
            newItem.remove('id');
            newItem['word_list_id'] = localListId;
            // Don't check for duplicates for quizzes, just add history
            await txn.insert('quiz_results', newItem);
          }
        }
      }

      // --- 5. Import Settings (Replace) ---
      if (data['userSettings'] != null) {
        for (var item in data['userSettings']) {
          // Skip target_language to preserve local preference
          if (item['key'] == 'target_language') continue;

          await txn.insert('user_settings', item,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      // --- 6. Import SRS Data (Match by Word Lower) ---
      if (data['wordFamiliarity'] != null) {
        for (var item in data['wordFamiliarity']) {
          await txn.insert('word_familiarity', item,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      // --- 7. Import Profile ---
      if (data['userProfile'] != null) {
        for (var item in data['userProfile']) {
          await txn.insert('user_profile', item,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      // --- 8. Import Learning Activity ---
      if (data['learningActivity'] != null) {
        for (var item in data['learningActivity']) {
          await txn.insert('learning_activity', item,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  // ────────────────────────────────────────────────────────────────────────────
  // AI Language Partner – Chat Sessions
  // ────────────────────────────────────────────────────────────────────────────

  Future<int> createChatSession({String title = 'New Chat', String language = 'en'}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return await db.insert('chat_sessions', {
      'title': title,
      'language': language,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<List<Map<String, dynamic>>> getChatSessions() async {
    final db = await database;
    return await db.query('chat_sessions', orderBy: 'updated_at DESC');
  }

  Future<void> updateChatSessionTitle(int id, String title) async {
    final db = await database;
    await db.update(
      'chat_sessions',
      {'title': title, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteChatSession(int id) async {
    final db = await database;
    await db.delete('chat_sessions', where: 'id = ?', whereArgs: [id]);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // AI Language Partner – Chat Messages
  // ────────────────────────────────────────────────────────────────────────────

  Future<int> addChatMessage({
    required int sessionId,
    required String sender,
    required String content,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final msgId = await db.insert('chat_messages', {
      'session_id': sessionId,
      'sender': sender,
      'content': content,
      'timestamp': now,
    });
    // Bump session updated_at
    await db.update(
      'chat_sessions',
      {'updated_at': now},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    return msgId;
  }

  Future<List<Map<String, dynamic>>> getChatMessages(int sessionId) async {
    final db = await database;
    return await db.query(
      'chat_messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // AI Language Partner – Corrections
  // ────────────────────────────────────────────────────────────────────────────

  Future<int> addCorrection({
    int? messageId,
    int? sessionId,
    required String originalText,
    required String correctedText,
    required String explanation,
    String category = 'grammar',
  }) async {
    final db = await database;
    return await db.insert('correction_metadata', {
      'message_id': messageId,
      'session_id': sessionId,
      'original_text': originalText,
      'corrected_text': correctedText,
      'explanation': explanation,
      'category': category,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getCorrections({
    String? category,
    String? searchQuery,
  }) async {
    final db = await database;
    String? where;
    final List<Object?> whereArgs = [];

    if (category != null && category != 'all') {
      where = 'category = ?';
      whereArgs.add(category);
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      final q = '%${searchQuery.toLowerCase()}%';
      final searchWhere =
          '(LOWER(original_text) LIKE ? OR LOWER(corrected_text) LIKE ? OR LOWER(explanation) LIKE ?)';
      whereArgs.addAll([q, q, q]);
      where = where == null ? searchWhere : '$where AND $searchWhere';
    }

    return await db.query(
      'correction_metadata',
      where: where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'created_at DESC',
    );
  }

  Future<void> updateCorrectionNote(int id, String note) async {
    final db = await database;
    await db
        .update('correction_metadata', {'user_note': note}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteCorrection(int id) async {
    final db = await database;
    await db.delete('correction_metadata', where: 'id = ?', whereArgs: [id]);
  }
}
