import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../data/app_database.dart';
import '../models/link_item.dart';

const String kTaskId = 'check_new_chapters';

const List<String> kNotificationAllowedHosts = [
  'hayalistic.com.tr',
  'tortugaceviri.com',
  'ruyamanga.net',
  'asuracomic.net',
  'tempestmangas.com',
  'asurascans.com.tr',
  'uzaymanga.com',
];

Future<void> initBackground() async {
  await Workmanager().initialize(_workCallback, isInDebugMode: false);
  await Workmanager().registerPeriodicTask(
    'chapters_periodic',
    kTaskId,
    frequency: const Duration(hours: 3),
    initialDelay: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

void callbackDispatcher() {}

@pragma('vm:entry-point')
void _workCallback() {
  Workmanager().executeTask((task, input) async {
    if (task == kTaskId) {
      await _alarmEntry();
    }
    return Future.value(true);
  });
}

Future<void> _alarmEntry() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  final items = await db.getAllLinks();
  if (items.isEmpty) return;

  final sp = await SharedPreferences.getInstance();
  final notifier = FlutterLocalNotificationsPlugin();
  
  const androidInit = AndroidInitializationSettings('ic_launcher');
  await notifier.initialize(const InitializationSettings(android: androidInit));

  // 1. DIRECT CHECK: Inspect base manga pages of active bookmarks (up to 15 bookmarks)
  // Prioritize active (reading) bookmarks
  final activeItems = items.where((e) => e.readingState == 'reading').toList();
  final otherItems = items.where((e) => e.readingState == 'notStarted').toList();
  final bookmarksToCheck = [...activeItems, ...otherItems].take(15).toList();

  // Check bookmarks concurrently in chunks of 5
  for (int i = 0; i < bookmarksToCheck.length; i += 5) {
    final chunk = bookmarksToCheck.sublist(i, (i + 5).clamp(0, bookmarksToCheck.length));
    await Future.wait(chunk.map((item) => _checkSingleLink(item, sp, notifier, db)));
  }

  // 2. HOMEPAGE CHECK: Scan Site Manager homepages for matches with all bookmarks (up to 100)
  final bookmarkSlugs = <String, LinkItem>{};
  for (final item in items) {
    final slug = _getMangaSlug(item.url);
    if (slug.isNotEmpty) {
      bookmarkSlugs[slug] = item;
    }
  }

  if (bookmarkSlugs.isNotEmpty) {
    final manualSites = sp.getStringList('tracked_urls') ?? <String>[];
    final sitesToCheck = [...kNotificationAllowedHosts.map((h) => 'https://$h')];
    for (final s in manualSites) {
      if (!sitesToCheck.contains(s)) sitesToCheck.add(s);
    }

    // Check homepages concurrently in chunks of 3
    for (int i = 0; i < sitesToCheck.length; i += 3) {
      final chunk = sitesToCheck.sublist(i, (i + 3).clamp(0, sitesToCheck.length));
      await Future.wait(chunk.map((siteUrl) => _checkHomepageForUpdates(siteUrl, bookmarkSlugs, sp, notifier, db)));
    }
  }
}

Future<void> runCheckNow() => _alarmEntry();

Future<List<String>> getTrackedUrls() async {
  final db = AppDatabase();
  final items = await db.getAllLinks();
  return items.map((e) => e.url).toList();
}

Future<void> addTrackedUrl(String url) async {}
Future<void> removeTrackedUrl(String url) async {}

// --- HELPER UTILITIES ---

bool _isChapterSegment(String seg) {
  final s = seg.toLowerCase();
  if (RegExp(r'^(bolum|chapter|issue|ep|episode|sezon|season|vol|volume|ch)[-_]').hasMatch(s)) return true;
  if (RegExp(r'^\d+$').hasMatch(s)) return true;
  return false;
}

String _getMangaSlug(String url) {
  try {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    for (int i = 0; i < segments.length; i++) {
      if (const ['manga', 'series', 'comic', 'comics', 'webtoon', 'webtoons'].contains(segments[i].toLowerCase())) {
        if (i + 1 < segments.length) return segments[i + 1].toLowerCase();
      }
    }
    // Fallback to the longest segment that isn't a chapter/bölüm or helper keyword
    final candidates = segments.where((s) => 
        !_isChapterSegment(s) && s.length > 3 && s.toLowerCase() != 'manga'
    ).toList();
    if (candidates.isNotEmpty) return candidates.first.toLowerCase();
  } catch (_) {}
  return '';
}

String _getMangaBaseUrl(String url) {
  try {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return url;
    
    // Common patterns for chapters: bolum-XX, chapter-XX, issue-XX, ep-XX, etc.
    final chapterPattern = RegExp(
      r'^(bolum|chapter|issue|ep|episode|sezon|season|vol|volume|ch)[-_]?\d+',
      caseSensitive: false,
    );
    
    // If the last segment matches chapter pattern or is a pure number
    if (chapterPattern.hasMatch(segments.last) || RegExp(r'^\d+$').hasMatch(segments.last)) {
      final newPath = '/${segments.take(segments.length - 1).join('/')}';
      return uri.replace(path: newPath).toString();
    }
  } catch (_) {}
  return url;
}

Future<void> _checkSingleLink(LinkItem item, SharedPreferences sp, FlutterLocalNotificationsPlugin notifier, AppDatabase db) async {
  try {
    final baseUrl = _getMangaBaseUrl(item.url);
    final res = await http
        .get(Uri.parse(baseUrl), headers: {'user-agent': 'Mozilla/5.0'})
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return;

    final doc = html_parser.parse(utf8.decode(res.bodyBytes));
    final title = (doc.querySelector('title')?.text ?? item.title).trim();
    final anchors = doc.querySelectorAll('a');
    
    // Find all chapter-like links on the page
    final chapterLinks = <String, String>{}; // Text -> Url
    for (final a in anchors) {
      final href = a.attributes['href'];
      if (href == null || href.isEmpty) continue;
      
      final text = a.text.trim();
      final url = href.startsWith('http') ? href : Uri.parse(baseUrl).replace(path: href).toString();
      
      final lowerText = text.toLowerCase();
      if (lowerText.contains('chapter') || lowerText.contains('bölüm') || lowerText.contains('ep-') || lowerText.contains('ch-')) {
        // Dedup and normalize
        final normText = text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (normText.isNotEmpty && !chapterLinks.containsKey(normText)) {
          chapterLinks[normText] = url;
        }
      }
    }

    if (chapterLinks.isEmpty) return;

    // Create signature based on sorted keys
    final sortedKeys = chapterLinks.keys.toList()..sort();
    final chapterTexts = sortedKeys.join('|');
    final sig = sha1.convert(utf8.encode('$title::$chapterTexts')).toString();
    
    final key = 'sig_${item.url}';
    final last = sp.getString(key);

    if (last != null && last != sig) {
      // Find the newest chapter URL to link the notification to
      String targetUrl = item.url;
      String newChapterName = '';
      
      // Look for a chapter URL that isn't the current bookmarked one
      for (final entry in chapterLinks.entries) {
        if (entry.value != item.url) {
          targetUrl = entry.value;
          newChapterName = entry.key;
          break;
        }
      }

      final notifyKey = 'notified_$targetUrl';
      final alreadyNotified = sp.getBool(notifyKey) ?? false;

      if (!alreadyNotified) {
        await sp.setBool(notifyKey, true);
        
        final desc = newChapterName.isNotEmpty 
            ? 'Yeni bölüm: $newChapterName' 
            : '${item.title} sayfası güncellendi.';
            
        // Trigger notification
        await notifier.show(
          targetUrl.hashCode & 0x7fffffff,
          'Yeni Bölüm: ${item.title}',
          desc,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'chapters_channel',
              'Yeni Bölümler',
              channelDescription: 'Kitaplık yeni bölüm bildirimleri',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
            ),
          ),
        );

        // Insert into App Database
        await db.insertNotification({
          'link_id': item.id,
          'title': 'Yeni Bölüm: ${item.title}',
          'message': desc,
          'url': targetUrl,
          'cover_path': item.coverPath,
          'is_read': 0,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
      }
    }
    await sp.setString(key, sig);
  } catch (_) {}
}

Future<void> _checkHomepageForUpdates(
  String siteUrl,
  Map<String, LinkItem> bookmarkSlugs,
  SharedPreferences sp,
  FlutterLocalNotificationsPlugin notifier,
  AppDatabase db,
) async {
  try {
    final res = await http
        .get(Uri.parse(siteUrl), headers: {'user-agent': 'Mozilla/5.0'})
        .timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) return;

    final doc = html_parser.parse(utf8.decode(res.bodyBytes));
    final anchors = doc.querySelectorAll('a');
    
    for (final a in anchors) {
      final href = a.attributes['href'];
      if (href == null || href.isEmpty) continue;
      
      final linkText = a.text.trim();
      final linkUrl = href.startsWith('http') ? href : Uri.parse(siteUrl).replace(path: href).toString();
      
      final linkSlug = _getMangaSlug(linkUrl);
      if (linkSlug.isNotEmpty && bookmarkSlugs.containsKey(linkSlug)) {
        final bookmarkedItem = bookmarkSlugs[linkSlug]!;
        
        // Match! Check if we haven't notified for this URL
        final notifyKey = 'notified_$linkUrl';
        final alreadyNotified = sp.getBool(notifyKey) ?? false;
        
        if (bookmarkedItem.url != linkUrl && !alreadyNotified) {
          await sp.setBool(notifyKey, true);
          
          final title = bookmarkedItem.title;
          final desc = linkText.isNotEmpty ? linkText : '${bookmarkedItem.title} sayfası güncellendi.';
          
          // Trigger system notification
          await notifier.show(
            linkUrl.hashCode & 0x7fffffff,
            'Yeni Bölüm: $title',
            desc,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'chapters_channel',
                'Yeni Bölümler',
                channelDescription: 'Kitaplık yeni bölüm bildirimleri',
                importance: Importance.high,
                priority: Priority.high,
                playSound: true,
              ),
            ),
          );

          // Save to App Database
          await db.insertNotification({
            'link_id': bookmarkedItem.id,
            'title': 'Yeni Bölüm: $title',
            'message': desc,
            'url': linkUrl,
            'cover_path': bookmarkedItem.coverPath,
            'is_read': 0,
            'created_at': DateTime.now().millisecondsSinceEpoch,
          });
        }
      }
    }
  } catch (_) {}
}
