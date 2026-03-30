import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart' as genai;

// ─────────────────────────────────────────────────────────────────────────────
// Data Models
// ─────────────────────────────────────────────────────────────────────────────

class ChatMessage {
  final int? id;
  final int sessionId;
  final String sender; // 'user' | 'ai'
  final String content;
  final DateTime timestamp;
  final CorrectionData? correction; // only on AI messages

  const ChatMessage({
    this.id,
    required this.sessionId,
    required this.sender,
    required this.content,
    required this.timestamp,
    this.correction,
  });

  bool get isUser => sender == 'user';

  ChatMessage copyWith({CorrectionData? correction}) => ChatMessage(
        id: id,
        sessionId: sessionId,
        sender: sender,
        content: content,
        timestamp: timestamp,
        correction: correction ?? this.correction,
      );

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
        id: map['id'] as int?,
        sessionId: map['session_id'] as int,
        sender: map['sender'] as String,
        content: map['content'] as String,
        timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );
}

class CorrectionData {
  final int? id;
  final String original;
  final String corrected;
  final String explanation;
  final String category; // 'grammar' | 'spelling' | 'naturalness'
  String? userNote;

  CorrectionData({
    this.id,
    required this.original,
    required this.corrected,
    required this.explanation,
    required this.category,
    this.userNote,
  });

  factory CorrectionData.fromMap(Map<String, dynamic> map) => CorrectionData(
        id: map['id'] as int?,
        original: map['original_text'] as String? ?? '',
        corrected: map['corrected_text'] as String? ?? '',
        explanation: map['explanation'] as String? ?? '',
        category: map['category'] as String? ?? 'grammar',
        userNote: map['user_note'] as String?,
      );

  factory CorrectionData.fromJson(Map<String, dynamic> json) => CorrectionData(
        original: json['original'] as String? ?? '',
        corrected: json['corrected'] as String? ?? '',
        explanation: json['explanation'] as String? ?? '',
        category: _normalizeCategory(json['category'] as String?),
      );

  static String _normalizeCategory(String? raw) {
    final r = (raw ?? '').toLowerCase();
    if (r.contains('spell')) return 'spelling';
    if (r.contains('natural')) return 'naturalness';
    return 'grammar';
  }
}

/// Our own DB/UI session model.
/// Named [PartnerSession] to avoid colliding with [genai.ChatSession]
/// from the google_generative_ai package; [ChatSession] is a backwards-
/// compatible typedef kept for existing usages in providers/widgets.
class PartnerSession {
  final int? id;
  final String title;
  final String language;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PartnerSession({
    this.id,
    required this.title,
    required this.language,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PartnerSession.fromMap(Map<String, dynamic> map) => PartnerSession(
        id: map['id'] as int?,
        title: map['title'] as String,
        language: map['language'] as String? ?? 'en',
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Backwards-compatible alias so existing code that imports [ChatSession]
/// from this file still compiles without modification.
typedef ChatSession = PartnerSession;

class AiPartnerResult {
  final String reply;
  final CorrectionData? correction;

  const AiPartnerResult({required this.reply, this.correction});
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal Gemini session wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _GeminiSession {
  final genai.ChatSession chat;
  _GeminiSession({required this.chat});
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class AiPartnerService {
  static final AiPartnerService _instance = AiPartnerService._internal();
  factory AiPartnerService() => _instance;
  AiPartnerService._internal();

  static const String _apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue:
        'AIzaSyAUnguxe4YV8cgetipYmct2CWIt6Rf8Mlo', // User's provided key as fallback
  );

  static const String _modelName = 'gemini-2.5-flash';

  // Per-DB-session Gemini chat sessions (in-memory only)
  final Map<int, _GeminiSession> _sessionCache = {};

  genai.GenerativeModel _buildModel(String explanationLanguage) {
    return genai.GenerativeModel(
      model: _modelName,
      apiKey: _apiKey,
      systemInstruction:
          genai.Content.system(_systemPrompt(explanationLanguage)),
      generationConfig: genai.GenerationConfig(
        temperature: 0.8,
        maxOutputTokens: 1024,
      ),
    );
  }

  String _systemPrompt(String explanationLanguage) => '''
You are a friendly, encouraging AI language learning partner.
Converse naturally in whatever language the user uses.

If the user makes a mistake in grammar, spelling, or phrasing, you MUST playfully roast them for it in your conversational reply. Ensure it's friendly but a clear roast.
You must also constantly maintain the chat by asking the user a follow-up question about the spoken topic to keep the conversation going.

CRITICAL INSTRUCTION: You are STRICTLY a language learning assistant. 
If the user asks you to write code, solve math problems, answer historical trivia, or do anything unrelated to language learning, YOU MUST REFUSE politely. 
Steer the conversation back to language practice. Do not break character.

After each of your replies, carefully check the user's most recent message for:
- Grammar mistakes
- Spelling errors
- Unnatural or non-idiomatic phrasing

If you find any issue, append a SINGLE structured correction block at the very end
of your reply using EXACTLY this format (with nothing else after it):

---CORRECTION---
Original: <exact phrase from user>
Corrected: <improved version>
Explanation: <brief, friendly explanation written entirely in $explanationLanguage>
Category: <grammar or spelling or naturalness>

If the user's message is perfectly fine, do NOT include the correction block.
Keep your conversational reply separate from the correction block.
Limit conversational replies to ~3 sentences unless asked for more.
''';

  _GeminiSession _getSession(int sessionId, String explanationLanguage) {
    return _sessionCache.putIfAbsent(
      sessionId,
      () => _GeminiSession(chat: _buildModel(explanationLanguage).startChat()),
    );
  }

  void clearSession(int sessionId) => _sessionCache.remove(sessionId);

  void loadHistory(
      int sessionId, List<ChatMessage> messages, String explanationLanguage) {
    final history = messages.map((m) {
      return genai.Content(
        m.isUser ? 'user' : 'model',
        [genai.TextPart(m.content)],
      );
    }).toList();
    _sessionCache[sessionId] = _GeminiSession(
        chat: _buildModel(explanationLanguage).startChat(history: history));
  }

  Future<AiPartnerResult> sendMessage(int sessionId, String userMessage,
      {String explanationLanguage = 'English'}) async {
    if (_apiKey.isEmpty) {
      throw Exception(
        'GEMINI_API_KEY is not configured. '
        'Run flutter with --dart-define=GEMINI_API_KEY=your_key',
      );
    }

    final session = _getSession(sessionId, explanationLanguage);
    final response = await session.chat.sendMessage(
      genai.Content.text(userMessage),
    );

    final rawText = response.text ?? '';
    debugPrint('DEBUG_GEMINI_RAW: $rawText');
    return _parseResponse(rawText);
  }

  AiPartnerResult _parseResponse(String raw) {
    String reply = raw.trim();
    CorrectionData? correction;

    final marker = '---CORRECTION---';
    final markerIdx = raw.indexOf(marker);

    if (markerIdx != -1) {
      reply = raw.substring(0, markerIdx).trim();
      final correctionText = raw.substring(markerIdx + marker.length).trim();

      String? original, corrected, explanation, category;

      for (final line in correctionText.split('\n')) {
        final lower = line.toLowerCase();
        if (lower.startsWith('original:')) {
          original = line.substring(9).trim();
        } else if (lower.startsWith('corrected:')) {
          corrected = line.substring(10).trim();
        } else if (lower.startsWith('explanation:')) {
          explanation = line.substring(12).trim();
        } else if (lower.startsWith('category:')) {
          category = line.substring(9).trim();
        }
      }

      if (original != null &&
          original.isNotEmpty &&
          corrected != null &&
          corrected.isNotEmpty) {
        correction = CorrectionData(
          original: original,
          corrected: corrected,
          explanation: explanation ?? '',
          category: CorrectionData._normalizeCategory(category),
        );
      }
    }

    return AiPartnerResult(reply: reply, correction: correction);
  }
}
