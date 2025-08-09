import 'dart:convert';
// import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
// Alarm manager kaldırıldı; manuel kontrol veya ileride Workmanager ile devam edilecek.

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
    final sp = await SharedPreferences.getInstance();
    final urls = sp.getStringList('tracked_urls') ?? <String>[];
    if (urls.isEmpty) return;

    final notifier = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await notifier.initialize(const InitializationSettings(android: androidInit));

    for (final url in urls) {
      try {
        final res = await http.get(Uri.parse(url), headers: {'user-agent': 'Mozilla/5.0'});
        if (res.statusCode != 200) continue;
        final doc = html_parser.parse(utf8.decode(res.bodyBytes));
        // Basit sezgisel: sayfa başlığı + ilk link listesi hash’i
        final title = (doc.querySelector('title')?.text ?? '').trim();
        final chapterTexts = doc
            .querySelectorAll('a')
            .map((e) => e.text.trim())
            .where((e) => e.isNotEmpty)
            .take(80)
            .join('|');
        final sig = sha1.convert(utf8.encode('$title::$chapterTexts')).toString();
        final key = 'sig_$url';
        final last = sp.getString(key);
        if (last != null && last != sig) {
          // İçerik değişmiş → yeni bölüm olma ihtimali yüksek
          await notifier.show(
            sig.hashCode & 0x7fffffff,
            'Yeni bölüm olabilir',
            '$title sayfası güncellendi',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'chapters', 'Chapters', importance: Importance.defaultImportance,
              ),
            ),
          );
        }
        await sp.setString(key, sig);
      } catch (_) {}
    }
    return;
}

Future<void> runCheckNow() => _alarmEntry();

Future<void> addTrackedUrl(String url) async {
  final sp = await SharedPreferences.getInstance();
  final urls = sp.getStringList('tracked_urls') ?? <String>[];
  if (!urls.contains(url)) {
    urls.add(url);
    await sp.setStringList('tracked_urls', urls);
  }
}

Future<void> removeTrackedUrl(String url) async {
  final sp = await SharedPreferences.getInstance();
  final urls = sp.getStringList('tracked_urls') ?? <String>[];
  urls.remove(url);
  await sp.setStringList('tracked_urls', urls);
}


