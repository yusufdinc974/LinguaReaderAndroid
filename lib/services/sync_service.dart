import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_service.dart';

/// Syncs local SQLite data to/from Supabase for signed-in users.
/// Strategy: local_id (SQLite integer PK) + user_id = unique key for upsert.
class SyncService {
  static final _supabase = Supabase.instance.client;
  static final _db = DatabaseService();

  static String? get _userId => _supabase.auth.currentUser?.id;

  /// Call after login — merges cloud/local data.
  static Future<void> syncOnLogin() async {
    if (_userId == null) {
      debugPrint('SyncService.syncOnLogin skipped: no user');
      return;
    }
    // Always pull first, then push merged state.
    // This prevents wiping cloud data when local DB is empty (e.g., reinstall/new device).
    await pullFromCloud();
    await pushToCloud();
  }

  /// Pushes local SQLite data → Supabase
  static Future<void> pushToCloud() async {
    if (_userId == null) {
      debugPrint('SyncService.pushToCloud skipped: no user');
      return;
    }
    try {
      final data = await _db.getAllData();

      final wordLists = (data['wordLists'] as List<Map<String, dynamic>>)
          .map((row) => <String, dynamic>{
                'user_id': _userId,
                'local_id': row['id'],
                'name': row['name'],
                'description': row['description'],
                'color': row['color'],
                'created_at': row['created_at'],
              })
          .toList();

      final words = (data['words'] as List<Map<String, dynamic>>)
          .map((row) => <String, dynamic>{
                'user_id': _userId,
                'local_id': row['id'],
                'word': row['word'],
                'translation': row['translation'],
                'source_language': row['source_language'],
                'target_language': row['target_language'],
                'sentence_context': row['sentence_context'],
                'pdf_name': row['pdf_name'],
                'note': row['note'],
                'created_at': row['created_at'],
                'mastery_level': row['mastery_level'],
              })
          .toList();

      final wordListItems =
          (data['wordListItems'] as List<Map<String, dynamic>>)
              .map((row) => <String, dynamic>{
                    'user_id': _userId,
                    'local_id': row['id'],
                    'word_list_local_id': row['word_list_id'],
                    'word_local_id': row['word_id'],
                    'added_at': row['added_at'],
                  })
              .toList();

      final wordFamiliarity =
          (data['wordFamiliarity'] as List<Map<String, dynamic>>)
              .map((row) => <String, dynamic>{
                    'user_id': _userId,
                    'local_id': row['id'],
                    'word_lower': row['word_lower'],
                    'familiarity_level': row['familiarity_level'],
                    'translation': row['translation'],
                    'easiness_factor': row['easiness_factor'],
                    'interval': row['interval'],
                    'repetitions': row['repetitions'],
                    'next_review_date': row['next_review_date'],
                    'last_review_date': row['last_review_date'],
                    'updated_at': row['updated_at'],
                  })
              .toList();

      await _syncTable('word_lists', wordLists);
      await _syncTable('words', words);
      await _syncTable('word_list_items', wordListItems);
      await _syncTable('word_familiarity', wordFamiliarity);

      debugPrint(
        'SyncService: push complete lists=${wordLists.length} words=${words.length} items=${wordListItems.length} familiarity=${wordFamiliarity.length}',
      );
    } catch (e) {
      debugPrint('SyncService.pushToCloud error: $e');
    }
  }

  /// Pulls Supabase data → local SQLite (used when user logs in on new device)
  static Future<void> pullFromCloud() async {
    if (_userId == null) {
      debugPrint('SyncService.pullFromCloud skipped: no user');
      return;
    }
    try {
      final cloudLists = (await _supabase
          .from('word_lists')
          .select()
          .eq('user_id', _userId!)) as List<dynamic>;

      // Only pull if there's cloud data to restore
      if (cloudLists.isEmpty) return;

      final cloudWords = (await _supabase
          .from('words')
          .select()
          .eq('user_id', _userId!)) as List<dynamic>;

      final cloudItems = (await _supabase
          .from('word_list_items')
          .select()
          .eq('user_id', _userId!)) as List<dynamic>;

      final cloudFamiliarity = (await _supabase
          .from('word_familiarity')
          .select()
          .eq('user_id', _userId!)) as List<dynamic>;

      final validLists = cloudLists
          .whereType<Map<String, dynamic>>()
          .where((e) => e['local_id'] != null)
          .toList();
      final validWords = cloudWords
          .whereType<Map<String, dynamic>>()
          .where((e) => e['local_id'] != null)
          .toList();
      final validItems = cloudItems
          .whereType<Map<String, dynamic>>()
          .where((e) => e['local_id'] != null)
          .toList();
      final validFamiliarity = cloudFamiliarity
          .whereType<Map<String, dynamic>>()
          .where((e) => e['local_id'] != null)
          .toList();

      // Remap cloud data to match local import format
      final remappedLists = validLists
          .map((e) => {
                'id': e['local_id'],
                'name': e['name'],
                'description': e['description'],
                'color': e['color'],
                'created_at': e['created_at'],
              })
          .toList();

      final remappedWords = validWords
          .map((e) => {
                'id': e['local_id'],
                'word': e['word'],
                'translation': e['translation'],
                'source_language': e['source_language'],
                'target_language': e['target_language'],
                'sentence_context': e['sentence_context'],
                'pdf_name': e['pdf_name'],
                'note': e['note'],
                'created_at': e['created_at'],
                'mastery_level': e['mastery_level'] ?? 0,
              })
          .toList();

      final remappedItems = validItems
          .map((e) => {
                'id': e['local_id'],
                'word_list_id': e['word_list_local_id'],
                'word_id': e['word_local_id'],
                'added_at': e['added_at'],
              })
          .toList();

      final remappedFamiliarity = validFamiliarity
          .map((e) => {
                'id': e['local_id'],
                'word_lower': e['word_lower'],
                'familiarity_level': e['familiarity_level'] ?? 1,
                'translation': e['translation'],
                'easiness_factor':
                    (e['easiness_factor'] as num?)?.toDouble() ?? 2.5,
                'interval': e['interval'] ?? 0,
                'repetitions': e['repetitions'] ?? 0,
                'next_review_date': e['next_review_date'],
                'last_review_date': e['last_review_date'],
                'updated_at': e['updated_at'],
              })
          .toList();

      await _db.importData({
        'wordLists': remappedLists,
        'words': remappedWords,
        'wordListItems': remappedItems,
        'wordFamiliarity': remappedFamiliarity,
        'quizResults': [],
        'userSettings': [],
      });

      debugPrint(
        'SyncService: pull complete — restored ${remappedLists.length} lists, ${remappedWords.length} words',
      );
    } catch (e) {
      debugPrint('SyncService.pullFromCloud error: $e');
    }
  }

  static Future<void> _syncTable(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    final localIds =
        rows.map((row) => row['local_id']).whereType<int>().toList();
    await _deleteMissingRows(table, localIds);
    if (rows.isEmpty) return;

    try {
      await _supabase.from(table).upsert(
            rows,
            onConflict: 'user_id,local_id',
          );
    } catch (e) {
      if (table == 'words') {
        final fallbackRows = rows
            .map((row) => Map<String, dynamic>.from(row)..remove('note'))
            .toList();
        try {
          await _supabase.from(table).upsert(
                fallbackRows,
                onConflict: 'user_id,local_id',
              );
          debugPrint(
            'SyncService._syncTable(words): synced without note column fallback',
          );
          return;
        } catch (_) {
          // Fall through to original error log below.
        }
      }
      debugPrint('SyncService._syncTable($table) upsert error: $e');
    }
  }

  static Future<void> _deleteMissingRows(
    String table,
    List<int> localIds,
  ) async {
    if (_userId == null) return;

    try {
      final query = _supabase.from(table).delete().eq('user_id', _userId!);
      if (localIds.isEmpty) {
        await query;
        return;
      }
      final idsCsv = localIds.join(',');
      await query.not('local_id', 'in', '($idsCsv)');
    } catch (e) {
      debugPrint('SyncService._deleteMissingRows($table) error: $e');
    }
  }
}
