import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/ai_partner_service.dart';
import '../../services/database_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Service provider
// ─────────────────────────────────────────────────────────────────────────────

final aiPartnerServiceProvider = Provider<AiPartnerService>(
  (ref) => AiPartnerService(),
);

// ─────────────────────────────────────────────────────────────────────────────
// Chat Sessions
// ─────────────────────────────────────────────────────────────────────────────

final chatSessionsProvider =
    AsyncNotifierProvider<ChatSessionsNotifier, List<ChatSession>>(
  ChatSessionsNotifier.new,
);

class ChatSessionsNotifier extends AsyncNotifier<List<ChatSession>> {
  @override
  Future<List<ChatSession>> build() => _load();

  Future<List<ChatSession>> _load() async {
    final rows = await DatabaseService().getChatSessions();
    return rows.map(ChatSession.fromMap).toList();
  }

  Future<int> createSession({String title = 'New Chat'}) async {
    final id = await DatabaseService().createChatSession(title: title);
    ref.invalidateSelf();
    return id;
  }

  Future<void> deleteSession(int id) async {
    ref.read(aiPartnerServiceProvider).clearSession(id);
    await DatabaseService().deleteChatSession(id);
    ref.invalidateSelf();
  }

  Future<void> rename(int id, String title) async {
    await DatabaseService().updateChatSessionTitle(id, title);
    ref.invalidateSelf();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Active Chat State
// ─────────────────────────────────────────────────────────────────────────────

class ActiveChatState {
  final int? sessionId;
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? error;

  const ActiveChatState({
    this.sessionId,
    this.messages = const [],
    this.isLoading = false,
    this.error,
  });

  ActiveChatState copyWith({
    int? sessionId,
    List<ChatMessage>? messages,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      ActiveChatState(
        sessionId: sessionId ?? this.sessionId,
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

final activeChatProvider =
    StateNotifierProvider<ActiveChatNotifier, ActiveChatState>(
  (ref) => ActiveChatNotifier(ref),
);

class ActiveChatNotifier extends StateNotifier<ActiveChatState> {
  final Ref _ref;
  ActiveChatNotifier(this._ref) : super(const ActiveChatState());

  /// Load (or create) a session and fetch its history from DB.
  Future<void> loadSession(int sessionId) async {
    state = state.copyWith(
        sessionId: sessionId, messages: [], isLoading: true, clearError: true);
    try {
      final db = DatabaseService();
      final rows = await db.getChatMessages(sessionId);
      final messages = rows.map(ChatMessage.fromMap).toList();

      final profile = await db.getUserProfile();
      final nativeLang = profile?['native_language'] as String? ?? 'English';

      // Pre-load Gemini history so the model has context
      _ref
          .read(aiPartnerServiceProvider)
          .loadHistory(sessionId, messages, nativeLang);
      state = state.copyWith(messages: messages, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> sendMessage(String text) async {
    final sessionId = state.sessionId;
    if (sessionId == null || text.trim().isEmpty) return;

    final db = DatabaseService();
    final service = _ref.read(aiPartnerServiceProvider);

    // Optimistically add user message to UI
    final userMsg = ChatMessage(
      sessionId: sessionId,
      sender: 'user',
      content: text.trim(),
      timestamp: DateTime.now(),
    );
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
      clearError: true,
    );

    try {
      // Persist user message
      await db.addChatMessage(
          sessionId: sessionId, sender: 'user', content: text.trim());

      final profile = await db.getUserProfile();
      final nativeLang = profile?['native_language'] as String? ?? 'English';

      // Call Gemini
      final result = await service.sendMessage(sessionId, text.trim(),
          explanationLanguage: nativeLang);

      // Persist AI message
      final aiMsgId = await db.addChatMessage(
          sessionId: sessionId, sender: 'ai', content: result.reply);

      // Persist correction if present
      int? correctionDbId;
      if (result.correction != null) {
        final c = result.correction!;
        correctionDbId = await db.addCorrection(
          messageId: aiMsgId,
          sessionId: sessionId,
          originalText: c.original,
          correctedText: c.corrected,
          explanation: c.explanation,
          category: c.category,
        );
        // Notify history provider to reload
        _ref.invalidate(correctionHistoryProvider);
      }

      final aiMsg = ChatMessage(
        id: aiMsgId,
        sessionId: sessionId,
        sender: 'ai',
        content: result.reply,
        timestamp: DateTime.now(),
        correction: result.correction != null
            ? CorrectionData(
                id: correctionDbId,
                original: result.correction!.original,
                corrected: result.correction!.corrected,
                explanation: result.correction!.explanation,
                category: result.correction!.category,
              )
            : null,
      );

      // Auto-name the session after first exchange
      if (state.messages.length <= 1) {
        final title = text.trim().length > 40
            ? '${text.trim().substring(0, 40)}…'
            : text.trim();
        await db.updateChatSessionTitle(sessionId, title);
        _ref.invalidate(chatSessionsProvider);
      }

      state = state.copyWith(
        messages: [...state.messages, aiMsg],
        isLoading: false,
      );
    } catch (e) {
      debugPrint('ActiveChatNotifier.sendMessage error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
  void reset() => state = const ActiveChatState();
}

// ─────────────────────────────────────────────────────────────────────────────
// Correction History
// ─────────────────────────────────────────────────────────────────────────────

class HistoryState {
  final List<CorrectionData> corrections;
  final bool isLoading;
  final String? error;
  final String searchQuery;
  final String
      selectedCategory; // 'all' | 'grammar' | 'spelling' | 'naturalness'

  const HistoryState({
    this.corrections = const [],
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
    this.selectedCategory = 'all',
  });

  HistoryState copyWith({
    List<CorrectionData>? corrections,
    bool? isLoading,
    String? error,
    String? searchQuery,
    String? selectedCategory,
  }) =>
      HistoryState(
        corrections: corrections ?? this.corrections,
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        searchQuery: searchQuery ?? this.searchQuery,
        selectedCategory: selectedCategory ?? this.selectedCategory,
      );
}

final correctionHistoryProvider =
    StateNotifierProvider<HistoryNotifier, HistoryState>(
  (ref) => HistoryNotifier(),
);

class HistoryNotifier extends StateNotifier<HistoryState> {
  HistoryNotifier() : super(const HistoryState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final rows = await DatabaseService().getCorrections(
        category:
            state.selectedCategory == 'all' ? null : state.selectedCategory,
        searchQuery: state.searchQuery.isEmpty ? null : state.searchQuery,
      );
      state = state.copyWith(
        corrections: rows.map(CorrectionData.fromMap).toList(),
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> setCategory(String category) async {
    state = state.copyWith(selectedCategory: category);
    await load();
  }

  Future<void> setSearch(String query) async {
    state = state.copyWith(searchQuery: query);
    await load();
  }

  Future<void> updateNote(int id, String note) async {
    await DatabaseService().updateCorrectionNote(id, note);
    // Update in-memory list too
    final updated = state.corrections.map((c) {
      if (c.id == id) {
        c.userNote = note;
        return c;
      }
      return c;
    }).toList();
    state = state.copyWith(corrections: updated);
  }

  Future<void> deleteCorrection(int id) async {
    await DatabaseService().deleteCorrection(id);
    state = state.copyWith(
      corrections: state.corrections.where((c) => c.id != id).toList(),
    );
  }
}
