# R8 keep rules for GE Prices release builds.
#
# The Flutter embedder and plugin entry points are loaded reflectively and are
# not referenced from Dart-compiled Java code, so R8 cannot see them as roots.

# Flutter engine + plugin registrant.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keepattributes Signature, *Annotation*

# flutter_local_notifications (com.dexterous) instantiates some components
# reflectively.
-keep class com.dexterous.** { *; }

# WorkManager (used by the workmanager plugin) resolves workers by name.
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**

# Flutter's deferred components reference the optional Play Core split-install
# classes; not used by this app, so silence R8's missing-class warnings.
-dontwarn com.google.android.play.core.**