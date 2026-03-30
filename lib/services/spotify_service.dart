import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:spotify_sdk/spotify_sdk.dart';

class SpotifyTrackSummary {
  final String id;
  final String name;
  final String artist;
  final String? albumArtUrl;
  final String uri;
  final int durationMs;

  const SpotifyTrackSummary({
    required this.id,
    required this.name,
    required this.artist,
    required this.uri,
    required this.durationMs,
    this.albumArtUrl,
  });

  factory SpotifyTrackSummary.fromTrackJson(Map<String, dynamic> track) {
    final artists = track['artists'];
    String artistName = '';
    if (artists is List && artists.isNotEmpty) {
      final first = artists.first;
      if (first is Map && first['name'] != null) {
        artistName = first['name'].toString();
      }
    }

    String? imageUrl;
    final album = track['album'];
    if (album is Map) {
      final images = album['images'];
      if (images is List && images.isNotEmpty) {
        final firstImage = images.first;
        if (firstImage is Map && firstImage['url'] != null) {
          imageUrl = firstImage['url'].toString();
        }
      }
    }

    return SpotifyTrackSummary(
      id: track['id']?.toString() ?? '',
      name: track['name']?.toString() ?? '',
      artist: artistName,
      uri: track['uri']?.toString() ?? '',
      durationMs: track['duration_ms'] is int ? track['duration_ms'] as int : 0,
      albumArtUrl: imageUrl,
    );
  }
}

class SpotifyService {
  static final SpotifyService instance = SpotifyService._();
  factory SpotifyService() => instance;
  SpotifyService._();

  static const String _clientIdEnv = 'SPOTIFY_CLIENT_ID';
  static const String _redirectUriEnv = 'SPOTIFY_REDIRECT_URI';
  static const String _scope =
      'app-remote-control,user-read-playback-state,user-modify-playback-state,'
      'user-read-recently-played,user-library-read';

  String get _clientId => const String.fromEnvironment(_clientIdEnv);
  String get _redirectUri => const String.fromEnvironment(
        _redirectUriEnv,
        defaultValue: 'com.yusufdinc.linguareader://spotify-auth',
      );

  String? get _market {
    try {
      final code = ui.PlatformDispatcher.instance.locale.countryCode;
      if (code != null && code.length == 2) return code.toUpperCase();
    } catch (_) {}
    return null;
  }

  String? _accessToken;
  DateTime? _accessTokenTime;
  bool _isConnected = false;

  Future<bool> connect() async {
    _ensureConfigured();
    if (_isConnected) {
      return true;
    }
    try {
      print('[SPOTIFY] Connecting to App Remote...');
      final connected = await SpotifySdk.connectToSpotifyRemote(
        clientId: _clientId,
        redirectUrl: _redirectUri,
        scope: _scope,
      ).timeout(const Duration(seconds: 12));
      print('[SPOTIFY] App Remote connected: $connected');
      if (!connected) {
        throw Exception(
          'Could not connect to Spotify. Is the Spotify app installed and you are logged in?',
        );
      }
      _isConnected = true;
      return connected;
    } on TimeoutException {
      throw Exception(
        'Spotify did not respond. Open the Spotify app and try again.',
      );
    } on PlatformException catch (e) {
      throw Exception('Spotify connection failed: ${e.code} ${e.message}');
    }
  }

  Future<void> disconnect() async {
    try {
      await SpotifySdk.disconnect();
      _isConnected = false;
    } catch (_) {}
  }

  Future<String> _getAccessToken() async {
    _ensureConfigured();
    if (_accessToken != null && _accessTokenTime != null) {
      final age = DateTime.now().difference(_accessTokenTime!);
      if (age.inMinutes < 45) {
        return _accessToken!;
      }
    }

    String token;
    try {
      print('[SPOTIFY] Requesting access token...');
      token = await SpotifySdk.getAccessToken(
        clientId: _clientId,
        redirectUrl: _redirectUri,
        scope: _scope,
      );
      print('[SPOTIFY] Access token received.');
    } on PlatformException catch (e) {
      throw Exception('Spotify auth failed: ${e.code} ${e.message}');
    }
    _accessToken = token;
    _accessTokenTime = DateTime.now();
    return token;
  }

  Future<String?> searchTrackUri({
    required String title,
    required String artist,
  }) async {
    final token = await _getAccessToken();
    final query = 'track:"$title" artist:"$artist"';
    print('[SPOTIFY] Search: $query');
    final queryParameters = <String, String>{
      'q': query,
      'type': 'track',
      'limit': '5',
    };
    final market = _market;
    if (market != null) {
      queryParameters['market'] = market;
    }
    final uri = Uri.https('api.spotify.com', '/v1/search', queryParameters);
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
      },
    );
    print('[SPOTIFY] Search status: ${response.statusCode}');
    if (response.statusCode != 200) {
      final body = response.body;
      final snippet = body.length > 600 ? '${body.substring(0, 600)}…' : body;
      throw Exception('Spotify search failed: ${response.statusCode} $snippet');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final tracks = data['tracks'] as Map<String, dynamic>?;
    final items = tracks?['items'];
    if (items is List && items.isNotEmpty) {
      final first = items.first as Map<String, dynamic>?;
      final uriValue = first?['uri']?.toString();
      print('[SPOTIFY] First track uri: $uriValue');
      return uriValue;
    }
    return null;
  }

  Future<bool> playTrackBySearch({
    required String title,
    required String artist,
  }) async {
    // Ensure the user is authorized before attempting App Remote connection.
    await _getAccessToken();
    final connected = await connect();
    if (!connected) return false;
    final uri = await searchTrackUri(title: title, artist: artist);
    if (uri == null || uri.isEmpty) return false;
    print('[SPOTIFY] Checking capabilities...');
    final capabilities =
        await SpotifySdk.getCapabilities(spotifyUri: uri);
    if (capabilities != null && !capabilities.canPlayOnDemand) {
      throw Exception(
        'Spotify Premium is required for on-demand playback on this account.',
      );
    }
    print('[SPOTIFY] Playing uri: $uri');
    await SpotifySdk.play(spotifyUri: uri);
    return true;
  }

  Future<String> getAccessToken() async {
    return _getAccessToken();
  }

  Future<bool> connectRemote() async {
    await _getAccessToken();
    return connect();
  }

  void setConnectionStatus(bool connected) {
    _isConnected = connected;
  }

  bool get isConnected => _isConnected;

  Future<List<SpotifyTrackSummary>> fetchRecentlyPlayed({int limit = 10}) async {
    return _fetchTrackList(
      Uri.https('api.spotify.com', '/v1/me/player/recently-played', {
        'limit': '$limit',
      }),
      itemsKey: 'items',
      trackKey: 'track',
    );
  }

  Future<List<SpotifyTrackSummary>> fetchLikedTracks({int limit = 10}) async {
    return _fetchTrackList(
      Uri.https('api.spotify.com', '/v1/me/tracks', {
        'limit': '$limit',
      }),
      itemsKey: 'items',
      trackKey: 'track',
    );
  }

  Future<List<SpotifyTrackSummary>> _fetchTrackList(
    Uri uri, {
    required String itemsKey,
    required String trackKey,
  }) async {
    final token = await _getAccessToken();
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 401) {
      _accessToken = null;
      _accessTokenTime = null;
      final retryToken = await _getAccessToken();
      final retryResponse = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $retryToken',
        },
      );
      return _parseTrackList(retryResponse, itemsKey, trackKey);
    }
    return _parseTrackList(response, itemsKey, trackKey);
  }

  List<SpotifyTrackSummary> _parseTrackList(
    http.Response response,
    String itemsKey,
    String trackKey,
  ) {
    if (response.statusCode != 200) {
      final body = response.body;
      final snippet = body.length > 600 ? '${body.substring(0, 600)}…' : body;
      throw Exception('Spotify list failed: ${response.statusCode} $snippet');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data[itemsKey];
    if (items is! List) return [];
    final tracks = <SpotifyTrackSummary>[];
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final track = item[trackKey];
      if (track is Map<String, dynamic>) {
        tracks.add(SpotifyTrackSummary.fromTrackJson(track));
      }
    }
    return tracks;
  }

  Future<void> pause() async {
    await SpotifySdk.pause();
  }

  Future<void> resume() async {
    await SpotifySdk.resume();
  }

  void _ensureConfigured() {
    if (_clientId.isEmpty) {
      throw Exception(
          'Missing Spotify client id. Set --dart-define=SPOTIFY_CLIENT_ID=YOUR_ID');
    }
    if (_redirectUri.isEmpty) {
      throw Exception(
          'Missing Spotify redirect uri. Set --dart-define=SPOTIFY_REDIRECT_URI=your.scheme://your-host');
    }
  }
}
