import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import '../../providers/settings_provider.dart';
import '../../providers/library_provider.dart';
import '../../models/link_item.dart';
import '../../utils/translations.dart';
import '../../utils/export_helper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _importController = TextEditingController();
  final _restoreController = TextEditingController();
  bool _isImporting = false;

  @override
  void dispose() {
    _importController.dispose();
    _restoreController.dispose();
    super.dispose();
  }

  /// Slug'ı okunabilir başlığa çevir
  String _slugToTitle(String slug) {
    final readable = slug
        .replaceAll(RegExp(r'[-_]+'), ' ')
        .replaceAll(RegExp(r'\d+$'), '')
        .trim();
    if (readable.isEmpty) return slug;
    return readable.split(' ').where((w) => w.isNotEmpty).map((w) {
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }

  /// Segment bölüm/chapter bilgisi mi?
  bool _isChapterSegment(String seg) {
    final s = seg.toLowerCase();
    if (RegExp(r'^(bolum|chapter|issue|ep|episode|sezon|season|vol|volume)[-_]').hasMatch(s)) return true;
    if (RegExp(r'^\d+[-_](bolum|chapter|episode)').hasMatch(s)) return true;
    if (RegExp(r'^\d+$').hasMatch(s)) return true;
    if (s.contains('sezon-finali') || s.contains('sezon-baslangic') || s.contains('season-finale')) return true;
    return false;
  }

  /// URL path'inden okunabilir bir başlık üretir
  String _titleFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) return uri.host.replaceAll('www.', '');

      // /manga/, /comic/ gibi marker'dan sonraki segmenti al
      const markers = ['manga', 'comic', 'comics', 'webtoon', 'webtoons', 'series', 'read'];
      for (int i = 0; i < segments.length - 1; i++) {
        if (markers.contains(segments[i].toLowerCase())) {
          final candidate = segments[i + 1];
          if (!_isChapterSegment(candidate) && candidate.length > 2) {
            return _slugToTitle(candidate);
          }
          // /manga/8/isim/ formatı için bir sonrakine de bak
          if (i + 2 < segments.length) {
            final candidate2 = segments[i + 2];
            if (!_isChapterSegment(candidate2) && candidate2.length > 2) {
              return _slugToTitle(candidate2);
            }
          }
        }
      }

      // Marker yoksa: bölüm olmayan en anlamlı segmenti bul
      for (final seg in segments) {
        if (!_isChapterSegment(seg) && seg.length > 3 && !markers.contains(seg.toLowerCase())) {
          return _slugToTitle(seg);
        }
      }

      return _slugToTitle(segments.reduce((a, b) => a.length >= b.length ? a : b));
    } catch (_) {
      return url;
    }
  }

  Future<String> _fetchTitle(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http
          .get(uri, headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          })
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        String? title;

        // Manga sitelerine özgü seçiciler
        title ??= document.querySelector('h1.entry-title')?.text.trim();
        title ??= document.querySelector('h1.text-center')?.text.trim();
        title ??= document.querySelector('.post-title h1')?.text.trim();
        title ??= document.querySelector('.series-title')?.text.trim();
        title ??= document.querySelector('.manga-title')?.text.trim();
        title ??= document.querySelector('.anime-title')?.text.trim();

        // OG / Twitter meta
        title ??= document.querySelector('meta[property="og:title"]')?.attributes['content']?.trim();
        title ??= document.querySelector('meta[name="twitter:title"]')?.attributes['content']?.trim();

        // Son çare: <title> tag'i
        title ??= document.querySelector('title')?.text.trim();

        if (title != null && title.isNotEmpty) {
          title = title.replaceAll(RegExp(r'\s+'), ' ');
          title = title.replaceAll(RegExp(r'\s*[-–|]\s*(AsuraScans|Asura|MangaDex|Read|Online|Free|Manga|Webtoon|Hayalistic|Ragnar|Tortuga|Rüya|Uzay).*$', caseSensitive: false), '');
          title = title.replaceAll(RegExp(r'\s*(Bölüm|Bolum|Chapter|Issue|Episode)\s*[-\s]?\d+.*$', caseSensitive: false), '');
          title = title.trim();
          if (title.isNotEmpty) return title;
        }
      }
    } catch (_) {}
    return _titleFromUrl(url);
  }

  Future<void> _handleBatchImport() async {
    final text = _importController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isImporting = true);

    // Extract URLs using Regex
    final urlRegex = RegExp(r'(https?:\/\/[^\s,]+)');
    final matches = urlRegex.allMatches(text);
    final urls = matches.map((m) => m.group(0)!).toSet().toList();

    if (urls.isEmpty) {
      setState(() => _isImporting = false);
      return;
    }

    final library = context.read<LibraryProvider>();
    final settings = context.read<SettingsProvider>();
    int importedCount = 0;
    int updatedCount = 0;

    for (final url in urls) {
      final title = await _fetchTitle(url);

      // Var olan linki kontrol et
      final existing = library.items.where((e) => e.url == url).toList();
      if (existing.isNotEmpty) {
        // Başlığı güncelle
        final item = existing.first;
        if (item.title != title && item.id != null) {
          await library.update(item.copyWith(title: title));
          updatedCount++;
        }
        continue;
      }

      String? coverUrl;
      try {
        final uri = Uri.parse(url);
        coverUrl = 'https://www.google.com/s2/favicons?sz=128&domain_url=${uri.scheme}://${uri.host}';
      } catch (_) {}

      await library.add(
        LinkItem(
          title: title,
          url: url,
          category: 'Genel',
          coverPath: coverUrl,
          createdAt: DateTime.now(),
        ),
      );
      importedCount++;
    }

    setState(() => _isImporting = false);
    _importController.clear();

    if (mounted) {
      final lang = settings.languageCode;
      String msg;
      if (importedCount > 0 && updatedCount > 0) {
        msg = lang == 'tr'
            ? '$importedCount eklendi, $updatedCount güncellendi.'
            : '$importedCount added, $updatedCount updated.';
      } else if (updatedCount > 0) {
        msg = lang == 'tr'
            ? '$updatedCount link başlığı güncellendi.'
            : '$updatedCount link titles updated.';
      } else {
        msg = lang == 'tr'
            ? '$importedCount link başarıyla içe aktarıldı.'
            : '$importedCount links successfully imported.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.teal),
      );
    }
  }


  Future<void> _handleRestore() async {
    final text = _restoreController.text.trim();
    if (text.isEmpty) return;

    try {
      final list = json.decode(text) as List<dynamic>;
      final library = context.read<LibraryProvider>();
      int restored = 0;

      for (final itemMap in list) {
        if (itemMap is Map<String, dynamic>) {
          final item = LinkItem.fromMap(itemMap);
          // Check for duplication
          if (!library.items.any((e) => e.url == item.url)) {
            await library.add(
              LinkItem(
                title: item.title,
                url: item.url,
                category: item.category,
                coverPath: item.coverPath,
                createdAt: item.createdAt,
                readingState: item.readingState,
                lastScrollPosition: item.lastScrollPosition,
              ),
            );
            restored++;
          }
        }
      }

      _restoreController.clear();
      if (mounted) {
        Navigator.pop(context); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$restored ${context.tr('restore_success')}'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('invalid_backup')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showRestoreDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('backup_restore')),
        content: TextField(
          controller: _restoreController,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: context.tr('restore_desc'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: _handleRestore,
            child: Text(context.tr('apply')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('settings')),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: settings.isDarkMode
                ? [const Color(0xFF0C0C0C), Colors.blueGrey.shade900]
                : [Colors.blue.shade50, Colors.teal.shade50],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            // Preference Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.language, color: Colors.teal),
                      title: Text(context.tr('language')),
                      trailing: DropdownButton<String>(
                        value: settings.languageCode,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'tr', child: Text('Türkçe')),
                          DropdownMenuItem(value: 'en', child: Text('English')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            settings.setLanguageCode(val);
                            // Also refresh library to trigger localization updates
                            context.read<LibraryProvider>().load();
                          }
                        },
                      ),
                    ),
                    const Divider(),
                    SwitchListTile(
                      secondary: const Icon(Icons.dark_mode, color: Colors.indigo),
                      title: Text(context.tr('dark_mode')),
                      value: settings.isDarkMode,
                      onChanged: (val) => settings.toggleDarkMode(),
                    ),
                    const Divider(),
                    SwitchListTile(
                      secondary: const Icon(Icons.shield_outlined, color: Colors.redAccent),
                      title: Text(context.tr('ad_blocker')),
                      value: settings.adBlockCssEnabled,
                      onChanged: (val) => settings.toggleAdBlockCss(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Import Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('batch_import'),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _importController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: context.tr('batch_import_hint'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: _isImporting
                          ? const Center(child: CircularProgressIndicator())
                          : ElevatedButton.icon(
                              onPressed: _handleBatchImport,
                              icon: const Icon(Icons.playlist_add),
                              label: Text(context.tr('add')),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Backup Restore Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('backup_restore'),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => showExportDialog(context),
                            icon: const Icon(Icons.ios_share),
                            label: Text(context.tr('export')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _showRestoreDialog,
                            icon: const Icon(Icons.settings_backup_restore),
                            label: Text(context.tr('import')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
