import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../services/youtube_service.dart';

class YouTubeFeedScreen extends StatefulWidget {
  const YouTubeFeedScreen({super.key});

  @override
  State<YouTubeFeedScreen> createState() => _YouTubeFeedScreenState();
}

class _YouTubeFeedScreenState extends State<YouTubeFeedScreen> {
  final YouTubeService _youtubeService = YouTubeService(
    Supabase.instance.client,
  );
  List<Map<String, dynamic>> _videos = [];
  bool _isLoading = false;
  bool _hasError = false;
  String? _errorMessage;
  int _selectedCategory = 1;
  YoutubePlayerController? _controller;
  final ScrollController _scrollController = ScrollController();

  Set<String> likedVideoIds = {};
  Set<String> dislikedVideoIds = {};

  @override
  void initState() {
    super.initState();
    _loadVideos();
    _fetchLikedVideos();
    _fetchDislikedVideos();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _fetchLikedVideos() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final res = await Supabase.instance.client
        .from('likes')
        .select('video_id')
        .eq('user_id', userId);
    likedVideoIds = Set<String>.from(res.map((e) => e['video_id'].toString()));
    setState(() {});
  }

  Future<void> _fetchDislikedVideos() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final res = await Supabase.instance.client
        .from('dislikes')
        .select('video_id')
        .eq('user_id', userId);
    dislikedVideoIds = Set<String>.from(
      res.map((e) => e['video_id'].toString()),
    );
    setState(() {});
  }

  Future<void> _toggleLike(String videoId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    if (likedVideoIds.contains(videoId)) {
      await Supabase.instance.client
          .from('likes')
          .delete()
          .eq('user_id', userId)
          .eq('video_id', videoId);
      likedVideoIds.remove(videoId);
    } else {
      if (dislikedVideoIds.contains(videoId)) {
        await Supabase.instance.client
            .from('dislikes')
            .delete()
            .eq('user_id', userId)
            .eq('video_id', videoId);
        dislikedVideoIds.remove(videoId);
      }
      await Supabase.instance.client.from('likes').insert({
        'user_id': userId,
        'video_id': videoId,
        'created_at': DateTime.now().toIso8601String(),
        'is_like': true,
      });
      likedVideoIds.add(videoId);
    }
    setState(() {});
  }

  Future<void> _toggleDislike(String videoId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    if (dislikedVideoIds.contains(videoId)) {
      await Supabase.instance.client
          .from('dislikes')
          .delete()
          .eq('user_id', userId)
          .eq('video_id', videoId);
      dislikedVideoIds.remove(videoId);
    } else {
      if (likedVideoIds.contains(videoId)) {
        await Supabase.instance.client
            .from('likes')
            .delete()
            .eq('user_id', userId)
            .eq('video_id', videoId);
        likedVideoIds.remove(videoId);
      }
      await Supabase.instance.client.from('dislikes').insert({
        'user_id': userId,
        'video_id': videoId,
        'created_at': DateTime.now().toIso8601String(),
      });
      dislikedVideoIds.add(videoId);
    }
    setState(() {});
  }

  Future<void> _recordView(String videoId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client.from('video_history').upsert({
        'user_id': userId,
        'youtube_video_id': videoId,
        'watched_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,youtube_video_id');
    } catch (e) {}
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      _loadMoreVideos();
    }
  }

  Future<void> _loadVideos() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      final result = await _youtubeService.searchVideos(
        query: _getCategoryQuery(_selectedCategory),
        categoryId: _selectedCategory,
      );

      if (mounted) {
        setState(() {
          _videos = result.videos;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Beklenmeyen bir hata oluştu: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreVideos() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final result = await _youtubeService.searchVideos(
        query: _getCategoryQuery(_selectedCategory),
        categoryId: _selectedCategory,
        pageToken: null,
      );

      if (mounted) {
        setState(() {
          _videos.addAll(result.videos);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Daha fazla video yüklenirken hata oluştu: $e'),
          ),
        );
      }
    }
  }

  String _getCategoryQuery(int categoryId) {
    final queries = {
      1: 'Eğitici videolar',
      2: 'Çizgi film',
      3: 'Çocuk şarkıları',
      4: 'Eğitici oyunlar',
      5: 'Etkinlikler',
      6: 'Hikayeler',
    };
    return queries[categoryId] ?? 'Eğitici videolar';
  }

  void _playVideo(String videoId) {
    _controller?.dispose();
    _controller = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        enableCaption: true,
      ),
    );
    _recordView(videoId);

    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: YoutubePlayer(
                      controller: _controller!,
                      showVideoProgressIndicator: true,
                      progressIndicatorColor: Colors.purple,
                      progressColors: const ProgressBarColors(
                        playedColor: Colors.purple,
                        handleColor: Colors.purpleAccent,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                likedVideoIds.contains(videoId)
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: Colors.pink,
                              ),
                              onPressed: () async {
                                await _toggleLike(videoId);
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                dislikedVideoIds.contains(videoId)
                                    ? Icons.thumb_down_alt
                                    : Icons.thumb_down,
                                color: Colors.blue,
                              ),
                              onPressed: () async {
                                await _toggleDislike(videoId);
                              },
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('YouTube Videoları'),
        actions: [
          DropdownButton<int>(
            value: _selectedCategory,
            items: [
              DropdownMenuItem(value: 1, child: Text('Eğitici')),
              DropdownMenuItem(value: 2, child: Text('Çizgi Film')),
              DropdownMenuItem(value: 3, child: Text('Çocuk Şarkıları')),
              DropdownMenuItem(value: 4, child: Text('Oyunlar')),
              DropdownMenuItem(value: 5, child: Text('Etkinlikler')),
              DropdownMenuItem(value: 6, child: Text('Hikayeler')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedCategory = value);
                _loadVideos();
              }
            },
          ),
        ],
      ),
      body:
          _hasError
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(_errorMessage ?? 'Beklenmeyen bir hata oluştu'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadVideos,
                      child: const Text('Tekrar Dene'),
                    ),
                  ],
                ),
              )
              : RefreshIndicator(
                onRefresh: _loadVideos,
                child: GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.8,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _videos.length + (_isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _videos.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    final video = _videos[index];
                    return Card(
                      elevation: 4,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        onTap: () => _playVideo(video['video_id']),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Stack(
                              children: [
                                Image.network(
                                  video['thumbnail_url'] ?? '',
                                  height: 120,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      height: 120,
                                      color: Colors.grey[300],
                                      child: const Icon(Icons.error_outline),
                                    );
                                  },
                                ),
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      video['duration'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    video['title'] ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.visibility, size: 16),
                                      Text(
                                        ' ${_formatNumber(video['view_count'] ?? 0)}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.thumb_up, size: 16),
                                      Text(
                                        ' ${_formatNumber(video['like_count'] ?? 0)}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
