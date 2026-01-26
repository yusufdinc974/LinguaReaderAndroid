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
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'linguareader.db');
    final db = await openDatabase(
      path,
      version: 2,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    
    await _ensureDefaults(db);
    return db;
  }

  Future<void> _ensureDefaults(Database db) async {
    // Ensure target_language is set (Default: 'en')
    final List<Map<String, dynamic>> targetLang = await db.query(
      'user_settings',
      where: 'key = ?',
      whereArgs: ['target_language'],
    );
    if (targetLang.isEmpty) {
      await db.insert('user_settings', {'key': 'target_language', 'value': 'en'});
    }

    // Ensure deepl_api_key is set (Default: '') to explicitly enable MyMemory fallback logic
    final List<Map<String, dynamic>> apiKey = await db.query(
      'user_settings',
      where: 'key = ?',
      whereArgs: ['deepl_api_key'],
    );
    if (apiKey.isEmpty) {
      await db.insert('user_settings', {'key': 'deepl_api_key', 'value': ''});
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



    // Default Settings
    await db.insert('user_settings', {'key': 'target_language', 'value': 'en'});
    await db.insert('user_settings', {'key': 'theme', 'value': 'dark'});
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
  }

  // --- Word Lists ---
  Future<List<Map<String, dynamic>>> getWordLists() async {
    final db = await database;
    return await db.query('word_lists', orderBy: 'created_at DESC');
  }

  Future<int> createWordList(String name, String description, {String? color}) async {
    final db = await database;
    return await db.insert('word_lists', {
      'name': name,
      'description': description,
      'color': color ?? '0xFF2196F3', // Default Blue
    });
  }

  Future<void> deleteWordList(int id) async {
    final db = await database;
    
    // 1. Get all words in this list
    final words = await db.rawQuery('''
      SELECT w.id, w.word 
      FROM words w
      JOIN word_list_items wli ON w.id = wli.word_id
      WHERE wli.word_list_id = ?
    ''', [id]);

    // 2. Delete words specific to this list (orphans)
    // Desktop logic: Deletes words that are ONLY in this list (orphaned after list deletion)
    // To do this safely, we first delete the list items, then check for orphans.
    
    await db.delete('word_list_items', where: 'word_list_id = ?', whereArgs: [id]);
    
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

  Future<List<Map<String, dynamic>>> getWordsWithColors({List<int>? listIds}) async {
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
  }) async {
    final db = await database;
    // 1. Insert into words table
    final wordId = await db.insert('words', {
      'word': word,
      'translation': translation,
      'source_language': 'auto', // Could be passed in
      'target_language': 'en',   // Could be passed in or from settings
      'sentence_context': context,
      'pdf_name': pdfName,
    });

    // 2. Link to list
    await db.insert('word_list_items', {
      'word_list_id': listId,
      'word_id': wordId,
    });
    
    // 3. Initialize SRS (Familiarity)
    await db.insert('word_familiarity', {
      'word_lower': word.toLowerCase(),
      'translation': translation,
      'next_review_date': DateTime.now().toIso8601String(), // Start review immediately or next day
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    return wordId;
  }

  Future<void> deleteWord(int id) async {
    final db = await database;
    
    // Get word text for familiarity cleanup
    final wordMaps = await db.query('words', columns: ['word'], where: 'id = ?', whereArgs: [id]);
    if (wordMaps.isNotEmpty) {
      final wordLower = (wordMaps.first['word'] as String).toLowerCase();
      await db.delete('word_familiarity', where: 'word_lower = ?', whereArgs: [wordLower]);
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
      'SELECT COUNT(*) FROM word_list_items WHERE word_id = ?',
      [wordId]
    ));

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

  Future<void> addRecentPdf(String name, String path) async {
    final db = await database;
    await db.insert('recent_pdfs', {
      'name': name,
      'path': path,
      'last_opened': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // --- Stats ---
  Future<int> getWordsToReviewCount() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM word_familiarity WHERE next_review_date <= ?',
      [now]
    );
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
      'Mastered': 0, // Combining Familiar and Mastered for simplicity or keeping separate
    };

    for (var row in result) {
      final level = row['familiarity_level'] as int;
      final count = row['count'] as int;
      if (level <= 1) stats['Unknown'] = (stats['Unknown'] ?? 0) + count;
      else if (level == 2) stats['Seen'] = (stats['Seen'] ?? 0) + count;
      else if (level == 3) stats['Learning'] = (stats['Learning'] ?? 0) + count;
      else stats['Mastered'] = (stats['Mastered'] ?? 0) + count;
    }
    return stats;
  }

  Future<List<Map<String, dynamic>>> getUpcomingReviews() async {
    final db = await database;
    final now = DateTime.now();
    final todayStr = now.toIso8601String().split('T')[0];
    
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
    return buckets.entries.map((e) => {'review_day': e.key, 'count': e.value}).toList();
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

    easeFactor = easeFactor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
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
                  if (item['description'] != null) 'description': item['description'],
                },
                where: 'id = ?',
                whereArgs: [localId]
              );
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
            wordIdMap[remoteId] = existing.first['id'] as int;
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
                'added_at': item['added_at'] ?? DateTime.now().toIso8601String(),
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
          
          await txn.insert('user_settings', item, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      
      // --- 6. Import SRS Data (Match by Word Lower) ---
      if (data['wordFamiliarity'] != null) {
         for (var item in data['wordFamiliarity']) {
           // We match by word_lower, which is a unique key
           // If it exists, we could check which one is "newer" (based on updated_at), 
           // but for simple sync, we often accept latest import or trust the most recent device.
           // Ideally we check timestamps.
           await txn.insert('word_familiarity', item, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }
}
