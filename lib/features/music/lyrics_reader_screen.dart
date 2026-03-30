import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:spotify_sdk/models/connection_status.dart';
import 'package:spotify_sdk/models/player_state.dart' as sp;
import 'package:spotify_sdk/spotify_sdk.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/fox_sprite.dart';
import '../../services/music_service.dart';
import '../../services/spotify_service.dart';
import '../../services/database_service.dart';
import '../reader/widgets/translation_sheet.dart';
import 'listening_quiz_screen.dart';

class LyricsReaderScreen extends ConsumerStatefulWidget {
  final TrackModel track;

  const LyricsReaderScreen({super.key, required this.track});

  @override
  ConsumerState<LyricsReaderScreen> createState() => _LyricsReaderScreenState();
}

class _LyricsReaderScreenState extends ConsumerState<LyricsReaderScreen> {
  final DatabaseService _databaseService = DatabaseService();
  
  LyricsModel? _lyrics;
  bool _isLoading = true;
  String? _error;
  
  // Audio Player
  final AudioPlayer _audioPlayer = AudioPlayer();
  final SpotifyService _spotifyService = SpotifyService();
  
  bool _isPlaying = false;
  bool _isPlayerInit = false;
  String? _fullAudioUrl;
  String _audioStatus = 'Preparing audio...';
  bool _spotifyReady = false;
  List<_AudioCandidate> _audioCandidates = [];
  int _audioCandidateIndex = 0;
  bool _isSwitchingAudio = false;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<ConnectionStatus>? _spotifyConnectionSub;
  StreamSubscription<sp.PlayerState>? _spotifyStateSub;
  bool _usingSpotify = false;
  bool _isConnectingSpotify = false;
  
  // Highlights & Selection
  List<Map<String, dynamic>> _savedWords = [];
  String? _tempSelectedText;
  bool _showSelectionActions = false;

  @override
  void initState() {
    super.initState();
    _audioStatus = 'Spotify required';
    _loadSavedWords();
    _spotifyReady = _spotifyService.isConnected;
    _spotifyConnectionSub = SpotifySdk.subscribeConnectionStatus().listen(
      (status) {
        if (!mounted) return;
        _spotifyService.setConnectionStatus(status.connected);
        if (status.connected && !_spotifyReady && !_isConnectingSpotify) {
          setState(() {
            _spotifyReady = true;
            _isLoading = true;
          });
          _fetchLyrics();
          _connectSpotifyAndPlay();
        } else if (status.hasError()) {
          final parts = <String>[];
          if (status.errorCode?.isNotEmpty == true) {
            parts.add(status.errorCode!);
          }
          if (status.message?.isNotEmpty == true) {
            parts.add(status.message!);
          }
          if (status.errorDetails?.isNotEmpty == true) {
            parts.add(status.errorDetails!);
          }
          if (parts.isNotEmpty) {
            _showSnack('Spotify connection error: ${parts.join(' | ')}');
          }
        }
      },
      onError: (_) {},
    );
    if (_spotifyReady) {
      _fetchLyrics();
      _connectSpotifyAndPlay();
    }
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _playbackEventSub?.cancel();
    _spotifyConnectionSub?.cancel();
    _spotifyStateSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadSavedWords() async {
    try {
      final lists = await _databaseService.getWordLists();
      final listIds = lists.map((l) => l['id'] as int).toList();
      if (listIds.isNotEmpty) {
        final words = await _databaseService.getWordsWithColors(listIds: listIds);
        if (mounted) {
          setState(() {
            _savedWords = words;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchLyrics() async {
    final service = ref.read(Provider((ref) => MusicService()));
    
    try {
      final lyricsResult = await service.fetchLyrics(widget.track.title, widget.track.artist);
      if (mounted) {
        setState(() {
          _lyrics = lyricsResult;
          _isLoading = false;
          if (lyricsResult == null || lyricsResult.plainLyrics.isEmpty) {
            _error = "Lyrics not found for this track.";
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "Failed to load lyrics.";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _initAudioWithFallbacks(List<_AudioCandidate> candidates) async {
    _audioCandidates = candidates;
    _audioCandidateIndex = 0;
    _isSwitchingAudio = false;
    await _setAudioFromCandidate(candidates.first);
  }

  Future<bool> _connectSpotifyAndPlay() async {
    if (_isConnectingSpotify) return false;
    if (mounted) {
      setState(() {
        _isConnectingSpotify = true;
        _audioStatus = 'Connecting to Spotify...';
      });
    }
    _stopLocalPlayback();
    try {
      print('[SPOTIFY] Starting play flow...');
      final success = await _spotifyService.playTrackBySearch(
        title: widget.track.title,
        artist: widget.track.artist,
      );
      if (!mounted) return false;
      if (!success) {
        setState(() {
          _usingSpotify = false;
          _isPlayerInit = false;
          _audioStatus = 'Spotify track not found';
        });
        _showSnack('Spotify could not find this track.');
        return false;
      }
      setState(() {
        _usingSpotify = true;
        _isPlayerInit = true;
        _audioStatus = 'Spotify • connected';
      });
      _setupSpotifyListener();
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _usingSpotify = false;
        _isPlayerInit = false;
        _audioStatus = 'Spotify unavailable';
      });
      final message = e.toString();
      final needsOpen = message.contains('did not respond') ||
          message.contains('not installed') ||
          message.contains('NotLoggedInException');
      if (needsOpen) {
        _showSnack(
          'Spotify error: $e',
          actionLabel: 'Open Spotify',
          onAction: _openSpotifyApp,
        );
      } else {
        _showSnack('Spotify error: $e');
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isConnectingSpotify = false;
        });
      }
    }
    return _usingSpotify;
  }

  void _setupSpotifyListener() {
    _spotifyStateSub?.cancel();
    _spotifyStateSub = SpotifySdk.subscribePlayerState().listen((state) {
      if (!mounted || !_usingSpotify) return;
      setState(() {
        _isPlaying = !state.isPaused;
      });
    }, onError: (Object e, StackTrace st) {
      if (!mounted) return;
      _showSnack('Spotify playback error: $e');
    });
  }

  Future<void> _handleSpotifyConnect() async {
    final success = await _connectSpotifyAndPlay();
    if (!mounted) return;
    if (success) {
      setState(() {
        _spotifyReady = true;
        _isLoading = true;
      });
      await _fetchLyrics();
    }
  }

  void _stopLocalPlayback() {
    _audioPlayer.pause();
    _audioPlayer.seek(Duration.zero);
  }

  Future<void> _fallbackToPreview(String reason) async {
    if (!mounted) return;
    _usingSpotify = false;

    final previewUrl = widget.track.previewUrl;
    if (previewUrl == null || previewUrl.isEmpty) {
      setState(() {
        _audioStatus = reason;
        _isPlayerInit = false;
      });
      return;
    }

    setState(() {
      _audioStatus = 'Using 30s preview';
    });
    await _initAudioWithFallbacks([
      _AudioCandidate.url(previewUrl, 'Using 30s preview'),
    ]);
  }

  Future<void> _setAudioFromCandidate(_AudioCandidate candidate) async {
    try {
      _usingSpotify = false;
      if (candidate.source != null) {
        final source = candidate.source!;
        print('[AUDIO_DEBUG] Setting Audio Source (stream)');
        await _audioPlayer.setAudioSource(source);
      } else {
        final url = candidate.url!;
        if (_isFilePath(url)) {
          print('[AUDIO_DEBUG] Using local file for audio: $url');
          await _audioPlayer.setFilePath(url);
        } else {
          print("[AUDIO_DEBUG] Setting Audio Source URL: $url");
          final headers = _buildHeaders(url);
          await _audioPlayer
              .setAudioSource(AudioSource.uri(Uri.parse(url), headers: headers));
          print("[AUDIO_DEBUG] Audio source set successfully");
        }
      }
      _isPlayerInit = true;
      _fullAudioUrl = candidate.url;
      if (mounted) {
        setState(() {
          _audioStatus = _labelForCandidate(candidate);
        });
      }
      _setupAudioListener();
      _setupPlaybackErrorListener();
    } catch (e) {
      print('[AUDIO_DEBUG] Audio init failed: $e');
      await _tryNextAudioCandidate(reason: e.toString());
    }
  }

  Future<void> _tryNextAudioCandidate({String? reason}) async {
    if (_isSwitchingAudio) return;
    _isSwitchingAudio = true;
    try {
      final nextIndex = _audioCandidateIndex + 1;
      if (nextIndex >= _audioCandidates.length) {
        if (mounted) {
          setState(() {
            _audioStatus = 'Audio unavailable';
            _isPlayerInit = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              reason == null
                  ? 'Audio failed. Please try another track.'
                  : 'Audio failed: $reason',
            ),
            duration: const Duration(seconds: 4),
          ));
        }
        return;
      }

      _audioCandidateIndex = nextIndex;
      final nextCandidate = _audioCandidates[_audioCandidateIndex];
      if (mounted) {
        setState(() {
          _audioStatus =
              'Retrying audio (${_audioCandidateIndex + 1}/${_audioCandidates.length})';
        });
      }
      await _setAudioFromCandidate(nextCandidate);
    } finally {
      _isSwitchingAudio = false;
    }
  }

  void _setupPlaybackErrorListener() {
    _playbackEventSub?.cancel();
    _playbackEventSub = _audioPlayer.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) async {
        print('[AUDIO_DEBUG] Playback error: $e');
        await _tryNextAudioCandidate(reason: e.toString());
      },
    );
  }

  String _labelForCandidate(_AudioCandidate candidate) {
    if (candidate.label.isNotEmpty) return candidate.label;
    if (candidate.source != null) return 'Full song (stream)';
    if (candidate.url != null) return _labelForUrl(candidate.url!);
    return 'Preparing audio...';
  }

  String _labelForUrl(String url) {
    if (_isFilePath(url)) return 'Full song cached';
    if (widget.track.previewUrl != null && url == widget.track.previewUrl) {
      return 'Using 30s preview';
    }
    return 'Preparing audio...';
  }

  bool _isFilePath(String url) {
    final uri = Uri.tryParse(url);
    return uri == null || uri.scheme.isEmpty || uri.scheme == 'file';
  }

  Map<String, String> _buildHeaders(String url) {
    final headers = <String, String>{
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
    };
    return headers;
  }

  void _setupAudioListener() {
    _playerStateSub?.cancel();
    _playerStateSub = _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing && state.processingState != ProcessingState.completed;
        });
        if (state.processingState == ProcessingState.completed) {
          _audioPlayer.pause();
          _audioPlayer.seek(Duration.zero);
        }
      }
    });
  }

  void _togglePlayPause() {
    if (_usingSpotify) {
      if (_isPlaying) {
        _spotifyService.pause();
      } else {
        _spotifyService.resume();
      }
      return;
    }
    if (!_isPlayerInit) return;
    if (_isPlaying) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
    }
  }

  void _showSnack(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _openSpotifyApp() async {
    final uri = Uri.parse('spotify:');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showSnack('Spotify app is not available on this device.');
    }
  }

  void _clearSelectionState() {
    setState(() {
      _tempSelectedText = null;
      _showSelectionActions = false;
    });
  }

  Future<void> _copySelectedText() async {
    final text = _tempSelectedText?.trim();
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
    _clearSelectionState();
  }

  void _showTranslation(String text) async {
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 1.0,
        expand: false,
        builder: (_, controller) => TranslationSheet(
          word: text.trim(),
          sentence: "", 
          scrollController: controller,
        ),
      ),
    );

    _clearSelectionState();
    
    // Refresh words to highlight the newly saved word
    if (result != null) {
      _loadSavedWords();
    }
  }

  void _startQuiz() {
    if (_lyrics == null || _lyrics!.plainLyrics.isEmpty) return;
    if (_isPlaying) {
      _audioPlayer.pause();
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ListeningQuizScreen(
          track: widget.track,
          lyrics: _lyrics!,
          audioUrl: _fullAudioUrl ?? widget.track.previewUrl,
          usingSpotify: _usingSpotify,
        ),
      ),
    );
  }

  Color _parseColor(String? colorStr) {
    if (colorStr == null) return const Color(0xFF2196F3);
    try {
      if (colorStr.startsWith('#')) {
        final hex = colorStr.replaceAll('#', '');
        return Color(int.parse((hex.length == 6 ? 'FF' : '') + hex, radix: 16));
      } else if (colorStr.startsWith('0x')) {
        return Color(int.parse(colorStr));
      }
      return Color(int.parse(colorStr));
    } catch (_) {
      return const Color(0xFF2196F3);
    }
  }

  List<InlineSpan> _buildLyricsSpans(String text) {
    if (_savedWords.isEmpty) {
      return [TextSpan(text: text)];
    }
    
    final spans = <InlineSpan>[];
    
    // Create a fast lookup for lowercase clean words mapped to colors
    final wordColors = <String, Color>{};
    for (var sw in _savedWords) {
      final w = (sw['word'] as String).toLowerCase().trim();
      final c = _parseColor(sw['color'] as String?);
      wordColors[w] = c;
    }

    // Split text keeping punctuation and whitespace using regex
    // This regex splits by words vs non-words so we can reconstruct exactly
    final matches = RegExp(r"(\w+)|([^\w]+)").allMatches(text);
    
    for (final match in matches) {
      final segment = match.group(0)!;
      final clean = segment.toLowerCase();
      
      if (wordColors.containsKey(clean)) {
        spans.add(TextSpan(
          text: segment,
          style: TextStyle(
            backgroundColor: wordColors[clean]!.withValues(alpha: 0.4),
          ),
        ));
      } else {
        spans.add(TextSpan(text: segment));
      }
    }
    
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    if (!_spotifyReady) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Connect Spotify'),
        ),
        body: _buildSpotifyGate(),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.track.title),
        actions: [
          if (_lyrics != null && _lyrics!.plainLyrics.isNotEmpty)
            TextButton.icon(
              onPressed: _startQuiz,
              icon: const Icon(Icons.quiz, color: AppColors.primary),
              label: const Text('New Quiz', style: TextStyle(color: AppColors.primary)),
            )
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildPlayerHeader(),
                const Divider(height: 1, color: AppColors.border),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.error)))
                          : _buildLyricsContent(),
                ),
              ],
            ),
          ),
          
          if (_tempSelectedText != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 32,
              child: Card(
                elevation: 4,
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: AppColors.border, width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _showSelectionActions
                      ? Row(
                          children: [
                            Expanded(
                              child: _buildLargeActionButton(
                                icon: Icons.translate,
                                label: 'Translate',
                                onTap: () => _showTranslation(_tempSelectedText!),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildLargeActionButton(
                                icon: Icons.copy,
                                label: 'Copy',
                                onTap: _copySelectedText,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildLargeActionButton(
                                icon: Icons.close,
                                label: 'Cancel',
                                onTap: _clearSelectionState,
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Selection ready (${_tempSelectedText!.length} chars)',
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const FoxSpriteAnimator(
                              animation: FoxAnimation.walkWest,
                              size: 34,
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => setState(() => _showSelectionActions = true),
                              icon: const Icon(Icons.touch_app, size: 20),
                              label: const Text('Actions'),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(132, 52),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _clearSelectionState,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(88, 52),
                              ),
                              child: const Text('Clear'),
                            ),
                          ],
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLargeActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      ),
    );
  }

  Widget _buildPlayerHeader() {
    final canUsePlayPause = _usingSpotify || _isPlayerInit;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: widget.track.albumArtUrl != null
                ? Image.network(
                    widget.track.albumArtUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildPlaceholder(),
                  )
                : _buildPlaceholder(),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.track.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.track.artist,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _audioStatus,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                iconSize: 32,
                icon: Icon(
                  _isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: canUsePlayPause
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                onPressed: canUsePlayPause ? _togglePlayPause : null,
              ),
              if (!_usingSpotify)
                TextButton(
                  onPressed: _isConnectingSpotify ? null : _handleSpotifyConnect,
                  child: Text(
                    _isConnectingSpotify ? 'Spotify…' : 'Retry Spotify',
                    style: const TextStyle(fontSize: 12),
                  ),
                )
              else
                const Text(
                  'Spotify',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpotifyGate() {
    const spotifyGreen = Color(0xFF1DB954);
    final surface = Theme.of(context).colorScheme.surface;
    final border = AppColors.border;
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.surfaceGradient,
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: _buildGlowCircle(
              size: 220,
              color: spotifyGreen.withValues(alpha: 0.18),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -40,
            child: _buildGlowCircle(
              size: 260,
              color: AppColors.primary.withValues(alpha: 0.2),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Spotify Required',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Connect your Spotify account to play the full track while reading lyrics.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: spotifyGreen.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.graphic_eq,
                                color: spotifyGreen,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.track.title,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    widget.track.artist,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Conditions to use this feature:',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 12),
                        _buildConditionRow('Spotify app is installed and you are logged in.'),
                        _buildConditionRow('Spotify Premium is required for on-demand playback.'),
                        _buildConditionRow('You must approve access when prompted.'),
                        _buildConditionRow('Your account is added in Spotify Dashboard (if app is in dev mode).'),
                        _buildConditionRow('Keep Spotify running in the background.'),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isConnectingSpotify ? null : _handleSpotifyConnect,
                            icon: const Icon(Icons.link),
                            label: Text(
                              _isConnectingSpotify ? 'Connecting...' : 'Connect Spotify',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: spotifyGreen,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _openSpotifyApp,
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Open Spotify'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              side: const BorderSide(color: AppColors.border),
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Playback happens inside the Spotify app. '
                    'We only control it and show the lyrics here.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                          height: 1.4,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlowCircle({required double size, required Color color}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }

  Widget _buildConditionRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, size: 18, color: AppColors.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 48,
      height: 48,
      color: AppColors.surfaceHighlight,
      child: const Icon(Icons.music_note, color: AppColors.textSecondary),
    );
  }

  Widget _buildLyricsContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 96), // Extra bottom padding for floating card
      child: SelectableText.rich(
        TextSpan(
          children: _buildLyricsSpans(_lyrics!.plainLyrics),
          style: const TextStyle(
            fontSize: 18,
            height: 1.6,
            color: AppColors.textPrimary,
          ),
        ),
        textAlign: TextAlign.center,
        onSelectionChanged: (selection, cause) {
          final text = _lyrics!.plainLyrics;
          if (selection.baseOffset >= 0 && selection.extentOffset >= 0 && selection.baseOffset != selection.extentOffset) {
            final start = selection.baseOffset < selection.extentOffset ? selection.baseOffset : selection.extentOffset;
            final end = selection.baseOffset > selection.extentOffset ? selection.baseOffset : selection.extentOffset;
            final selected = text.substring(start, end).trim();
            
            if (selected.isNotEmpty) {
              setState(() {
                _tempSelectedText = selected;
                _showSelectionActions = false;
              });
            } else {
              _clearSelectionState();
            }
          } else {
            // Keep selection alive if they just tap inside it, 
            // but if they deselect we clear it. Since mobile SelectableText
            // behavior is quirky, we usually let clear button handle hiding.
          }
        },
      ),
    );
  }
}

class _AudioCandidate {
  final String? url;
  final AudioSource? source;
  final String label;

  const _AudioCandidate.url(this.url, this.label) : source = null;
  const _AudioCandidate.source(this.source, this.label) : url = null;
}
