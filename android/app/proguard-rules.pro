# Flutter-specific ProGuard rules for YourCA

# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Kotlin
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keepclassmembers class ** { <fields>; }
-keepclassmembers class kotlin.Metadata { public <methods>; }

# Gson / JSON serialization (if used)
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**

# General Android
-keepattributes SourceFile,LineNumberTable
-keepattributes *Annotation*

# Flutter Play Store Split / Deferred components (not used, ignore missing classes)
-dontwarn com.google.android.play.core.**