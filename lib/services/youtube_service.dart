import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class YouTubeService {
  final SupabaseClient _supabase;
  final String _apiKey = dotenv.env['AIzaSyCpK4jLiHWsNdbji9S1SlHPEdv2d3NfV1M'] ?? '';

  YouTubeService(this._supabase);

  Future<({List<Map<String, dynamic>> videos, String? nextPageToken})>
  searchVideos({
    required String query,
    required int categoryId,
    int maxResults = 20,
    String? pageToken,
  }) async {
    final Map<int, String> categoryKeywords = {
      1: 'çocuk eğitim',
      2: 'çocuk çizgi film',
      3: 'çocuk şarkıları',
      4: 'çocuk eğitici oyunlar',
      5: 'çocuk etkinlikler',
      6: 'çocuk hikayeler',
    };

    final List<String> bannedWords = [
      'violence',
      'violent',
      'sex',
      'adult',
      'explicit',
      'inappropriate',
      'hate',
      'kill',
      'death',
      'blood',
      'fight',
      'abuse',
      'drugs',
      'alcohol',
      'nude',
      'suicide',
      'terror',
      'racist',
      'weapon',
      'gun',
      'knife',
      'قتل',
      'عنف',
      'جريمة',
      'جنس',
      'اباحي',
      'مخدرات',
      'كحول',
      'سلاح',
      'دم',
      'انتحار',
      'كراهية',
    ];

    final searchQuery =
        '${categoryKeywords[categoryId] ?? ''} $query çocuk kids for children';

    final url = Uri.https('www.googleapis.com', '/youtube/v3/search', {
      'part': 'snippet',
      'q': searchQuery,
      'type': 'video',
      'maxResults': '$maxResults',
      'key': _apiKey,
      'safeSearch': 'strict',
      'videoDuration': 'short',
      if (pageToken != null) 'pageToken': pageToken,
    });

    final response = await http.get(url);
    if (response.statusCode != 200) {
      return (videos: <Map<String, dynamic>>[], nextPageToken: null);
    }
    final data = json.decode(response.body);
    final List items = data['items'] ?? [];
    List<Map<String, dynamic>> videos = [];
    for (var item in items) {
      final videoId = item['id']?['videoId'];
      final snippet = item['snippet'];
      if (videoId == null || snippet == null) continue;

      final details = await getVideoDetails(videoId);
      if (details == null) continue;

      final title = (snippet['title'] ?? '').toString().toLowerCase();
      final description =
          (snippet['description'] ?? '').toString().toLowerCase();
      bool isBanned = bannedWords.any(
        (word) => title.contains(word) || description.contains(word),
      );
      if (isBanned) continue;

      final safetyScore = _calculateSafetyScore(snippet, details);
      if (safetyScore < 0.8) continue;

      videos.add({
        'video_id': videoId,
        'title': snippet['title'],
        'description': snippet['description'],
        'thumbnail_url': snippet['thumbnails']?['high']?['url'],
        'duration': details['duration'],
        'view_count': details['viewCount'],
        'like_count': details['likeCount'],
        'category_id': categoryId,
        'safety_score': safetyScore,
      });
    }
    return (videos: videos, nextPageToken: data['nextPageToken'] as String?);
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

  double _calculateSafetyScore(Map snippet, Map details) {
    double score = 1.0;
    final title = (snippet['title'] ?? '').toString().toLowerCase();
    final description = (snippet['description'] ?? '').toString().toLowerCase();
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
      await _supabase.from('youtube_videos').upsert({
        'video_id': video['video_id'],
        'title': video['title'],
        'description': video['description'],
        'thumbnail_url': video['thumbnail_url'],
        'duration': video['duration'],
        'category_id': video['category_id'],
        'view_count': video['view_count'],
        'like_count': video['like_count'],
        'safety_score': video['safety_score'],
        'is_approved': video['safety_score'] >= 0.8,
      });
      await _supabase.from('content_filters').insert({
        'video_id': video['video_id'],
        'language_score': video['safety_score'],
        'violence_score': 1 - video['safety_score'],
        'adult_content_score': 1 - video['safety_score'],
        'educational_score': video['safety_score'],
        'is_safe': video['safety_score'] >= 0.8,
      });
    }
  }
}