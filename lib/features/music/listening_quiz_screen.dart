import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:spotify_sdk/models/player_state.dart' as sp;
import 'package:spotify_sdk/spotify_sdk.dart';
import '../../core/constants/app_colors.dart';
import '../../services/music_service.dart';
import '../../services/spotify_service.dart';
import '../../core/widgets/pixel_card.dart';

class QuizBlank {
  final int lineIndex;
  final String originalWord;
  final int start;
  final int end;
  String userAnswer = '';
  bool isChecked = false;

  QuizBlank({
    required this.lineIndex,
    required this.originalWord,
    required this.start,
    required this.end,
  });
  
  bool get isCorrect => userAnswer.trim().toLowerCase() == originalWord.trim().toLowerCase();
}

class ListeningQuizScreen extends StatefulWidget {
  final TrackModel track;
  final LyricsModel lyrics;
  final String? audioUrl;
  final bool usingSpotify;

  const ListeningQuizScreen({
    super.key,
    required this.track,
    required this.lyrics,
    this.audioUrl,
    this.usingSpotify = false,
  });

  @override
  State<ListeningQuizScreen> createState() => _ListeningQuizScreenState();
}

class _ListeningQuizScreenState extends State<ListeningQuizScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final SpotifyService _spotifyService = SpotifyService();
  
  bool _isPlaying = false;
  bool _isSpotifyPlaying = false;
  
  late List<String> _lines;
  final List<QuizBlank> _blanks = [];
  bool _isFinished = false;
  StreamSubscription<sp.PlayerState>? _spotifyStateSub;

  @override
  void initState() {
    super.initState();
    if (widget.usingSpotify) {
      _subscribeSpotify();
    } else {
      _setupAudio();
    }
    _generateQuiz();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _spotifyStateSub?.cancel();
    super.dispose();
  }

  Future<void> _setupAudio() async {
    final urlToPlay = widget.audioUrl ?? widget.track.previewUrl;
    if (urlToPlay != null) {
      try {
        if (_isFilePath(urlToPlay)) {
          await _audioPlayer.setFilePath(urlToPlay);
        } else {
          print("[AUDIO_DEBUG] Setting Quiz Audio Source URL: $urlToPlay");
          final headers = _buildHeaders(urlToPlay);
          await _audioPlayer.setAudioSource(AudioSource.uri(Uri.parse(urlToPlay), headers: headers));
          print("[AUDIO_DEBUG] Quiz Audio source set successfully");
        }
        
        _audioPlayer.playerStateStream.listen((state) {
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
      } catch (e) {
        print('Error loading audio for quiz: \$e');
      }
    }
  }

  void _subscribeSpotify() {
    _spotifyStateSub?.cancel();
    _spotifyStateSub = SpotifySdk.subscribePlayerState().listen((state) {
      if (!mounted) return;
      setState(() {
        _isSpotifyPlaying = !state.isPaused;
      });
    }, onError: (_, __) {});
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

  void _generateQuiz() {
    final rawLines = widget.lyrics.plainLyrics.split('\n');
    _lines = rawLines.where((l) => l.trim().isNotEmpty).toList();
    
    // Pick up to 10 random lines to have a blank
    final rng = Random();
    final candidateLines = List<int>.generate(_lines.length, (i) => i);
    candidateLines.shuffle(rng);
    
    int blanksCreated = 0;
    
    final letterRegex = RegExp(r'\p{L}+', unicode: true);
    const minWordLen = 2;

    for (final lineIdx in candidateLines) {
      if (blanksCreated >= 10) break;
      
      final line = _lines[lineIdx];
      final matches = letterRegex.allMatches(line).toList();
      final candidates =
          matches.where((m) => (m.group(0)?.length ?? 0) >= minWordLen).toList();
      if (candidates.isEmpty) continue;

      final chosen = candidates[rng.nextInt(candidates.length)];
      final actualWord = chosen.group(0) ?? '';
      _blanks.add(QuizBlank(
        lineIndex: lineIdx,
        originalWord: actualWord,
        start: chosen.start,
        end: chosen.end,
      ));
      blanksCreated++;
    }
  }

  void _checkAnswers() {
    setState(() {
      _isFinished = true;
      for (var b in _blanks) {
        b.isChecked = true;
      }
    });
    
    final correctCount = _blanks.where((b) => b.isCorrect).length;
    
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(correctCount == _blanks.length ? 'Perfect!' : 'Result'),
        content: Text('You got $correctCount out of ${_blanks.length} correct.'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Review Answers'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Listening Quiz'),
        actions: [
          if (!_isFinished && _blanks.isNotEmpty)
            TextButton.icon(
              onPressed: _checkAnswers,
              icon: const Icon(Icons.check_circle_outline, color: AppColors.primary),
              label: const Text('Check', style: TextStyle(color: AppColors.primary)),
            )
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            widget.usingSpotify ? _buildSpotifyHeader() : _buildPlayControl(),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: _blanks.isEmpty ? _buildNoQuiz() : _buildQuizList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayControl() {
    void togglePlayPause() {
      if (_isPlaying) {
        _audioPlayer.pause();
      } else {
        _audioPlayer.play();
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Listen and fill in the blanks',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                widget.audioUrl != null && widget.audioUrl != widget.track.previewUrl
                    ? 'Full Song'
                    : '30 Sec Preview',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ],
          ),
          FloatingActionButton(
            mini: true,
            onPressed: togglePlayPause,
            child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSpotifyPlayPause() async {
    if (_isSpotifyPlaying) {
      await _spotifyService.pause();
    } else {
      await _spotifyService.resume();
    }
  }

  Widget _buildSpotifyHeader() {
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
                const Text(
                  'Spotify playback',
                  style: TextStyle(
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
                  _isSpotifyPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: AppColors.primary,
                ),
                onPressed: _toggleSpotifyPlayPause,
              ),
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

  Widget _buildNoQuiz() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32.0),
        child: Text(
          "Not enough suitable words found in the lyrics to create a quiz.",
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildQuizList() {
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: _lines.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final line = _lines[index];
        final blank = _blanks.where((b) => b.lineIndex == index).firstOrNull;
        
        if (blank == null) {
          // Normal line
          return Text(
            line,
            style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
            textAlign: TextAlign.center,
          );
        } else {
          // Line with a blank
          return _buildLineWithBlank(line, blank);
        }
      },
    );
  }

  Widget _buildLineWithBlank(String line, QuizBlank blank) {
    final spans = <InlineSpan>[];
    final prefix = line.substring(0, blank.start);
    final suffix = line.substring(blank.end);

    if (prefix.isNotEmpty) {
      spans.add(TextSpan(text: prefix, style: const TextStyle(fontSize: 16, color: AppColors.textPrimary)));
    }

    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          width: 80,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: TextField(
            enabled: !_isFinished,
            onChanged: (val) => blank.userAnswer = val,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _isFinished
                  ? (blank.isCorrect ? AppColors.success : AppColors.error)
                  : AppColors.primary,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              hintText: '...',
              hintStyle: const TextStyle(color: AppColors.textSecondary),
              errorText: _isFinished && !blank.isCorrect ? blank.originalWord : null,
              errorStyle: const TextStyle(height: 0.8),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.primary, width: 2),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.primary, width: 3),
              ),
              disabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.transparent),
              ),
            ),
          ),
        ),
      ),
    );

    if (suffix.isNotEmpty) {
      spans.add(TextSpan(text: suffix, style: const TextStyle(fontSize: 16, color: AppColors.textPrimary)));
    }
    
    return RichText(
      textAlign: TextAlign.center,
        text: TextSpan(
          style: const TextStyle(fontSize: 16, height: 1.8, color: AppColors.textPrimary),
          children: spans,
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
}
