import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'login.dart';
import 'home.dart';
import 'package:video_player/video_player.dart';

// API Keys
const String supabaseUrl = 'https://dzzedydeaqavpbqoofxi.supabase.co';
const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR6emVkeWRlYXFhdnBicW9vZnhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDc2ODc1MDcsImV4cCI6MjA2MzI2MzUwN30.KvlMy1YgIFsguRUj2_ZpMwfjHhGYEaUxjQPwDXmXrVM';
const String youtubeApiKey = 'AIzaSyCpK4jLiHWsNdbji9S1SlHPEdv2d3NfV1M';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TiKids',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Cairo',
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('tr', 'TR')],
      locale: const Locale('tr', 'TR'),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
      },
    );
  }
}

class SimpleVideoPlayerScreen extends StatelessWidget {
  final String videoUrl;
  const SimpleVideoPlayerScreen({super.key, required this.videoUrl});

  @override
  Widget build(BuildContext context) {
    final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
    return Scaffold(
      appBar: AppBar(title: const Text('Video')),
      body: FutureBuilder(
        future: controller.initialize(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          controller.play();
          return Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          );
        },
      ),
    );
  }
}

final emailRegex = RegExp(
  r"^[a-zA-Z0-9.!#\$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+\.[a-zA-Z]{2,}",
);