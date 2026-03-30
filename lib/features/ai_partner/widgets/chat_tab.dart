import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/constants/app_colors.dart';
import '../ai_partner_providers.dart';
import '../../../services/ai_partner_service.dart';
import '../../reader/widgets/translation_sheet.dart';
import 'correction_inform_box.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

class ChatTab extends ConsumerStatefulWidget {
  const ChatTab({super.key});

  @override
  ConsumerState<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends ConsumerState<ChatTab> {
  final _msgController = TextEditingController();
  final _scrollController = ScrollController();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  final FlutterTts _flutterTts = FlutterTts();
  bool _voiceMode = true; // Default to true based on user request

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initTts();
  }

  void _initSpeech() async {
    await _speech.initialize();
  }

  void _initTts() async {
    await _flutterTts.setLanguage(
        "en-US"); // Default language, you can match to AI detection
    await _flutterTts.setSpeechRate(0.5);
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            setState(() {
              _msgController.text = val.recognizedWords;
            });
          },
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _flutterTts.stop();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _ensureSession() async {
    final state = ref.read(activeChatProvider);
    if (state.sessionId == null) {
      final id = await ref.read(chatSessionsProvider.notifier).createSession();
      await ref.read(activeChatProvider.notifier).loadSession(id);
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    await _ensureSession();
    _msgController.clear();
    await ref.read(activeChatProvider.notifier).sendMessage(text);
    _scrollToBottom();
  }

  Future<void> _startNewSession() async {
    ref.read(activeChatProvider.notifier).reset();
    final id = await ref
        .read(chatSessionsProvider.notifier)
        .createSession(title: 'New Chat');
    await ref.read(activeChatProvider.notifier).loadSession(id);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ActiveChatState>(activeChatProvider, (previous, next) {
      if (_voiceMode && next.messages.isNotEmpty && !next.isLoading) {
        final lastMsg = next.messages.last;
        final prevLen = previous?.messages.length ?? 0;
        if (lastMsg.sender == 'ai' && next.messages.length > prevLen) {
          _flutterTts.speak(lastMsg.content);
        }
      }
    });

    final chatState = ref.watch(activeChatProvider);
    final sessions = ref.watch(chatSessionsProvider);

    // Auto-scroll when messages change
    if (chatState.messages.isNotEmpty) _scrollToBottom();

    return Column(
      children: [
        // ── Session header bar ─────────────────────────────────────────────
        Container(
          color: Theme.of(context).colorScheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // Session picker
              Expanded(
                child: sessions.when(
                  data: (list) => list.isEmpty
                      ? Text('New Chat',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 14))
                      : _SessionDropdown(
                          sessions: list,
                          activeId: chatState.sessionId,
                          onChanged: (id) => ref
                              .read(activeChatProvider.notifier)
                              .loadSession(id),
                        ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ),
              // New chat button
              IconButton(
                icon: const Icon(Icons.add_comment_outlined, size: 20),
                color: AppColors.primaryLight,
                tooltip: 'New Chat',
                onPressed: _startNewSession,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // ── Message list ───────────────────────────────────────────────────
        Expanded(
          child: chatState.messages.isEmpty
              ? _EmptyChat(onStart: _ensureSession)
              : ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  itemCount: chatState.messages.length,
                  itemBuilder: (ctx, i) {
                    final msg = chatState.messages[i];
                    return _MessageTile(message: msg);
                  },
                ),
        ),
        // ── Error banner ───────────────────────────────────────────────────
        if (chatState.error != null)
          Container(
            color: AppColors.error.withOpacity(0.1),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    size: 16, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    chatState.error!.contains('GEMINI_API_KEY')
                        ? 'Gemini API key not configured.'
                        : chatState.error!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close,
                      size: 16, color: AppColors.textSecondary),
                  onPressed: () =>
                      ref.read(activeChatProvider.notifier).clearError(),
                )
              ],
            ),
          ),
        // ── Input bar ─────────────────────────────────────────────────────
        _InputBar(
          controller: _msgController,
          isLoading: chatState.isLoading,
          onSend: _sendMessage,
          isListening: _isListening,
          onListen: _listen,
          voiceMode: _voiceMode,
          onToggleVoiceMode: () => setState(() => _voiceMode = !_voiceMode),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _SessionDropdown extends StatelessWidget {
  final List<ChatSession> sessions;
  final int? activeId;
  final ValueChanged<int> onChanged;

  const _SessionDropdown({
    required this.sessions,
    required this.activeId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final active = sessions.firstWhere(
      (s) => s.id == activeId,
      orElse: () => sessions.first,
    );
    return GestureDetector(
      onTap: () => _showSessionSheet(context),
      child: Row(
        children: [
          const Icon(Icons.chat_bubble_outline,
              size: 15, color: AppColors.primaryLight),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              active.title,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
        ],
      ),
    );
  }

  void _showSessionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _SessionPickerSheet(
          sessions: sessions, activeId: activeId, onPick: onChanged),
    );
  }
}

class _SessionPickerSheet extends StatelessWidget {
  final List<ChatSession> sessions;
  final int? activeId;
  final ValueChanged<int> onPick;
  const _SessionPickerSheet(
      {required this.sessions, required this.activeId, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Chat Sessions', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: sessions.length,
              itemBuilder: (_, i) {
                final s = sessions[i];
                return ListTile(
                  selected: s.id == activeId,
                  selectedColor: AppColors.primaryLight,
                  leading: const Icon(Icons.chat_bubble_outline, size: 18),
                  title: Text(s.title,
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(context);
                    onPick(s.id!);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _MessageTile extends StatelessWidget {
  final ChatMessage message;
  const _MessageTile({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final textStyle = TextStyle(
      color: isUser ? Colors.white : AppColors.textPrimary,
      fontSize: 14,
      height: 1.45,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser) ...[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.secondary.withOpacity(0.2),
                  child: const Icon(Icons.auto_awesome,
                      size: 14, color: AppColors.secondary),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser
                        ? AppColors.primary
                        : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                    border: isUser
                        ? null
                        : Border.all(color: AppColors.border, width: 1),
                  ),
                  child: isUser
                      ? Text(message.content, style: textStyle)
                      : SelectionArea(
                          contextMenuBuilder: (context, selectableRegionState) {
                            final List<ContextMenuButtonItem> buttonItems =
                                selectableRegionState.contextMenuButtonItems;

                            final selectedText = selectableRegionState
                                .textEditingValue.selection
                                .textInside(
                                    selectableRegionState.textEditingValue.text)
                                .trim();

                            if (selectedText.isNotEmpty) {
                              buttonItems.insert(
                                0,
                                ContextMenuButtonItem(
                                  label: 'Translate',
                                  onPressed: () {
                                    ContextMenuController.removeAny();
                                    _showTranslation(context, selectedText);
                                  },
                                ),
                              );
                            }

                            return AdaptiveTextSelectionToolbar.buttonItems(
                              anchors: selectableRegionState.contextMenuAnchors,
                              buttonItems: buttonItems,
                            );
                          },
                          child: MarkdownBody(
                            data: message.content,
                            selectable: false,
                            styleSheet: MarkdownStyleSheet(
                              p: textStyle,
                              listBullet: textStyle,
                            ),
                          ),
                        ),
                ),
              ),
              if (isUser) const SizedBox(width: 8),
            ],
          ),
          // Correction inform box (AI messages only)
          if (!isUser && message.correction != null)
            CorrectionInformBox(correction: message.correction!),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showTranslation(BuildContext context, String word) {
    // Strip common punctuation around the ends if needed, though TranslationSheet often handles raw words well enough.
    final lookupWord = word.replaceAll(
        RegExp(r'^[^\w\s\u00C0-\u00FF]+|[^\w\s\u00C0-\u00FF]+$'), '');

    // Import translation_sheet here lazily or assume flutter analyze will catch it.
    // We already have `showModalBottomSheet` available.
    // Need to use the explicit import of translation_sheet.dart. I will add it via another tool if missing.
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 1.0,
        expand: false,
        builder: (_, controller) => TranslationSheet(
          word: lookupWord.isEmpty ? word : lookupWord,
          sentence: message.content,
          scrollController: controller,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _EmptyChat extends StatelessWidget {
  final VoidCallback onStart;
  const _EmptyChat({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.secondary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome,
                  size: 36, color: AppColors.secondary),
            ),
            const SizedBox(height: 20),
            const Text(
              'Start a conversation',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Practice your target language. I\'ll gently correct mistakes and explain why.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onSend;
  final bool isListening;
  final VoidCallback onListen;
  final bool voiceMode;
  final VoidCallback onToggleVoiceMode;

  const _InputBar({
    required this.controller,
    required this.isLoading,
    required this.onSend,
    required this.isListening,
    required this.onListen,
    required this.voiceMode,
    required this.onToggleVoiceMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: const Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                minLines: 1,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Type a message…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide:
                        const BorderSide(color: AppColors.border, width: 1.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide:
                        const BorderSide(color: AppColors.border, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  isDense: true,
                ),
                onSubmitted: (_) => isLoading ? null : onSend(),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(
                voiceMode ? Icons.volume_up : Icons.volume_off,
                color: voiceMode ? AppColors.primary : AppColors.textSecondary,
              ),
              onPressed: onToggleVoiceMode,
              tooltip: 'Toggle AI Voice',
            ),
            GestureDetector(
              onTap: onListen,
              child: Material(
                color: isListening ? AppColors.error : AppColors.secondary,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(isListening ? Icons.mic : Icons.mic_none,
                      size: 20, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isLoading
                  ? const SizedBox(
                      key: ValueKey('loading'),
                      width: 42,
                      height: 42,
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: AppColors.primary),
                      ),
                    )
                  : Material(
                      key: const ValueKey('send'),
                      color: AppColors.primary,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: onSend,
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(Icons.send_rounded,
                              size: 20, color: Colors.white),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
