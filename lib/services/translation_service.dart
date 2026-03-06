import 'dart:convert';
import 'package:http/http.dart' as http;
import 'database_service.dart';

class TranslationResult {
  final String translatedText;
  final String detectedLanguage;
  final String? source;

  TranslationResult(
      {required this.translatedText,
      required this.detectedLanguage,
      this.source});
}

class TranslationService {
  final _databaseService = DatabaseService();

  Future<TranslationResult> translateText(
    String text, {
    String sourceLang = 'auto',
    String? targetLang,
  }) async {
    // 1. Get Settings
    String? deepLKey = await _databaseService.getSetting('deepl_api_key');
    String resolvedTargetLang = targetLang?.trim() ?? '';
    if (resolvedTargetLang.isEmpty) {
      resolvedTargetLang =
          (await _databaseService.getSetting('target_language')) ?? '';
    }
    if (resolvedTargetLang.trim().isEmpty) {
      resolvedTargetLang = 'tr';
      print('DEBUG: target_language was empty/null, defaulting to "tr"');
    }

    print('DEBUG: Translating "$text" to $resolvedTargetLang');
    if (deepLKey != null && deepLKey.trim().isNotEmpty) {
      print('DEBUG: Using DeepL API Key: ${deepLKey.substring(0, 5)}...');
      try {
        return await _translateWithDeepL(text, deepLKey, resolvedTargetLang);
      } catch (e) {
        print('DEBUG: DeepL failed ($e). Falling back to MyMemory...');
        // Fall through to MyMemory below
      }
    }

    // 2. Fallback to MyMemory (Free)
    print('DEBUG: Using MyMemory Fallback');
    return _translateWithMyMemory(
      text,
      targetLang: resolvedTargetLang,
      sourceLang: sourceLang,
    );
  }

  Future<TranslationResult> _translateWithDeepL(
      String text, String apiKey, String targetLang) async {
    // DeepL target supports 'EN-US' or 'EN-GB', but 'EN' is usually fine (defaults to US)
    // DeepL Free API URL
    const String baseUrl = 'https://api-free.deepl.com/v2/translate';

    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Authorization': 'DeepL-Auth-Key $apiKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'text': text,
          'target_lang': targetLang.toUpperCase(), // DeepL requires uppercase
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decoder.convert(response.bodyBytes));
        final translations = data['translations'] as List;
        if (translations.isNotEmpty) {
          return TranslationResult(
            translatedText: translations[0]['text'],
            detectedLanguage: translations[0]['detected_source_language'],
            source: 'DeepL',
          );
        }
      }
      throw Exception('DeepL Error: ${response.statusCode} ${response.body}');
    } catch (e) {
      print('DeepL failed: $e. Falling back...');
      // Allow fallback if DeepL fails? Maybe rethrow for now so user knows key is wrong.
      throw Exception('DeepL Translation failed. Check API Key. Error: $e');
    }
  }

  Future<TranslationResult> _translateWithMyMemory(String text,
      {String targetLang = 'en', String sourceLang = 'auto'}) async {
    const String baseUrl = 'https://api.mymemory.translated.net/get';
    try {
      final source = sourceLang == 'auto' ? 'autodetect' : sourceLang;
      final langPair = '$source|${targetLang.toLowerCase()}';

      final uri = Uri.parse(baseUrl).replace(queryParameters: {
        'q': text,
        'langpair': langPair,
      });

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception('Translation failed: ${response.statusCode}');
      }

      final data = json.decode(response.body);

      if (data['responseStatus'] != 200) {
        throw Exception(data['responseDetails'] ?? 'Translation failed');
      }

      return TranslationResult(
        translatedText: data['responseData']['translatedText'],
        detectedLanguage: data['responseData']['detectedLanguage'] ?? 'unknown',
        source: 'MyMemory (Free)',
      );
    } catch (e) {
      throw Exception('Translation error: $e');
    }
  }
}
