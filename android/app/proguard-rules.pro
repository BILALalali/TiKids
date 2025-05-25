# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Supabase
-keep class io.supabase.** { *; }
-keep class com.google.gson.** { *; }

# Video Player
-keep class com.google.android.exoplayer.** { *; }

# File Picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# YouTube Player
-keep class com.pierfrancescosoffritti.androidyoutubeplayer.** { *; }

# General Android
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; } 