import 'dart:convert';
import 'package:http/http.dart' as http;

class TrackModel {
  final String id;
  final String title;
  final String artist;
  final String? albumArtUrl;
  final String? previewUrl;
  final int durationMs;

  TrackModel({
    required this.id,
    required this.title,
    required this.artist,
    this.albumArtUrl,
    this.previewUrl,
    required this.durationMs,
  });

  factory TrackModel.fromJson(Map<String, dynamic> json) {
    return TrackModel(
      id: json['trackId']?.toString() ?? '',
      title: json['trackName'] ?? '',
      artist: json['artistName'] ?? '',
      albumArtUrl: json['artworkUrl100']?.replaceAll('100x100bb', '300x300bb'),
      previewUrl: json['previewUrl'],
      durationMs: json['trackTimeMillis'] ?? 0,
    );
  }
}

class LyricsModel {
  final String plainLyrics;
  final String? syncedLyrics;

  LyricsModel({required this.plainLyrics, this.syncedLyrics});
}

class MusicService {
  static const String _itunesSearchUrl = 'https://itunes.apple.com/search';
  static const String _lrclibSearchUrl = 'https://lrclib.net/api/search';

  /// Searches iTunes API for tracks (which includes 30s previews)
  Future<List<TrackModel>> searchTracks(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final uri = Uri.parse(
          '$_itunesSearchUrl?term=${Uri.encodeComponent(query)}&entity=song&limit=20');
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List;
        return results.map((r) => TrackModel.fromJson(r)).toList();
      } else {
        throw Exception('Failed to load tracks from iTunes');
      }
    } catch (e) {
      print('iTunes search error: $e');
      return [];
    }
  }

  /// Searches LRCLib for lyrics using track name and artist name
  Future<LyricsModel?> fetchLyrics(String trackName, String artistName) async {
    try {
      final query = '$trackName $artistName';
      final uri = Uri.parse(
          '$_lrclibSearchUrl?q=${Uri.encodeComponent(query)}');
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        if (data.isNotEmpty) {
          // Find closest match or take first
          final bestMatch = data.firstWhere(
            (item) =>
                item['trackName']?.toString().toLowerCase().trim() ==
                    trackName.toLowerCase().trim(),
            orElse: () => data.first,
          );

          return LyricsModel(
            plainLyrics: bestMatch['plainLyrics'] ?? '',
            syncedLyrics: bestMatch['syncedLyrics'],
          );
        }
      }
      return null;
    } catch (e) {
      print('LRCLib fetch error: $e');
      return null;
    }
  }
}
