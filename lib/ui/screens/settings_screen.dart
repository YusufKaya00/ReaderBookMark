import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../../providers/settings_provider.dart';
import '../../providers/library_provider.dart';
import '../../models/link_item.dart';
import '../../utils/translations.dart';

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

  Future<String> _fetchTitle(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http
          .get(uri, headers: {'user-agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        final match = RegExp(r'<title>(.*?)<\/title>', caseSensitive: false, dotAll: true)
            .firstMatch(body);
        if (match != null && match.group(1) != null) {
          // HTML entities clean up
          return match.group(1)!.trim().replaceAll(RegExp(r'&quot;'), '"').replaceAll(RegExp(r'&amp;'), '&');
        }
      }
    } catch (_) {}
    try {
      final host = Uri.parse(url).host;
      return host.replaceAll('www.', '');
    } catch (_) {
      return url;
    }
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
    int importedCount = 0;

    for (final url in urls) {
      // Check if URL already exists
      final exists = library.items.any((e) => e.url == url);
      if (exists) continue;

      final title = await _fetchTitle(url);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$importedCount ${context.tr('import_success')}'),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  Future<void> _handleBackup() async {
    final library = context.read<LibraryProvider>();
    final data = library.items.map((e) => e.toMap()).toList();
    final jsonStr = json.encode(data);

    await Clipboard.setData(ClipboardData(text: jsonStr));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('backup_copied')),
          backgroundColor: Colors.teal,
        ),
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
                            onPressed: _handleBackup,
                            icon: const Icon(Icons.copy_all),
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
