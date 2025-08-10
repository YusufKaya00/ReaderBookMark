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

// Sabit izinli site alan adları
const List<String> kAllowedHosts = [
  'hayalistic.com.tr',
  'tortugaceviri.com',
  'ruyamanga.net',
  'asuracomic.net',
  'tempestmangas.com',
  'asurascans.com.tr',
  'uzaymanga.com',
];

List<String> getAllowedHosts() => List.unmodifiable(kAllowedHosts);
bool isAllowedUrl(String url) {
  try {
    final h = Uri.parse(url).host.toLowerCase();
    return kAllowedHosts.any((a) => h == a || h.endsWith('.' + a));
  } catch (_) {
    return false;
  }
}

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
    final manual = sp.getStringList('tracked_urls') ?? <String>[];
    // Kütüphanedeki url'lerle eşleşen (host prefix) tekil sayfaları topla
    final libPrefix = <String>{};
    // Kütüphane URL’lerini almak için SharedPreferences yerine DB gerekir.
    // Basit yaklaşım: manuel listede verilen domain prefixleri üzerinden kontrol et.
    // (Gelişmiş: DB'den başlık/url çekilip hashlenebilir.)
    final urls = <String>{}..addAll(manual);
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
        // Manga siteleri için 'chapter' içeren bağlantıları daha yüksek öncelikle topla
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
        // Tekillik: aynı seriye ait tekrar eden satırları azaltmaya çalış
        final seen = <String>{};
        final dedup = <String>[];
        for (final t in prioritized) {
          final norm = t.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
          if (norm.isEmpty) continue;
          if (seen.contains(norm)) continue;
          seen.add(norm);
          dedup.add(norm);
          if (dedup.length >= 120) break;
        }
        final chapterTexts = dedup.join('|');
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

Future<List<String>> getTrackedUrls() async {
  final sp = await SharedPreferences.getInstance();
  final urls = sp.getStringList('tracked_urls') ?? <String>[];
  return urls;
}

Future<void> addTrackedUrl(String url) async {
  // İstek üzerine otomatik ekleme devre dışı.
}

Future<void> removeTrackedUrl(String url) async {
  final sp = await SharedPreferences.getInstance();
  final urls = sp.getStringList('tracked_urls') ?? <String>[];
  urls.remove(url);
  await sp.setStringList('tracked_urls', urls);
}


