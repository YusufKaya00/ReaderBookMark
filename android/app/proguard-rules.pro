# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# WebView
-keep class * implements android.webkit.WebViewClient { *; }
-keep class * implements android.webkit.WebChromeClient { *; }

# Dio HTTP client
-keep class dio.** { *; }

# SQLite
-keep class org.sqlite.** { *; }
-keep class org.sqlite.database.** { *; }

# Play Core dynamic delivery fallback
-dontwarn com.google.android.play.core.**


