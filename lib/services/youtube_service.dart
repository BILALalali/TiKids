import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeService {
  final SupabaseClient _supabase;
  final String _apiKey = 'AIzaSyCpK4jLiHWsNdbji9S1SlHPEdv2d3NfV1M';
  final Map<String, DateTime> _lastFetchTime = {};
  final Map<String, List<Map<String, dynamic>>> _cachedVideos = {};
  final Duration _cacheDuration = const Duration(hours: 1);
  final YoutubeExplode _yt = YoutubeExplode();

  YouTubeService(this._supabase);

  Future<({List<Map<String, dynamic>> videos, String? nextPageToken})>
  searchVideos({
    required String query,
    required int categoryId,
    int maxResults = 10,
    String? pageToken,
  }) async {
    final cacheKey = '${query}_${categoryId}_$pageToken';

    // Check cache first
    if (_cachedVideos.containsKey(cacheKey)) {
      final lastFetch = _lastFetchTime[cacheKey];
      if (lastFetch != null &&
          DateTime.now().difference(lastFetch) < _cacheDuration) {
        return (videos: _cachedVideos[cacheKey]!, nextPageToken: null);
      }
    }

    try {
      // First try to get videos from Supabase cache
      final cachedVideos = await _supabase
          .from('youtube_videos')
          .select()
          .eq('category_id', categoryId)
          .eq('is_approved', true)
          .order('created_at', ascending: false)
          .limit(maxResults);

      if (cachedVideos != null && cachedVideos.isNotEmpty) {
        _cacheVideos(cacheKey, List<Map<String, dynamic>>.from(cachedVideos));
        return (
          videos: List<Map<String, dynamic>>.from(cachedVideos),
          nextPageToken: null,
        );
      }

      // Try YouTube Data API first
      try {
        final url = Uri.https('www.googleapis.com', '/youtube/v3/search', {
          'part': 'snippet',
          'q': '$query #shorts',
          'type': 'video',
          'videoDuration': 'short',
          'maxResults': '$maxResults',
          'key': _apiKey,
          'safeSearch': 'strict',
          'relevanceLanguage': 'tr',
          'regionCode': 'TR',
          'fields':
              'items(id/videoId,snippet(title,description,thumbnails/high/url,thumbnails/default/url)),nextPageToken',
          if (pageToken != null) 'pageToken': pageToken,
        });

        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List items = data['items'] ?? [];
          final videos = await _processVideoItems(items, categoryId);
          _cacheVideos(cacheKey, videos);
          return (
            videos: videos,
            nextPageToken: data['nextPageToken'] as String?,
          );
        }

        // If API quota exceeded, use youtube_explode as fallback
        if (response.statusCode == 403) {
          print('YouTube API quota exceeded, using fallback method...');
          return await _searchWithYoutubeExplode(query, categoryId, maxResults);
        }

        throw Exception('YouTube API error: ${response.statusCode}');
      } catch (e) {
        print('Error with YouTube API: $e');
        return await _searchWithYoutubeExplode(query, categoryId, maxResults);
      }
    } catch (e) {
      print('Error in searchVideos: $e');
      // Try to return cached videos if any error occurs
      if (_cachedVideos.containsKey(cacheKey)) {
        return (videos: _cachedVideos[cacheKey]!, nextPageToken: null);
      }
      return (videos: <Map<String, dynamic>>[], nextPageToken: null);
    }
  }

  Future<({List<Map<String, dynamic>> videos, String? nextPageToken})>
  _searchWithYoutubeExplode(
    String query,
    int categoryId,
    int maxResults,
  ) async {
    try {
      final searchList = await _yt.search.search('$query #shorts');
      final videos = <Map<String, dynamic>>[];

      for (var video in searchList.take(maxResults)) {
        try {
          final videoData = {
            'video_id': video.id.value,
            'title': video.title,
            'description': video.description,
            'thumbnail_url': video.thumbnails.highResUrl,
            'category_id': categoryId,
            'is_approved': true,
            'created_at': DateTime.now().toIso8601String(),
          };

          videos.add(videoData);

          // Cache in Supabase
          try {
            await _supabase.from('youtube_videos').upsert(videoData);
          } catch (e) {
            print('Error caching video: $e');
          }
        } catch (e) {
          print('Error processing video: $e');
          continue;
        }
      }

      return (videos: videos, nextPageToken: null);
    } catch (e) {
      print('Error with youtube_explode: $e');
      return (videos: <Map<String, dynamic>>[], nextPageToken: null);
    }
  }

  Future<List<Map<String, dynamic>>> _processVideoItems(
    List items,
    int categoryId,
  ) async {
    final videos = <Map<String, dynamic>>[];

    for (var item in items) {
      try {
        final videoId = item['id']?['videoId'];
        final snippet = item['snippet'];
        if (videoId == null || snippet == null) continue;

        final videoData = {
          'video_id': videoId,
          'title': snippet['title'] ?? '',
          'description': snippet['description'] ?? '',
          'thumbnail_url':
              snippet['thumbnails']?['high']?['url'] ??
              snippet['thumbnails']?['default']?['url'],
          'category_id': categoryId,
          'is_approved': true,
          'created_at': DateTime.now().toIso8601String(),
        };

        videos.add(videoData);

        // Cache in Supabase
        try {
          await _supabase.from('youtube_videos').upsert(videoData);
        } catch (e) {
          print('Error caching video: $e');
        }
      } catch (e) {
        print('Error processing video item: $e');
        continue;
      }
    }

    return videos;
  }

  void _cacheVideos(String key, List<Map<String, dynamic>> videos) {
    _cachedVideos[key] = videos;
    _lastFetchTime[key] = DateTime.now();
  }

  Future<Map<String, dynamic>?> getVideoDetails(String videoId) async {
    final url = Uri.https('www.googleapis.com', '/youtube/v3/videos', {
      'part': 'contentDetails,statistics',
      'id': videoId,
      'key': _apiKey,
    });
    final response = await http.get(url);
    if (response.statusCode != 200) return null;
    final data = json.decode(response.body);
    if (data['items'] == null || data['items'].isEmpty) return null;
    final item = data['items'][0];
    return {
      'duration': item['contentDetails']?['duration'] ?? '',
      'viewCount': int.tryParse(item['statistics']?['viewCount'] ?? '0') ?? 0,
      'likeCount': int.tryParse(item['statistics']?['likeCount'] ?? '0') ?? 0,
    };
  }

  double _calculateSafetyScore(
    Map<String, dynamic> video,
    Map<String, dynamic>? details,
  ) {
    if (details == null) return 0.0;

    double score = 1.0;
    final title = (video['title'] ?? '').toString().toLowerCase();
    final description = (video['description'] ?? '').toString().toLowerCase();
    final unsafeWords = ['violence', 'adult', 'explicit', 'inappropriate'];

    for (var word in unsafeWords) {
      if (title.contains(word) || description.contains(word)) {
        score -= 0.3;
      }
    }

    final viewCount = details['viewCount'] ?? 0;
    final likeCount = details['likeCount'] ?? 0;

    if (viewCount > 0) {
      final likeRatio = likeCount / viewCount;
      if (likeRatio < 0.5) {
        score -= 0.2;
      }
    }

    final duration = _parseDuration(details['duration'] ?? '');
    if (duration > 60) {
      score = 0.0;
    }

    return score.clamp(0.0, 1.0);
  }

  int _parseDuration(String duration) {
    final regex = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?');
    final match = regex.firstMatch(duration);
    if (match == null) return 0;
    final hours = int.parse(match.group(1) ?? '0');
    final minutes = int.parse(match.group(2) ?? '0');
    final seconds = int.parse(match.group(3) ?? '0');
    return hours * 3600 + minutes * 60 + seconds;
  }

  Future<void> saveVideosToDatabase(List<Map<String, dynamic>> videos) async {
    for (var video in videos) {
      final details = await getVideoDetails(video['video_id']);
      final safetyScore = _calculateSafetyScore(video, details);

      await _supabase.from('youtube_videos').upsert({
        'video_id': video['video_id'],
        'title': video['title'],
        'description': video['description'],
        'thumbnail_url': video['thumbnail_url'],
        'duration': video['duration'],
        'category_id': video['category_id'],
        'view_count': video['view_count'],
        'like_count': video['like_count'],
        'safety_score': safetyScore,
        'is_approved': safetyScore >= 0.8,
      });

      await _supabase.from('content_filters').insert({
        'video_id': video['video_id'],
        'language_score': safetyScore,
        'violence_score': 1 - safetyScore,
        'adult_content_score': 1 - safetyScore,
        'educational_score': safetyScore,
        'is_safe': safetyScore >= 0.8,
      });
    }
  }

  @override
  void dispose() {
    _yt.close();
  }
}
