import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/library_provider.dart';
import 'translations.dart';

Future<void> showExportDialog(BuildContext context) async {
  final library = context.read<LibraryProvider>();
  if (library.items.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('no_links')),
        backgroundColor: Colors.orangeAccent,
      ),
    );
    return;
  }

  showDialog(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final isDark = theme.brightness == Brightness.dark;

      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 12,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.teal.withAlpha(38),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.ios_share_outlined,
                      color: Colors.teal,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      context.tr('export_title'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                context.tr('export_desc'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 24),

              // Option 1: Share JSON File
              _buildOptionCard(
                context: ctx,
                icon: Icons.insert_drive_file_outlined,
                color: Colors.teal,
                title: context.tr('export_json_file'),
                subtitle: 'backup.json',
                onTap: () async {
                  Navigator.pop(ctx);
                  await _exportAsJsonFile(context);
                },
              ),
              const SizedBox(height: 12),

              // Option 2: Copy JSON to Clipboard
              _buildOptionCard(
                context: ctx,
                icon: Icons.copy_all_outlined,
                color: Colors.indigo,
                title: context.tr('export_json_clipboard'),
                subtitle: 'JSON Text',
                onTap: () async {
                  Navigator.pop(ctx);
                  await _copyJsonToClipboard(context);
                },
              ),
              const SizedBox(height: 12),

              // Option 3: Copy URLs Only to Clipboard
              _buildOptionCard(
                context: ctx,
                icon: Icons.link_outlined,
                color: Colors.blue,
                title: context.tr('export_urls_clipboard'),
                subtitle: 'URL List (.txt)',
                onTap: () async {
                  Navigator.pop(ctx);
                  await _copyUrlsToClipboard(context);
                },
              ),
              const SizedBox(height: 24),

              // Cancel button
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    context.tr('cancel'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _buildOptionCard({
  required BuildContext context,
  required IconData icon,
  required Color color,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.black12,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withAlpha(31),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _exportAsJsonFile(BuildContext context) async {
  try {
    final library = context.read<LibraryProvider>();
    final data = library.items.map((e) => e.toMap()).toList();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

    // Save to temp directory first for max sharing compatibility
    final directory = await getTemporaryDirectory();
    final fileName = 'reader_bookmark_backup_${DateTime.now().millisecondsSinceEpoch}.json';
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(jsonStr);

    final xFile = XFile(file.path, mimeType: 'application/json');
    await Share.shareXFiles(
      [xFile],
      subject: 'ReaderBookmark Backup',
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('export_success')),
          backgroundColor: Colors.teal,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.tr('error')}: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}

Future<void> _copyJsonToClipboard(BuildContext context) async {
  try {
    final library = context.read<LibraryProvider>();
    final data = library.items.map((e) => e.toMap()).toList();
    final jsonStr = json.encode(data);

    await Clipboard.setData(ClipboardData(text: jsonStr));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('backup_copied')),
          backgroundColor: Colors.teal,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.tr('error')}: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}

Future<void> _copyUrlsToClipboard(BuildContext context) async {
  try {
    final library = context.read<LibraryProvider>();
    final urls = library.items.map((e) => e.url).join('\n');

    await Clipboard.setData(ClipboardData(text: urls));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('export_urls_copied')),
          backgroundColor: Colors.teal,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.tr('error')}: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}
