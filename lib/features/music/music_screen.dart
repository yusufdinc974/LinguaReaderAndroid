import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../services/music_service.dart';
import '../../services/spotify_service.dart';
import 'package:spotify_sdk/spotify_sdk.dart';
import 'lyrics_reader_screen.dart';

final musicServiceProvider = Provider((ref) => MusicService());

class MusicScreen extends ConsumerStatefulWidget {
  const MusicScreen({super.key});

  @override
  ConsumerState<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends ConsumerState<MusicScreen> {
  final TextEditingController _searchController = TextEditingController();
  final SpotifyService _spotifyService = SpotifyService();
  List<TrackModel> _searchResults = [];
  List<SpotifyTrackSummary> _recentTracks = [];
  List<SpotifyTrackSummary> _likedTracks = [];
  bool _isLoading = false;
  bool _isLoadingLibrary = false;
  String? _error;
  bool _spotifyReady = false;
  bool _isConnectingSpotify = false;
  String? _spotifyError;
  StreamSubscription? _spotifyConnectionSub;

  @override
  void dispose() {
    _searchController.dispose();
    _spotifyConnectionSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _spotifyReady = _spotifyService.isConnected;
    if (_spotifyReady) {
      _loadSpotifyLibrary();
    }
    _subscribeSpotifyConnection();
  }

  void _subscribeSpotifyConnection() {
    _spotifyConnectionSub?.cancel();
    _spotifyConnectionSub = SpotifySdk.subscribeConnectionStatus().listen((status) {
      if (!mounted) return;
      _spotifyService.setConnectionStatus(status.connected);
      setState(() {
        _spotifyReady = status.connected;
      });
      if (status.connected) {
        _loadSpotifyLibrary();
      } else if (status.hasError()) {
        final parts = <String>[];
        if (status.errorCode?.isNotEmpty == true) parts.add(status.errorCode!);
        if (status.message?.isNotEmpty == true) parts.add(status.message!);
        if (status.errorDetails?.isNotEmpty == true) {
          parts.add(status.errorDetails!);
        }
        if (parts.isNotEmpty) {
          setState(() {
            _spotifyError = parts.join(' | ');
          });
        }
      }
    }, onError: (_) {});
  }

  Future<void> _handleSpotifyConnect() async {
    if (_isConnectingSpotify) return;
    setState(() {
      _isConnectingSpotify = true;
      _spotifyError = null;
    });
    try {
      final connected = await _spotifyService.connectRemote();
      if (mounted) {
        setState(() {
          _spotifyReady = connected;
        });
      }
      _spotifyService.setConnectionStatus(connected);
      if (connected) {
        await _loadSpotifyLibrary();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _spotifyError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnectingSpotify = false;
        });
      }
    }
  }

  Future<void> _loadSpotifyLibrary() async {
    if (_isLoadingLibrary || !_spotifyReady) return;
    setState(() {
      _isLoadingLibrary = true;
    });
    try {
      final recent = await _spotifyService.fetchRecentlyPlayed(limit: 10);
      final liked = await _spotifyService.fetchLikedTracks(limit: 10);
      if (mounted) {
        setState(() {
          _recentTracks = recent;
          _likedTracks = liked;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _spotifyError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLibrary = false;
        });
      }
    }
  }

  Future<void> _performSearch() async {
    if (!_spotifyReady) {
      setState(() {
        _error = 'Connect Spotify to search songs.';
      });
      return;
    }
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _searchResults = [];
    });

    try {
      final service = ref.read(musicServiceProvider);
      final results = await service.searchTracks(query);

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoading = false;
          if (results.isEmpty) _error = 'No tracks found for "$query".';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error searching tracks: \$e';
          _isLoading = false;
        });
      }
    }
  }

  void _openTrack(TrackModel track) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LyricsReaderScreen(track: track),
      ),
    );
  }

  void _openSpotifyTrack(SpotifyTrackSummary track) {
    _openTrack(TrackModel(
      id: track.id,
      title: track.name,
      artist: track.artist,
      albumArtUrl: track.albumArtUrl,
      previewUrl: null,
      durationMs: track.durationMs,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!_spotifyReady) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Study with Music'),
        ),
        body: _buildSpotifyGate(),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Study with Music'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search for a song or artist...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => _performSearch(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _performSearch,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Search'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.error)))
                    : _buildConnectedBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedBody() {
    if (_isLoadingLibrary) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (_spotifyError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _spotifyError!,
              style: const TextStyle(color: AppColors.warning),
            ),
          ),
        _buildSectionTitle('Recently Played'),
        const SizedBox(height: 8),
        _buildHorizontalList(
          _recentTracks,
          emptyLabel: 'No recent Spotify activity yet.',
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('Liked Songs'),
        const SizedBox(height: 8),
        _buildHorizontalList(
          _likedTracks,
          emptyLabel: 'No liked songs found.',
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('Search Results'),
        const SizedBox(height: 8),
        _searchResults.isEmpty
            ? const Text(
                'Search for a song to start.',
                style: TextStyle(color: AppColors.textSecondary),
              )
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _searchResults.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final track = _searchResults[index];
                  return _buildTrackCard(track);
                },
              ),
      ],
    );
  }

  Widget _buildTrackCard(TrackModel track) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      color: Theme.of(context).colorScheme.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openTrack(track),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: track.albumArtUrl != null
                    ? Image.network(
                        track.albumArtUrl!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildPlaceholder(),
                      )
                    : _buildPlaceholder(),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artist,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 64,
      height: 64,
      color: AppColors.surfaceHighlight,
      child: const Icon(Icons.music_note, color: AppColors.textSecondary),
    );
  }

  Widget _buildSpotifyGate() {
    const spotifyGreen = Color(0xFF1DB954);
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.surfaceGradient,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Connect Spotify',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Before searching songs, connect your Spotify account.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: 16),
              if (_spotifyError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _spotifyError!,
                    style: const TextStyle(color: AppColors.warning),
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Conditions to use this feature:',
                      style: TextStyle(
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
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            _isConnectingSpotify ? null : _handleSpotifyConnect,
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
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _buildSectionTitle('What you get'),
              const SizedBox(height: 8),
              _buildBenefitRow('Full-length playback controlled in-app.'),
              _buildBenefitRow('Lyrics, quizzes, and translation tools.'),
              _buildBenefitRow('Quick access to recent and liked songs.'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
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

  Widget _buildBenefitRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.star, size: 16, color: AppColors.primaryLight),
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

  Widget _buildHorizontalList(
    List<SpotifyTrackSummary> tracks, {
    required String emptyLabel,
  }) {
    if (tracks.isEmpty) {
      return Text(
        emptyLabel,
        style: const TextStyle(color: AppColors.textSecondary),
      );
    }
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tracks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final track = tracks[index];
          return _buildSpotifyCard(track);
        },
      ),
    );
  }

  Widget _buildSpotifyCard(SpotifyTrackSummary track) {
    return GestureDetector(
      onTap: () => _openSpotifyTrack(track),
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: track.albumArtUrl != null
                  ? Image.network(
                      track.albumArtUrl!,
                      width: 116,
                      height: 76,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildSmallPlaceholder(),
                    )
                  : _buildSmallPlaceholder(),
            ),
            const SizedBox(height: 8),
            Text(
              track.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallPlaceholder() {
    return Container(
      width: 116,
      height: 76,
      color: AppColors.surfaceHighlight,
      child: const Icon(Icons.music_note, color: AppColors.textSecondary),
    );
  }
}
