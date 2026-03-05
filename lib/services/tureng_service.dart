import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

class TurengEntry {
  final String category;
  final String partOfSpeech;
  final String term;
  final String translation;

  const TurengEntry({
    required this.category,
    required this.partOfSpeech,
    required this.term,
    required this.translation,
  });
}

class TurengService {
  static const Map<String, String> supportedPairs = {
    'English ↔ Turkish': 'english-turkish',
    'German ↔ Turkish': 'german-turkish',
    'French ↔ Turkish': 'french-turkish',
    'Spanish ↔ Turkish': 'spanish-turkish',
  };

  Future<List<TurengEntry>> lookup(
    String word, {
    String languagePair = 'english-turkish',
  }) async {
    // Tureng wants the word as-is (case matters for proper nouns).
    // Try the original casing first, then lowercase as fallback.
    final trimmed = word.trim();

    try {
      final result = await _fetchAndParse(trimmed, languagePair);
      if (result != null) return result;
    } on _TurengBlockedException {
      return _lookupFallback(word: trimmed, languagePair: languagePair);
    }

    // Fallback: try lowercase
    final lower = trimmed.toLowerCase();
    if (lower != trimmed) {
      try {
        final lowerResult = await _fetchAndParse(lower, languagePair);
        if (lowerResult != null) return lowerResult;
      } on _TurengBlockedException {
        return _lookupFallback(word: lower, languagePair: languagePair);
      }
    }

    return []; // Word not found in Tureng
  }

  Future<List<TurengEntry>?> _fetchAndParse(
      String word, String languagePair) async {
    final encoded = Uri.encodeComponent(word);
    final url = 'https://tureng.com/en/$languagePair/$encoded';

    final http.Response response;
    try {
      response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9,tr;q=0.8',
          'Upgrade-Insecure-Requests': '1',
          'Sec-Fetch-Dest': 'document',
          'Sec-Fetch-Mode': 'navigate',
          'Sec-Fetch-Site': 'none',
          'Sec-Fetch-User': '?1',
        },
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw Exception('Network error: $e');
    }

    // 404 means word not found — return empty list (not an error)
    if (response.statusCode == 404) return [];

    if (response.statusCode == 403) {
      throw _TurengBlockedException();
    }

    if (response.statusCode != 200) {
      throw Exception('Tureng returned status ${response.statusCode}');
    }

    final results = _parseResults(response.body);
    // Return null only if we got a response that had no parseable results
    // (could indicate a redirect or captcha page rather than real results)
    return results;
  }

  Future<List<TurengEntry>> _lookupFallback({
    required String word,
    required String languagePair,
  }) async {
    final (source, target) = _sourceAndTarget(languagePair);
    final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
      'client': 'gtx',
      'sl': source,
      'tl': target,
      'dt': 't',
      'q': word,
    });

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception(
            'Fallback dictionary returned status ${response.statusCode}');
      }

      final data = json.decode(response.body) as List<dynamic>;
      final segments =
          data.isNotEmpty ? data.first as List<dynamic> : <dynamic>[];
      final translation = segments
          .map((segment) {
            if (segment is List && segment.isNotEmpty) {
              return segment.first?.toString() ?? '';
            }
            return '';
          })
          .join('')
          .trim();

      if (translation.isEmpty)
        throw Exception('No fallback dictionary results');

      return [
        TurengEntry(
          category: 'Fallback',
          partOfSpeech: '',
          term: word,
          translation: translation,
        ),
      ];
    } catch (_) {
      throw Exception(
        'Dictionary is temporarily unavailable (Tureng is blocking automated lookups).',
      );
    }
  }

  (String, String) _sourceAndTarget(String languagePair) {
    final pair = _languageCodePair(languagePair);
    final parts = pair.split('|');
    return (parts[0], parts[1]);
  }

  String _languageCodePair(String languagePair) {
    switch (languagePair) {
      case 'english-turkish':
        return 'en|tr';
      case 'german-turkish':
        return 'de|tr';
      case 'french-turkish':
        return 'fr|tr';
      case 'spanish-turkish':
        return 'es|tr';
      default:
        return 'en|tr';
    }
  }

  List<TurengEntry> _parseResults(String htmlBody) {
    final document = html_parser.parse(htmlBody);
    final results = <TurengEntry>[];

    // Tureng result tables are identified by id attributes like 'englishResults',
    // 'computerResults', etc. or class 'table'. We grab all tables and scan their tbody.
    final tables = document.querySelectorAll('table');

    for (final table in tables) {
      // Determine category name
      // Tureng puts category in the <thead> first <th> (e.g., "General", "Computers")
      String category = '';
      final thead = table.querySelector('thead');
      if (thead != null) {
        final ths = thead.querySelectorAll('th');
        // The 4th <th> (index 3) in Tureng thead is the category header for the translation column
        // but the category label is usually in a row of its own or as table id
        // Fallback: check table id attribute
        final tableId = table.attributes['id'] ?? '';
        if (tableId.isNotEmpty) {
          // "englishResults" → "English", "computerResults" → "Computer"
          category = tableId
              .replaceAll('Results', '')
              .replaceFirst(tableId[0], tableId[0].toUpperCase());
        }
        // If no id, try to get it from th text not matching column labels
        if (category.isEmpty) {
          final labels = {
            'english',
            'turkish',
            'german',
            'french',
            'spanish',
            'type',
            '#',
            ''
          };
          for (final th in ths) {
            final t = th.text.trim();
            if (!labels.contains(t.toLowerCase())) {
              category = t;
              break;
            }
          }
        }
      }

      final tbody = table.querySelector('tbody');
      if (tbody == null) continue;

      final rows = tbody.querySelectorAll('tr');
      for (final row in rows) {
        final cells = row.querySelectorAll('td');
        // Standard Tureng row: [#, term, type, translation]
        if (cells.length >= 4) {
          final term = cells[1].text.trim();
          final partOfSpeech = cells[2].text.trim();
          final translation = cells[3].text.trim();

          if (term.isNotEmpty && translation.isNotEmpty) {
            results.add(TurengEntry(
              category: category,
              partOfSpeech: partOfSpeech,
              term: term,
              translation: translation,
            ));
          }
        }
      }
    }

    return results;
  }
}

class _TurengBlockedException implements Exception {}
