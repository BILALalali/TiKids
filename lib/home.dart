import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'main.dart' show SimpleVideoPlayerScreen;
import 'screens/youtube_feed_screen.dart';
import 'services/youtube_service.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:http/http.dart' as http;

final GlobalKey<_HistoryScreenState> historyScreenKey =
    GlobalKey<_HistoryScreenState>();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 2;

  final List<Widget> _screens = [
    const SearchScreen(),
    const UploadScreen(),
    const VideoFeedScreen(),
    HistoryScreen(key: historyScreenKey),
    const ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: _screens[_selectedIndex],
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            onPressed: () => setState(() => _selectedIndex = 2),
            backgroundColor: Colors.white,
            elevation: 8,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_circle_fill, color: Colors.purple, size: 36),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'TiKids',
            style: TextStyle(
              color: Colors.purple,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => _onItemTapped(0),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => _onItemTapped(1),
              ),
              const SizedBox(width: 40), // TiKids
              IconButton(
                icon: const Icon(Icons.history),
                onPressed: () => _onItemTapped(3),
              ),
              IconButton(
                icon: const Icon(Icons.person),
                onPressed: () => _onItemTapped(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VideoFeedScreen extends StatefulWidget {
  final List<Map<String, dynamic>>? youtubeVideos;
  final int? initialIndex;
  const VideoFeedScreen({super.key, this.youtubeVideos, this.initialIndex});
  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  final YouTubeService _youtubeService = YouTubeService(
    Supabase.instance.client,
  );
  int _selectedCategory = 1;
  List<Map<String, dynamic>> _youtubeVideos = [];
  List<Map<String, dynamic>> _localVideos = [];
  bool _isLoading = true;
  int _currentIndex = 0;
  Map<int, YoutubePlayerController?> _ytControllers = {};
  Map<int, VideoPlayerController?> _localControllers = {};
  bool _isLoadingMore = false;
  String? _nextPageToken;
  Map<int, String?> _localVideoError = {};

  final Map<int, String> _categories = const {
    1: 'Eğitim',
    2: 'Çizgi Film',
    3: 'Çocuk Şarkıları',
    4: 'Eğitici Oyunlar',
    5: 'Etkinlikler',
    6: 'Hikayeler',
    99: 'Yerel Videolar',
  };

  Set<String> likedVideoIds = {};
  Set<String> dislikedVideoIds = {};

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

  Future<void> _recordView(String videoId, {bool isYoutube = false}) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      String? title;
      String? thumbnailUrl;

      if (isYoutube) {
        final video = _youtubeVideos.firstWhere(
          (v) => v['video_id'].toString() == videoId,
          orElse: () => {},
        );
        title = video['title'];
        thumbnailUrl = video['thumbnail_url'];
      } else {
        final video = _localVideos.firstWhere(
          (v) => v['id'].toString() == videoId,
          orElse: () => {},
        );
        title = video['title'];
        thumbnailUrl = video['thumbnail_url'];
      }

      await Supabase.instance.client.from('video_history').upsert({
        'user_id': user.id,
        'video_id': videoId,
        'title': title,
        'thumbnail_url': thumbnailUrl,
        'is_youtube': isYoutube,
        'watched_at': DateTime.now().toIso8601String(),
      });

      // Refresh history screen
      if (historyScreenKey.currentState != null) {
        historyScreenKey.currentState!._fetchHistory();
      }
    } catch (e) {
      print('Error recording view: $e');
    }
  }

  Future<void> _toggleLike(String videoId, {bool isYoutube = false}) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      String? title;
      String? thumbnailUrl;

      if (isYoutube) {
        final video = _youtubeVideos.firstWhere(
          (v) => v['video_id'].toString() == videoId,
          orElse: () => {},
        );
        title = video['title'];
        thumbnailUrl = video['thumbnail_url'];
      } else {
        final video = _localVideos.firstWhere(
          (v) => v['id'].toString() == videoId,
          orElse: () => {},
        );
        title = video['title'];
        thumbnailUrl = video['video_url'];
      }

      if (likedVideoIds.contains(videoId)) {
        await Supabase.instance.client
            .from('likes')
            .delete()
            .eq('user_id', user.id)
            .eq('video_id', videoId);
        likedVideoIds.remove(videoId);
      } else {
        if (dislikedVideoIds.contains(videoId)) {
          await Supabase.instance.client
              .from('dislikes')
              .delete()
              .eq('user_id', user.id)
              .eq('video_id', videoId);
          dislikedVideoIds.remove(videoId);
        }
        await Supabase.instance.client.from('likes').insert({
          'user_id': user.id,
          'video_id': videoId,
          'youtube_video_id': isYoutube ? videoId : null,
          'user_name': user.email,
          'created_at': DateTime.now().toIso8601String(),
          'title': title,
          'thumbnail_url': thumbnailUrl,
        });
        likedVideoIds.add(videoId);
      }
      setState(() {});

      // Refresh history screen
      if (historyScreenKey.currentState != null) {
        historyScreenKey.currentState!._fetchHistory();
      }
    } catch (e) {
      debugPrint('Error toggling like: $e');
    }
  }

  Future<void> _toggleDislike(String videoId, {bool isYoutube = false}) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      String? title;
      String? thumbnailUrl;

      if (isYoutube) {
        final video = _youtubeVideos.firstWhere(
          (v) => v['video_id'].toString() == videoId,
          orElse: () => {},
        );
        title = video['title'];
        thumbnailUrl = video['thumbnail_url'];
      } else {
        final video = _localVideos.firstWhere(
          (v) => v['id'].toString() == videoId,
          orElse: () => {},
        );
        title = video['title'];
        thumbnailUrl = video['video_url'];
      }

      if (dislikedVideoIds.contains(videoId)) {
        await Supabase.instance.client
            .from('dislikes')
            .delete()
            .eq('user_id', user.id)
            .eq('video_id', videoId);
        dislikedVideoIds.remove(videoId);
      } else {
        if (likedVideoIds.contains(videoId)) {
          await Supabase.instance.client
              .from('likes')
              .delete()
              .eq('user_id', user.id)
              .eq('video_id', videoId);
          likedVideoIds.remove(videoId);
        }
        await Supabase.instance.client.from('dislikes').insert({
          'user_id': user.id,
          'video_id': videoId,
          'youtube_video_id': isYoutube ? videoId : null,
          'user_name': user.email,
          'created_at': DateTime.now().toIso8601String(),
          'title': title,
          'thumbnail_url': thumbnailUrl,
        });
        dislikedVideoIds.add(videoId);
      }
      setState(() {});

      // Refresh history screen
      if (historyScreenKey.currentState != null) {
        historyScreenKey.currentState!._fetchHistory();
      }
    } catch (e) {
      debugPrint('Error toggling dislike: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.youtubeVideos != null && widget.youtubeVideos!.isNotEmpty) {
      _youtubeVideos = widget.youtubeVideos!;
      _isLoading = false;
      _currentIndex = widget.initialIndex ?? 0;
      _initializeVideo(_currentIndex);
    } else {
      _fetchAll();
    }
    _fetchLikedVideos();
    _fetchDislikedVideos();
  }

  Future<void> _fetchAll() async {
    setState(() => _isLoading = true);

    try {
      // Fetch YouTube videos
      if (_selectedCategory != 99) {
        final result = await _youtubeService.searchVideos(
          query: _categories[_selectedCategory] ?? 'Eğitim',
          categoryId: _selectedCategory,
        );
        _youtubeVideos = result.videos;
        _nextPageToken = result.nextPageToken;
      }

      // Fetch local videos with proper error handling
      try {
        final localVideosResponse = await Supabase.instance.client
            .from('videos')
            .select()
            .eq('is_approved', true)
            .order('created_at', ascending: false);

        if (mounted) {
          setState(() {
            _localVideos = List<Map<String, dynamic>>.from(localVideosResponse);

            // Pre-process video URLs
            for (var video in _localVideos) {
              if (video['video_url'] != null &&
                  !video['video_url'].toString().startsWith('http')) {
                try {
                  final fileName =
                      video['video_url'].toString().split('/').last;
                  video['video_url'] = Supabase.instance.client.storage
                      .from('videos')
                      .getPublicUrl(fileName);
                } catch (e) {
                  print('Error processing video URL: $e');
                }
              }
            }

            _isLoading = false;
            _currentIndex = 0;
          });

          // Initialize videos based on current view
          if (_youtubeVideos.isNotEmpty && _selectedCategory != 99) {
            _initializeVideo(0);
          } else if (_localVideos.isNotEmpty) {
            _initializeLocalVideo(0);
          }
        }
      } catch (e) {
        print('Error fetching local videos: $e');
        if (mounted) {
          setState(() {
            _localVideos = [];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error in _fetchAll: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreVideos() async {
    if (_isLoadingMore || _nextPageToken == null) return;
    setState(() => _isLoadingMore = true);
    try {
      final result = await _youtubeService.searchVideos(
        query: _categories[_selectedCategory] ?? 'Eğitim',
        categoryId: _selectedCategory,
        pageToken: _nextPageToken,
      );
      setState(() {
        _youtubeVideos.addAll(result.videos);
        _nextPageToken = result.nextPageToken;
        _isLoadingMore = false;
      });
      _preloadVideos();
    } catch (e) {
      setState(() => _isLoadingMore = false);
    }
  }

  void _preloadVideos() {
    // تحميل الفيديوهات السابقة والحالية والتالية
    for (int i = _currentIndex - 1; i <= _currentIndex + 1; i++) {
      if (i >= 0 && i < _youtubeVideos.length) {
        _initializeVideo(i);
      }
    }
  }

  Future<void> _initializeVideo(int index) async {
    if (_ytControllers.containsKey(index)) return;

    try {
      final video = _youtubeVideos[index];
      final controller = YoutubePlayerController(
        initialVideoId: video['video_id'],
        flags: const YoutubePlayerFlags(
          autoPlay: true,
          mute: false,
          enableCaption: true,
          showLiveFullscreenButton: false,
        ),
      );

      setState(() {
        _ytControllers[index] = controller;
      });

      if (index == _currentIndex) {
        controller.play();
      }
    } catch (e) {
      print('Error initializing YouTube video: $e');
    }
  }

  Future<void> _initializeLocalVideo(int index) async {
    if (_localControllers.containsKey(index)) return;

    try {
      final video = _localVideos[index];
      final videoUrl = video['video_url'];

      if (videoUrl == null) {
        throw Exception('Video URL is null');
      }

      // Get the public URL for the video from Supabase storage
      String publicUrl;
      if (videoUrl.startsWith('http')) {
        publicUrl = videoUrl;
      } else {
        try {
          // Extract the file name from the storage path
          final fileName = videoUrl.split('/').last;
          // Get a fresh public URL with the correct permissions
          publicUrl = await Supabase.instance.client.storage
              .from('videos')
              .createSignedUrl(fileName, 3600); // URL valid for 1 hour
        } catch (e) {
          print('Error getting signed URL: $e');
          setState(() {
            _localVideoError[index] = 'Error getting video URL';
          });
          return;
        }
      }

      print('Attempting to load video from URL: $publicUrl');

      // Initialize with better error handling
      final controller = VideoPlayerController.networkUrl(Uri.parse(publicUrl));
      bool initialized = false;

      try {
        await Future.any([
          controller.initialize().then((_) => initialized = true),
          Future.delayed(const Duration(seconds: 15)),
        ]);

        if (!initialized) {
          throw Exception('Video initialization timeout');
        }

        if (mounted) {
          setState(() {
            _localControllers[index] = controller;
            _localVideoError[index] = null;
          });

          if (index == _currentIndex) {
            controller.play();
          }
        }
      } catch (e) {
        controller.dispose();
        print('Error initializing video: $e');
        if (mounted) {
          setState(() {
            _localVideoError[index] = 'Failed to load video: $e';
          });
        }
      }
    } catch (e) {
      print('Error in _initializeLocalVideo: $e');
      if (mounted) {
        setState(() {
          _localVideoError[index] = e.toString();
        });
      }
    }
  }

  void _disposeLocalControllers() {
    for (var controller in _localControllers.values) {
      controller?.dispose();
    }
    _localControllers.clear();
  }

  void _onSwipe(int direction) {
    final isCustomYoutube =
        widget.youtubeVideos != null && widget.youtubeVideos!.isNotEmpty;
    final isLocalSection = _selectedCategory == 99 && !isCustomYoutube;
    final total =
        isCustomYoutube
            ? _youtubeVideos.length
            : (isLocalSection
                ? _localVideos.length
                : _youtubeVideos.length + _localVideos.length);
    int newIndex = _currentIndex + direction;
    if (newIndex < 0 || newIndex >= total) return;

    // Record view for the current video before changing
    if (isCustomYoutube) {
      final video = _youtubeVideos[_currentIndex];
      _recordView(video['video_id'].toString(), isYoutube: true);
    } else if (isLocalSection) {
      final video = _localVideos[_currentIndex];
      _recordView(video['id'].toString(), isYoutube: false);
    } else if (_currentIndex < _youtubeVideos.length) {
      final video = _youtubeVideos[_currentIndex];
      _recordView(video['video_id'].toString(), isYoutube: true);
    }

    if (isLocalSection) {
      _localControllers[_currentIndex]?.pause();
      setState(() {
        _currentIndex = newIndex;
      });
      _initializeLocalVideo(_currentIndex);
      return;
    }
    _ytControllers[_currentIndex]?.pause();
    setState(() {
      _currentIndex = newIndex;
    });
    _ytControllers[_currentIndex]?.play();
    if (!isCustomYoutube && newIndex >= _youtubeVideos.length - 3) {
      _loadMoreVideos();
    }
    _preloadVideos();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final isCustomYoutube =
        widget.youtubeVideos != null && widget.youtubeVideos!.isNotEmpty;
    final isLocalSection = _selectedCategory == 99 && !isCustomYoutube;
    final total =
        isCustomYoutube
            ? _youtubeVideos.length
            : (isLocalSection
                ? _localVideos.length
                : _youtubeVideos.length + _localVideos.length);
    final isYoutube =
        isCustomYoutube ||
        (!isLocalSection && _currentIndex < _youtubeVideos.length);
    final video =
        isCustomYoutube
            ? _youtubeVideos[_currentIndex]
            : (isLocalSection
                ? _localVideos[_currentIndex]
                : (isYoutube
                    ? _youtubeVideos[_currentIndex]
                    : _localVideos[_currentIndex - _youtubeVideos.length]));
    final isLocal = isLocalSection || (!isYoutube && _localVideos.isNotEmpty);
    final videoId =
        isLocal ? video['id'].toString() : (isYoutube ? video['video_id'] : '');
    final isLiked = likedVideoIds.contains(videoId);
    final isDisliked = dislikedVideoIds.contains(videoId);

    if (isLocalSection && _localControllers[_currentIndex] == null) {
      _initializeLocalVideo(_currentIndex);
      if (_localVideoError[_currentIndex] != null) {
        return Center(
          child: Text(
            'تعذر تحميل الفيديو المحلي:\n${_localVideoError[_currentIndex]}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
        );
      }
      return const Center(child: Text('جاري تحميل الفيديو المحلي...'));
    }
    if (isYoutube && _ytControllers[_currentIndex] == null) {
      _initializeVideo(_currentIndex);
      return const Center(child: Text('جاري تحميل الفيديو...'));
    }

    return SafeArea(
      child: Column(
        children: [
          if (!isCustomYoutube)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: DropdownButton<int>(
                value: _selectedCategory,
                items:
                    _categories.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedCategory = v);
                    _fetchAll();
                  }
                },
              ),
            ),
          Expanded(
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                if (!mounted || _isLoading) return;
                if (details.primaryDelta != null &&
                    details.primaryDelta! < -10) {
                  _onSwipe(1);
                } else if (details.primaryDelta != null &&
                    details.primaryDelta! > 10) {
                  _onSwipe(-1);
                }
              },
              child: Stack(
                children: [
                  Center(
                    child:
                        isLocalSection
                            ? (_localControllers[_currentIndex] != null &&
                                    _localControllers[_currentIndex]!
                                        .value
                                        .isInitialized
                                ? AspectRatio(
                                  aspectRatio:
                                      _localControllers[_currentIndex]!
                                          .value
                                          .aspectRatio,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(24),
                                    child: VideoPlayer(
                                      _localControllers[_currentIndex]!,
                                    ),
                                  ),
                                )
                                : const CircularProgressIndicator())
                            : (isYoutube
                                ? (_ytControllers[_currentIndex] != null
                                    ? AspectRatio(
                                      aspectRatio: 9 / 16,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(24),
                                        child: YoutubePlayer(
                                          controller:
                                              _ytControllers[_currentIndex]!,
                                          showVideoProgressIndicator: true,
                                          progressIndicatorColor: Colors.purple,
                                          progressColors:
                                              const ProgressBarColors(
                                                playedColor: Colors.purple,
                                                handleColor:
                                                    Colors.purpleAccent,
                                              ),
                                          onReady: () {
                                            _ytControllers[_currentIndex]!
                                                .play();
                                          },
                                        ),
                                      ),
                                    )
                                    : const CircularProgressIndicator())
                                : const CircularProgressIndicator()),
                  ),
                  // Videolar için etkileşim butonları (yerel videolar)
                  Positioned(
                    right: 16,
                    bottom: 120,
                    child: Column(
                      children: [
                        FloatingActionButton(
                          heroTag: 'like_$_currentIndex',
                          backgroundColor:
                              isLiked ? Colors.pink : Colors.pinkAccent,
                          onPressed: () {
                            if (isLocal) {
                              _toggleLike(videoId, isYoutube: false);
                            } else {
                              _toggleLike(videoId, isYoutube: true);
                            }
                          },
                          child: Icon(
                            isLiked ? Icons.favorite : Icons.favorite_border,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FloatingActionButton(
                          heroTag: 'dislike_$_currentIndex',
                          backgroundColor:
                              isDisliked ? Colors.blue : Colors.blueAccent,
                          onPressed: () {
                            if (isLocal) {
                              _toggleDislike(videoId, isYoutube: false);
                            } else {
                              _toggleDislike(videoId, isYoutube: true);
                            }
                          },
                          child: Icon(
                            isDisliked
                                ? Icons.thumb_down_alt
                                : Icons.thumb_down,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 20),
                        FloatingActionButton(
                          heroTag: 'report_$_currentIndex',
                          backgroundColor: Colors.orangeAccent,
                          onPressed: () {},
                          child: const Icon(
                            Icons.flag,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ],
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

  @override
  void dispose() {
    for (var controller in _ytControllers.values) {
      controller?.dispose();
    }
    _disposeLocalControllers();
    super.dispose();
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  final List<String> _suggestions = [
    'Çocuk Şarkıları',
    'Harf Öğrenme',
    'Uyku Hikayeleri',
    'Bilim Deneyleri',
    'Çizim ve Boyama',
  ];
  bool _isLoading = false;

  // إضافة خدمة يوتيوب
  final YouTubeService _youtubeService = YouTubeService(
    Supabase.instance.client,
  );

  Future<void> _search(String query) async {
    setState(() => _isLoading = true);
    // البحث من يوتيوب فقط
    final result = await _youtubeService.searchVideos(
      query: query,
      categoryId: 1,
    ); // يمكنك تخصيص categoryId حسب الحاجة
    setState(() {
      _results = result.videos;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Arama çubuğu
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Video ara...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              onSubmitted: _search,
            ),
            const SizedBox(height: 16),
            // Arama önerileri
            if (_searchController.text.isEmpty)
              Wrap(
                spacing: 8,
                children:
                    [
                          'Çocuk Şarkıları',
                          'Harf Öğrenme',
                          'Uyku Hikayeleri',
                          'Bilim Deneyleri',
                          'Çizim ve Boyama',
                        ]
                        .map(
                          (s) => ActionChip(
                            label: Text(s),
                            backgroundColor: Colors.purple[100],
                            onPressed: () {
                              _searchController.text = s;
                              _search(s);
                            },
                          ),
                        )
                        .toList(),
              ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_isLoading && _results.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final video = _results[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: ListTile(
                        leading:
                            video['thumbnail_url'] != null
                                ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    video['thumbnail_url'],
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                  ),
                                )
                                : const Icon(
                                  Icons.ondemand_video,
                                  size: 40,
                                  color: Colors.purple,
                                ),
                        title: Text(video['title'] ?? ''),
                        subtitle: Text(video['description'] ?? ''),
                        onTap: () {
                          // الانتقال إلى شاشة عرض الفيديوهات مع تمرير النتائج
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => VideoFeedScreen(
                                    youtubeVideos: _results,
                                    initialIndex: i,
                                  ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            if (!_isLoading &&
                _results.isEmpty &&
                _searchController.text.isNotEmpty)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: Center(child: Text('Bu arama için sonuç bulunamadı')),
              ),
          ],
        ),
      ),
    );
  }
}

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? _selectedVideo;
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  bool _isUploading = false;
  String? _errorMessage;
  String? _successMessage;

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedVideo = File(result.files.single.path!);
      });
    }
  }

  Future<void> _uploadVideo() async {
    setState(() {
      _isUploading = true;
      _errorMessage = null;
      _successMessage = null;
    });
    if (_selectedVideo == null || _titleController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Lütfen bir video seçin ve başlık girin';
        _isUploading = false;
      });
      return;
    }
    try {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${_selectedVideo!.path.split('/').last}';
      final storageResponse = await Supabase.instance.client.storage
          .from('videos')
          .upload(fileName, _selectedVideo!);
      final videoUrl = Supabase.instance.client.storage
          .from('videos')
          .getPublicUrl(fileName);
      // Video verilerini veritabanına kaydet
      await Supabase.instance.client.from('videos').insert({
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'video_url': videoUrl,
        'is_approved': true,
        'likes': 0,
        'dislikes': 0,
        'user_id': Supabase.instance.client.auth.currentUser?.id,
        'user_name': Supabase.instance.client.auth.currentUser?.email,
        'created_at': DateTime.now().toIso8601String(),
      });
      setState(() {
        _successMessage =
            'Video başarıyla yüklendi! Yayınlanmadan önce incelenecek.';
        _selectedVideo = null;
        _titleController.clear();
        _descController.clear();
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Video yüklenirken bir hata oluştu';
      });
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickVideo,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.purple[100],
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child:
                        _selectedVideo == null
                            ? const Icon(
                              Icons.add_a_photo,
                              size: 48,
                              color: Colors.purple,
                            )
                            : const Icon(
                              Icons.check_circle,
                              size: 48,
                              color: Colors.green,
                            ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Video Başlığı',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descController,
                decoration: InputDecoration(
                  labelText: 'Video Açıklaması (İsteğe bağlı)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (_successMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _successMessage!,
                    style: const TextStyle(color: Colors.green),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isUploading ? null : _uploadVideo,
                  icon: const Icon(Icons.cloud_upload),
                  label:
                      _isUploading
                          ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                          : const Text(
                            'Video Yükle',
                            style: TextStyle(fontSize: 18),
                          ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _watched = [];
  List<Map<String, dynamic>> _liked = [];
  List<Map<String, dynamic>> _disliked = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _watched = [];
        _liked = [];
        _disliked = [];
        _isLoading = false;
      });
      return;
    }

    try {
      // Fetch watch history
      final watchHistory = await Supabase.instance.client
          .from('video_history')
          .select()
          .eq('user_id', user.id)
          .order('watched_at', ascending: false);

      // Fetch liked videos
      final liked = await Supabase.instance.client
          .from('likes')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      // Fetch disliked videos
      final disliked = await Supabase.instance.client
          .from('dislikes')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _watched = List<Map<String, dynamic>>.from(watchHistory);
          _liked = List<Map<String, dynamic>>.from(liked);
          _disliked = List<Map<String, dynamic>>.from(disliked);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Geçmiş yüklenirken hata oluştu: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'İzleme Geçmişi',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_watched.isEmpty)
                      const Text('Henüz izleme geçmişi yok.')
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _watched.length,
                        itemBuilder: (context, index) {
                          final item = _watched[index];
                          return Card(
                            child: ListTile(
                              leading:
                                  item['thumbnail_url'] != null
                                      ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          item['thumbnail_url'],
                                          width: 56,
                                          height: 56,
                                          fit: BoxFit.cover,
                                          errorBuilder: (
                                            context,
                                            error,
                                            stackTrace,
                                          ) {
                                            return Container(
                                              width: 56,
                                              height: 56,
                                              color: Colors.grey[300],
                                              child: const Icon(Icons.error),
                                            );
                                          },
                                        ),
                                      )
                                      : const Icon(
                                        Icons.video_library,
                                        size: 40,
                                        color: Colors.purple,
                                      ),
                              title: Text(item['title'] ?? 'Video'),
                              subtitle: Text(
                                'İzlenme: ${DateTime.parse(item['watched_at']).toLocal().toString().split('.')[0]}',
                              ),
                              onTap: () {
                                if (item['is_youtube'] == true) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (context) => YoutubePlayerScreen(
                                            videoId: item['video_id'],
                                          ),
                                    ),
                                  );
                                } else if (item['video_url'] != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (context) => SimpleVideoPlayerScreen(
                                            videoUrl: item['video_url'],
                                          ),
                                    ),
                                  );
                                }
                              },
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 24),
                    const Text(
                      'Beğenilen Videolar',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.pink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_liked.isEmpty)
                      const Text('Henüz beğendiğiniz video yok.')
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _liked.length,
                        itemBuilder: (context, index) {
                          final item = _liked[index];
                          return Card(
                            child: ListTile(
                              leading:
                                  item['thumbnail_url'] != null
                                      ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          item['thumbnail_url'],
                                          width: 56,
                                          height: 56,
                                          fit: BoxFit.cover,
                                          errorBuilder: (
                                            context,
                                            error,
                                            stackTrace,
                                          ) {
                                            return Container(
                                              width: 56,
                                              height: 56,
                                              color: Colors.grey[300],
                                              child: const Icon(Icons.error),
                                            );
                                          },
                                        ),
                                      )
                                      : const Icon(
                                        Icons.favorite,
                                        size: 40,
                                        color: Colors.pink,
                                      ),
                              title: Text(item['title'] ?? 'Video'),
                              subtitle: Text(
                                'Beğenildi: ${DateTime.parse(item['created_at']).toLocal().toString().split('.')[0]}',
                              ),
                              onTap: () {
                                if (item['is_youtube'] == true) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (context) => YoutubePlayerScreen(
                                            videoId: item['video_id'],
                                          ),
                                    ),
                                  );
                                } else if (item['video_url'] != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (context) => SimpleVideoPlayerScreen(
                                            videoUrl: item['video_url'],
                                          ),
                                    ),
                                  );
                                }
                              },
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 24),
                    const Text(
                      'Beğenilmeyen Videolar',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_disliked.isEmpty)
                      const Text('Henüz beğenmediğiniz video yok.')
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _disliked.length,
                        itemBuilder: (context, index) {
                          final item = _disliked[index];
                          return Card(
                            child: ListTile(
                              leading:
                                  item['thumbnail_url'] != null
                                      ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          item['thumbnail_url'],
                                          width: 56,
                                          height: 56,
                                          fit: BoxFit.cover,
                                          errorBuilder: (
                                            context,
                                            error,
                                            stackTrace,
                                          ) {
                                            return Container(
                                              width: 56,
                                              height: 56,
                                              color: Colors.grey[300],
                                              child: const Icon(Icons.error),
                                            );
                                          },
                                        ),
                                      )
                                      : const Icon(
                                        Icons.thumb_down,
                                        size: 40,
                                        color: Colors.blue,
                                      ),
                              title: Text(item['title'] ?? 'Video'),
                              subtitle: Text(
                                'Beğenilmedi: ${DateTime.parse(item['created_at']).toLocal().toString().split('.')[0]}',
                              ),
                              onTap: () {
                                if (item['is_youtube'] == true) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (context) => YoutubePlayerScreen(
                                            videoId: item['video_id'],
                                          ),
                                    ),
                                  );
                                } else if (item['video_url'] != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (context) => SimpleVideoPlayerScreen(
                                            videoUrl: item['video_url'],
                                          ),
                                    ),
                                  );
                                }
                              },
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
    );
  }
}

// شاشة تشغيل فيديو يوتيوب
class YoutubePlayerScreen extends StatelessWidget {
  final String videoId;
  const YoutubePlayerScreen({super.key, required this.videoId});

  @override
  Widget build(BuildContext context) {
    final controller = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        enableCaption: true,
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('YouTube Video')),
      body: Center(
        child: YoutubePlayer(
          controller: controller,
          showVideoProgressIndicator: true,
          progressIndicatorColor: Colors.purple,
          progressColors: const ProgressBarColors(
            playedColor: Colors.purple,
            handleColor: Colors.purpleAccent,
          ),
        ),
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _name;
  String? _email;
  String? _imageUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    setState(() => _isLoading = true);
    final user = Supabase.instance.client.auth.currentUser;
    final userId = user?.id ?? '';
    _email = user?.email;
    final profile =
        await Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', userId)
            .maybeSingle();
    setState(() {
      _name = profile?['name'] ?? '';
      _imageUrl = profile?['avatar_url'];
      _isLoading = false;
    });
  }

  Future<void> _showEditDialog() async {
    final nameController = TextEditingController(text: _name ?? '');
    String? tempImage = _imageUrl;
    bool isSaving = false;

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setStateDialog) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  title: const Text('Profili Düzenle'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.image,
                          );
                          if (result != null &&
                              result.files.single.path != null) {
                            final file = File(result.files.single.path!);
                            final fileName =
                                '${Supabase.instance.client.auth.currentUser?.id}_${DateTime.now().millisecondsSinceEpoch}.png';
                            try {
                              await Supabase.instance.client.storage
                                  .from('avatars')
                                  .upload(fileName, file);
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Video yükleme hatası: ${e.toString()}',
                                  ),
                                ),
                              );
                              return;
                            }
                            final url = Supabase.instance.client.storage
                                .from('avatars')
                                .getPublicUrl(fileName);
                            setStateDialog(() {
                              tempImage = url;
                            });
                          }
                        },
                        child: CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.purple[100],
                          backgroundImage:
                              tempImage != null
                                  ? NetworkImage(tempImage!)
                                  : null,
                          child:
                              tempImage == null
                                  ? const Icon(
                                    Icons.person,
                                    size: 40,
                                    color: Colors.purple,
                                  )
                                  : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Kullanıcı Adı',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: isSaving ? null : () => Navigator.pop(context),
                      child: const Text('İptal'),
                    ),
                    ElevatedButton(
                      onPressed:
                          isSaving
                              ? null
                              : () async {
                                setStateDialog(() => isSaving = true);
                                try {
                                  final user =
                                      Supabase.instance.client.auth.currentUser;
                                  await Supabase.instance.client
                                      .from('profiles')
                                      .upsert({
                                        'id': user?.id,
                                        'name': nameController.text.trim(),
                                        'avatar_url': tempImage,
                                      });
                                  setState(() {
                                    _name = nameController.text.trim();
                                    _imageUrl = tempImage;
                                  });
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Profil güncellendi!'),
                                    ),
                                  );
                                } catch (e) {
                                  setStateDialog(() => isSaving = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Bir hata oluştu!'),
                                    ),
                                  );
                                }
                              },
                      child:
                          isSaving
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Text('Kaydet'),
                    ),
                  ],
                ),
          ),
    );
  }

  void _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Büyük dairesel profil fotoğrafı
                          CircleAvatar(
                            radius: 56,
                            backgroundColor: Colors.purple[100],
                            backgroundImage:
                                _imageUrl != null
                                    ? NetworkImage(_imageUrl!)
                                    : null,
                            child:
                                _imageUrl == null
                                    ? const Icon(
                                      Icons.person,
                                      size: 56,
                                      color: Colors.purple,
                                    )
                                    : null,
                          ),
                          const SizedBox(height: 16),
                          // Kullanıcı adı
                          Text(
                            _name ?? '',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // E-posta
                          Text(
                            _email ?? '',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 32),
                          // Profil düzenleme butonu
                          SizedBox(
                            width: 180,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: _showEditDialog,
                              icon: const Icon(Icons.edit),
                              label: const Text(
                                'Profili Düzenle',
                                style: TextStyle(fontSize: 18),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Çıkış butonu en altta
                  Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: SizedBox(
                      width: 180,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _signOut,
                        icon: const Icon(Icons.logout),
                        label: const Text(
                          'Çıkış Yap',
                          style: TextStyle(fontSize: 18),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
  }
}
