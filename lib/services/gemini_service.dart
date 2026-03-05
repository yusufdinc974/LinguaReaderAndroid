import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GeminiService {
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  final _supabase = Supabase.instance.client;

  bool get isLoggedIn => _supabase.auth.currentSession != null;

  /// Explains a phrase via the Supabase Edge Function (premium-only).
  ///
  /// Throws 'not_logged_in' if the user has no Supabase session.
  /// Throws 'premium_required' if the user is not a premium subscriber.
  /// Throws a descriptive message for network/server errors.
  Future<String> explainPhrase(
    String phrase, {
    String targetLanguage = 'Turkish',
  }) async {
    var session = _supabase.auth.currentSession;
    debugPrint(
      'GeminiService: before refresh session=${session != null} user=${_supabase.auth.currentUser?.id}',
    );

    // Session can be temporarily null while user data is still restoring.
    // Retry refresh once before deciding the user is not logged in.
    if (session == null) {
      try {
        final refreshed = await _supabase.auth.refreshSession();
        session = refreshed.session;
        debugPrint(
          'GeminiService: refresh result session=${session != null} user=${_supabase.auth.currentUser?.id}',
        );
      } catch (_) {
        // Ignore and fall through to not_logged_in.
        debugPrint('GeminiService: refresh session failed');
      }
    }

    if (session == null) {
      throw Exception('not_logged_in: no_active_session');
    }

    try {
      final response = await _invokeGemini(
        accessToken: session.accessToken,
        phrase: phrase,
        targetLanguage: targetLanguage,
      );

      final data = response.data as Map<String, dynamic>?;
      return data?['text'] as String? ?? 'No response from Gemini.';
    } on FunctionException catch (e) {
      // Token may have expired between checks; refresh + retry once.
      if (e.status == 401) {
        try {
          final refreshed = await _supabase.auth.refreshSession();
          final newSession = refreshed.session;
          debugPrint(
            'GeminiService: 401 retry refresh session=${newSession != null}',
          );
          if (newSession != null) {
            final retryResponse = await _invokeGemini(
              accessToken: newSession.accessToken,
              phrase: phrase,
              targetLanguage: targetLanguage,
            );
            final retryData = retryResponse.data as Map<String, dynamic>?;
            return retryData?['text'] as String? ?? 'No response from Gemini.';
          }
        } catch (_) {
          // Fall through to not_logged_in.
          debugPrint('GeminiService: 401 retry refresh failed');
        }
      }

      final detail = _extractErrorDetail(e);
      if (e.status == 401) throw Exception('not_logged_in: $detail');
      if (e.status == 403) throw Exception('premium_required: $detail');

      throw Exception('Gemini error: ${_toUserFriendlyError(detail)}');
    } catch (e) {
      throw Exception('Gemini request failed: $e');
    }
  }

  String _extractErrorDetail(FunctionException e) {
    final details = e.details;
    if (details is Map<String, dynamic>) {
      final detail = details['detail'] ?? details['error'];
      if (detail != null) return detail.toString();
    } else if (details != null) {
      return details.toString();
    }
    return e.reasonPhrase ?? 'Unknown error';
  }

  String _toUserFriendlyError(String detail) {
    final lowered = detail.toLowerCase();
    if (lowered.contains('api key') && lowered.contains('invalid')) {
      return 'Server Gemini API key is invalid.';
    }
    if (lowered.contains('quota') || lowered.contains('rate limit')) {
      return 'Gemini quota/rate limit reached. Please try again later.';
    }
    if (detail.length > 220) {
      return '${detail.substring(0, 220)}...';
    }
    return detail;
  }

  Future<FunctionResponse> _invokeGemini({
    required String accessToken,
    required String phrase,
    required String targetLanguage,
  }) {
    return _supabase.functions.invoke(
      'gemini-explain',
      headers: {
        'Authorization': 'Bearer $accessToken',
      },
      body: {
        'phrase': phrase.trim(),
        'targetLanguage': targetLanguage,
      },
    );
  }
}
