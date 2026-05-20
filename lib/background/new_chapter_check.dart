import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../data/app_database.dart';

const String kTaskId = 'check_new_chapters';

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

  // Prioritize active (reading) items, limit checking list to 20 items to prevent OS background task timeout
  final activeItems = items.where((e) => e.readingState == 'reading').toList();
  final otherItems = items.where((e) => e.readingState == 'notStarted').toList();
  final itemsToCheck = [...activeItems, ...otherItems].take(20).toList();

  final sp = await SharedPreferences.getInstance();
  final notifier = FlutterLocalNotificationsPlugin();
  
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await notifier.initialize(const InitializationSettings(android: androidInit));

  for (final item in itemsToCheck) {
    try {
      final res = await http
          .get(Uri.parse(item.url), headers: {'user-agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) continue;
      
      final doc = html_parser.parse(utf8.decode(res.bodyBytes));
      final title = (doc.querySelector('title')?.text ?? item.title).trim();
      final anchors = doc.querySelectorAll('a');
      final prioritized = anchors
          .map((e) => e.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();
          
      prioritized.sort((a, b) {
        final as = a.toLowerCase();
        final bs = b.toLowerCase();
        final aw = (as.contains('chapter') || as.contains('bölüm')) ? 0 : 1;
        final bw = (bs.contains('chapter') || bs.contains('bölüm')) ? 0 : 1;
        return aw.compareTo(bw);
      });

      final seen = <String>{};
      final dedup = <String>[];
      for (final t in prioritized) {
        final norm = t.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
        if (norm.isEmpty) continue;
        if (seen.contains(norm)) continue;
        seen.add(norm);
        dedup.add(norm);
        if (dedup.length >= 100) break;
      }
      
      final chapterTexts = dedup.join('|');
      final sig = sha1.convert(utf8.encode('$title::$chapterTexts')).toString();
      final key = 'sig_${item.url}';
      final last = sp.getString(key);

      if (last != null && last != sig) {
        await notifier.show(
          sig.hashCode & 0x7fffffff,
          'Yeni bölüm olabilir: ${item.title}',
          '${item.title} sayfası güncellendi.',
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
      }
      await sp.setString(key, sig);
    } catch (_) {}
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


