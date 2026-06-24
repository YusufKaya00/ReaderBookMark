# 📖 ReaderBookMark

<p align="center">
  <img src="logo1.jpg" width="120" alt="ReaderBookMark Logo"/>
</p>

<p align="center">
  <strong>A feature-rich bookmark manager and reader for manga, books, articles, and more.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.7+-02569B?logo=flutter&logoColor=white" alt="Flutter"/>
  <img src="https://img.shields.io/badge/Dart-3.7+-0175C2?logo=dart&logoColor=white" alt="Dart"/>
  <img src="https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white" alt="Android"/>
  <img src="https://img.shields.io/badge/Version-1.1.0-blue" alt="Version"/>
</p>

---

## Overview

**ReaderBookMark** is a modern Android application built with Flutter that lets you organize, read, and track web-based content — from manga and books to articles and videos. It features a built-in web reader with ad blocking, automatic new chapter detection with push notifications, in-app self-updating via GitHub Releases, and full library backup/restore capabilities.

---

## ✨ Features

### 📚 Library Management
- **Categorize everything** — Organize bookmarks into five categories: General, Manga, Book, Article, and Watchlist (for movies, series, and videos).
- **Reading state tracking** — Mark each item as *Not Started*, *Reading*, or *Completed* and filter by status.
- **Cover image support** — Display cover art fetched from URLs alongside each bookmark entry.
- **Auto title extraction** — When adding a URL, the app automatically fetches and parses the page title. Optimized for manga sites with smart slug-based title detection.
- **Bulk operations** — Select multiple bookmarks for batch category changes or deletion.
- **Search** — Full-text search across titles and URLs with instant filtering.

### 🌐 Built-in Web Reader
- **In-app WebView** — Read content without leaving the app. Supports both Android (WebView) and Windows (WebView2) platforms.
- **Ad blocker** — Built-in URL pattern-based ad blocker that filters common ad networks (Google Ads, DoubleClick, Facebook tracking, etc.) before they load.
- **Scroll position memory** — Automatically saves and restores your reading position for every bookmark.
- **Text translation** — Select text on any page and get an instant translation powered by Google Translate API.
- **Navigation controls** — Forward, back, refresh buttons with page load progress indicator.
- **External open** — Open any page in your default browser, Brave, or share the URL.

### 🔔 New Chapter Notifications
- **Background scanning** — A `WorkManager`-based periodic task runs every 3 hours to scan your active bookmarks for new chapters.
- **Smart URL normalization** — Strips chapter-specific segments from bookmark URLs (e.g., `/chapter-104/`) to find the manga's base page, then checks for new chapter links.
- **Site Manager integration** — Also scans the homepages of sites registered in the Site Manager for content matching your library.
- **Parallel requests** — Uses batched `Future.wait` (max 5 concurrent requests) for efficient network usage.
- **Push notifications** — Sends Android local notifications when new chapters are found.
- **In-app notification center** — The star icon on the home screen shows an unread badge count. Tap it to view, dismiss, or clear all notifications. Tapping a notification opens the chapter directly in the reader.

### 📤 Export & Import
- **Share as JSON file** — Export your entire library as a shareable `.json` file via the system share sheet.
- **Copy JSON to clipboard** — Copy full library data (including metadata, categories, and reading states) to the clipboard.
- **Copy URLs only** — Export just the raw URLs for quick sharing.
- **Restore from backup** — Paste a JSON backup string to restore your entire library, including all metadata.
- **Batch URL import** — Paste multiple URLs (one per line) to add them all at once. Titles and cover images are fetched automatically.

### 🔄 Self-Updating
- **GitHub Releases integration** — The app checks for updates by fetching `latest.json` from the latest GitHub Release, falling back to the GitHub API if unavailable.
- **One-tap install** — Download and install the new APK directly from within the app with a progress bar.
- **SHA-256 verification** — Downloaded APK integrity is verified against the SHA-256 hash published in the release manifest.
- **Version display** — Current app version is shown in the overflow menu and the About screen.

### 🎨 User Experience
- 🌙 **Dark mode** — Full Material 3 dark theme support, toggled from settings.
- 🌍 **Bilingual** — Complete Turkish and English localization. Language is selectable from settings and persists across sessions.
- 📱 **Material 3 design** — Modern UI with `ColorScheme.fromSeed` theming, choice chips, and responsive layouts.
- ⭐ **What's New dialog** — After each update, a changelog dialog automatically appears showing the latest features in the user's language.
- 🗂️ **Dual filter rows** — Filter bookmarks by both reading state and category simultaneously using scrollable chip rows.

---

## 🏗️ Architecture

The app follows a **Provider-based** state management pattern with a **SQLite** local database.

```
lib/
├── main.dart                         # App entry point, provider setup, background init
│
├── background/
│   └── new_chapter_check.dart        # WorkManager-based periodic chapter scanner
│
├── data/
│   └── app_database.dart             # SQLite database (links + notifications tables, v3)
│
├── models/
│   └── link_item.dart                # LinkItem data model with serialization
│
├── providers/
│   ├── library_provider.dart         # CRUD operations, filtering, search state
│   ├── settings_provider.dart        # Language, dark mode, ad blocker preferences
│   └── notification_provider.dart    # In-app notification list & unread badge count
│
├── ui/
│   ├── screens/
│   │   ├── home_screen.dart          # Main screen: library grid, filters, dialogs
│   │   ├── reader_screen.dart        # WebView reader with ad blocking & translation
│   │   ├── settings_screen.dart      # App settings & batch import/export
│   │   ├── notifications_screen.dart # In-app notification center
│   │   ├── sites_screen.dart         # Manage tracked sites for chapter checking
│   │   └── about_screen.dart         # Developer info & version display
│   └── widgets/
│       ├── add_link_dialog.dart      # Add new bookmark dialog with auto-fetch
│       └── edit_link_dialog.dart     # Edit existing bookmark dialog
│
├── update/
│   └── update_service.dart           # GitHub Releases update checker & APK installer
│
└── utils/
    ├── translations.dart             # TR/EN translation map & BuildContext extension
    ├── export_helper.dart            # JSON export, clipboard copy, file share logic
    └── external_open.dart            # URL launcher & Brave intent helper
```

### Database Schema (SQLite v3)

**`links` table**
| Column | Type | Description |
|---|---|---|
| `id` | INTEGER PK | Auto-increment primary key |
| `title` | TEXT | Bookmark title |
| `url` | TEXT | Target URL |
| `cover_path` | TEXT? | Cover image URL |
| `category` | TEXT | Genel / Manga / Kitap / Makale / İzlenecekler |
| `created_at` | INTEGER | Unix timestamp (ms) |
| `last_scroll_position` | REAL | Saved scroll offset for the reader |
| `reading_state` | TEXT | notStarted / reading / completed |

**`notifications` table**
| Column | Type | Description |
|---|---|---|
| `id` | INTEGER PK | Auto-increment primary key |
| `link_id` | INTEGER? | FK to related bookmark (nullable) |
| `title` | TEXT | Notification title |
| `message` | TEXT | Notification body text |
| `url` | TEXT | Chapter URL to open |
| `cover_path` | TEXT? | Cover image for display |
| `is_read` | INTEGER | 0 = unread, 1 = read |
| `created_at` | INTEGER | Unix timestamp (ms) |

---

## 📦 Supported Manga Sites

The following sites are pre-configured for automatic new chapter detection:

| Site | Domain |
|---|---|
| Hayalistic | `hayalistic.com.tr` |
| Tortuga Çeviri | `tortugaceviri.com` |
| Rüya Manga | `ruyamanga.net` |
| Asura Comic | `asuracomic.net` |
| Tempest Mangas | `tempestmangas.com` |
| Asura Scans TR | `asurascans.com.tr` |
| Uzay Manga | `uzaymanga.com` |

> **Note:** You can add or remove tracked sites from within the app via **Settings → Manage Sites**.

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) `>= 3.7.0`
- Android SDK (API 21+)
- Java 17 (for Gradle)

### Installation

```bash
# Clone the repository
git clone https://github.com/YusufKaya00/ReaderBookMark.git
cd ReaderBookMark

# Install dependencies
flutter pub get

# Run in debug mode
flutter run

# Build release APK
flutter build apk --release

# Build release App Bundle (for Play Store)
flutter build appbundle --release
```

The compiled APK will be at:
```
build/app/outputs/flutter-apk/app-release.apk
```

---

## 🔧 CI/CD

Automated builds and releases are handled by GitHub Actions.

| Trigger | Action |
|---|---|
| Push to `main` | Builds a release APK and creates a GitHub Release |
| Tag `v*` | Same as above, triggered by version tags |

Each GitHub Release includes:
- **`app-release.apk`** — Ready-to-install Android APK
- **`latest.json`** — Update manifest containing version info, download URL, and SHA-256 hash (consumed by the in-app updater)

---

## 🛠️ Tech Stack

| Package | Purpose |
|---|---|
| `provider` | State management (ChangeNotifier pattern) |
| `sqflite` / `sqflite_common_ffi` | Local SQLite database (Android + Desktop) |
| `webview_flutter` | In-app web reader (Android) |
| `webview_windows` | In-app web reader (Windows desktop) |
| `flutter_local_notifications` | Android push notifications |
| `workmanager` | Periodic background tasks (chapter scanning) |
| `dio` | File downloads with progress tracking (APK updates) |
| `http` | Lightweight HTTP requests (page fetching, API calls) |
| `html` | HTML DOM parsing (title extraction, chapter detection) |
| `shared_preferences` | Key-value local storage (settings, version tracking) |
| `package_info_plus` | Runtime app version info |
| `share_plus` | System share sheet integration |
| `permission_handler` | Android runtime permission requests |
| `url_launcher` / `android_intent_plus` | External browser and Brave integration |
| `crypto` | SHA-256 hash verification for update integrity |
| `open_filex` | Open downloaded APK for installation |
| `path_provider` | Platform-specific directory resolution |

---

## 📄 Changelog

### v1.1.0+25 (Latest)
- 🎬 **Watchlist category** — New category for tracking movies, series, and videos
- 🎉 **What's New dialog** — Auto-displayed changelog after each update
- 🔔 **Background chapter checking** — Periodic scanning for new manga chapters
- ⭐ **Notification center** — In-app notification tray with badge count
- 📤 **Bulk import & export** — Batch URL import, JSON backup, and restore
- 🏷️ **Auto title parsing** — Automatic title extraction from URLs
- 🔄 **Self-updating** — In-app update download via GitHub Releases
- 🛡️ **Ad blocker** — Built-in ad filtering in the web reader
- 🌍 **Bilingual UI** — Full Turkish and English localization

---

## 👨‍💻 Developer

**Yusuf Kaya**
- GitHub: [@YusufKaya00](https://github.com/YusufKaya00)

---

<p align="center">
  <sub>Built with ❤️ using Flutter & Dart</sub>
</p>
