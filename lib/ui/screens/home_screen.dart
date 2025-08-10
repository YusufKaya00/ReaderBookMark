import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../models/link_item.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../../background/new_chapter_check.dart';
import '../widgets/add_link_dialog.dart';
import '../widgets/edit_link_dialog.dart';
import 'reader_screen.dart';
import '../../utils/external_open.dart';
import 'package:share_plus/share_plus.dart';
import '../../update/update_service.dart';
import 'about_screen.dart';
import 'sites_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final Set<int> _selectedIds = <int>{};
  bool get _selectionMode => _selectedIds.isNotEmpty;
  final List<Map<String, dynamic>> _undoStack = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await context.read<SettingsProvider>().load();
      await context.read<LibraryProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final library = context.watch<LibraryProvider>();

    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('${_selectedIds.length} seçildi')
            : const Text('Kitaplık'),
        actions: [
          if (_selectionMode) ...[
            IconButton(
              tooltip: 'Kategoriyi değiştir',
              onPressed: () async {
                final newCat = await _pickCategory(context);
                if (newCat != null) {
                  // undo push
                  final before = library.items
                      .where((e) => e.id != null && _selectedIds.contains(e.id))
                      .map((e) => e.copyWith())
                      .toList();
                  _undoStack.add({'type': 'bulk_category', 'before': before});
                  await context.read<LibraryProvider>().updateCategoryMany(_selectedIds.toList(), newCat);
                  setState(() => _selectedIds.clear());
                }
              },
              icon: const Icon(Icons.label_outline),
            ),
            IconButton(
              tooltip: 'Seçilileri sil',
              onPressed: () async {
                final before = library.items
                    .where((e) => e.id != null && _selectedIds.contains(e.id))
                    .map((e) => e.copyWith())
                    .toList();
                _undoStack.add({'type': 'bulk_delete', 'before': before});
                await context.read<LibraryProvider>().removeMany(_selectedIds.toList());
                setState(() => _selectedIds.clear());
              },
              icon: const Icon(Icons.delete_forever),
            ),
            IconButton(
              tooltip: 'Seçimi temizle',
              onPressed: () => setState(() => _selectedIds.clear()),
              icon: const Icon(Icons.clear),
            ),
          ],
          if (!_selectionMode) ...[
            PopupMenuButton<String>(
              onSelected: (v) async {
                final prov = context.read<LibraryProvider>();
                if (v == 'export') {
                  final data = prov.items.map((e) => e.toMap()).toList();
                  final jsonStr = data.toString();
                  await Share.share(jsonStr, subject: 'Kitaplık Dışa Aktarım');
                } else if (v == 'check_chapters') {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const Center(child: CircularProgressIndicator()),
                  );
                  await runCheckNow();
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Yeni bölüm kontrolü tamamlandı.')),
                  );
                } else if (v == 'check_update') {
                  // Güncelleme kontrolü
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const Center(child: CircularProgressIndicator()),
                  );
                  final available = await UpdateService.isUpdateAvailable();
                  if (!mounted) return;
                  Navigator.of(context).pop(); // progress kapat
                  if (available) {
                    // Onay diyalogu
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Güncelleme mevcut'),
                        content: const Text('Yeni sürümü indirmek ve kurmak ister misiniz?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
                          ElevatedButton(
                            onPressed: () async {
                              Navigator.pop(context);
                              await UpdateService.startUpdate();
                            },
                            child: const Text('Güncelle'),
                          ),
                        ],
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Uygulama güncel.')),
                    );
                  }
                } else if (v == 'about') {
                  if (mounted) {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen()));
                  }
                } else if (v == 'sites') {
                  if (mounted) {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SitesScreen()));
                  }
                }
              },
              itemBuilder: (c) => const [
                PopupMenuItem(value: 'check_chapters', child: Text('Yeni bölümleri kontrol et')),
                PopupMenuItem(value: 'check_update', child: Text('Güncellemeyi kontrol et')),
                PopupMenuItem(value: 'export', child: Text('Dışa aktar (paylaş)')),
                PopupMenuItem(value: 'about', child: Text('Yapımcı')),
                PopupMenuItem(value: 'sites', child: Text('Siteleri Yönet')),
              ],
            ),
          ],
          // Üst barda reklam engelle ve gece modu taşındı (alt bara)
          // Seçim tümü alt barda gösteriliyor
          IconButton(
            tooltip: 'Geri al',
            onPressed: _undoStack.isEmpty
                ? null
                : () async {
                    final last = _undoStack.removeLast();
                    final type = last['type'] as String;
                    final before = (last['before'] as List).cast<dynamic>();
                    if (type == 'bulk_delete') {
                      // silinenleri geri ekle
                      for (final m in before) {
                        // m bir LinkItem
                        await context.read<LibraryProvider>().add(m);
                      }
                    } else if (type == 'bulk_category') {
                      // önceki kategorilere geri dön
                      for (final m in before) {
                        await context.read<LibraryProvider>().update(m);
                      }
                    } else if (type == 'single_update') {
                      await context.read<LibraryProvider>().update(before.first);
                    } else if (type == 'single_delete') {
                      await context.read<LibraryProvider>().add(before.first);
                    }
                  },
            icon: const Icon(Icons.undo),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAdd,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: BottomAppBar(
        height: 60,
        child: Row(
          children: [
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Siteleri Yönet',
              icon: const Icon(Icons.public),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SitesScreen()));
              },
            ),
            IconButton(
              tooltip: settings.adBlockCssEnabled ? 'Reklam engelle: Açık' : 'Reklam engelle: Kapalı',
              icon: Icon(settings.adBlockCssEnabled ? Icons.shield_moon : Icons.shield_outlined),
              onPressed: () => context.read<SettingsProvider>().toggleAdBlockCss(),
            ),
            IconButton(
              tooltip: settings.isDarkMode ? 'Aydınlık mod' : 'Karanlık mod',
              icon: Icon(settings.isDarkMode ? Icons.dark_mode : Icons.light_mode),
              onPressed: () => context.read<SettingsProvider>().toggleDarkMode(),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Yeni bölümleri kontrol et',
              icon: const Icon(Icons.notifications_active_outlined),
              onPressed: () async {
                showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
                await runCheckNow();
                if (!mounted) return;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Yeni bölüm kontrolü tamamlandı.')));
              },
            ),
            if (_selectionMode)
              IconButton(
                tooltip: 'Tümünü seç',
                onPressed: () {
                  final items = context.read<LibraryProvider>().items;
                  setState(() {
                    _selectedIds
                      ..clear()
                      ..addAll(items.where((e) => e.id != null).map((e) => e.id!));
                  });
                },
                icon: const Icon(Icons.select_all),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('wp.jpg'),
            fit: BoxFit.cover,
            opacity: 0.15,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Ara...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        isDense: true,
                      ),
                      onChanged: (v) => context.read<LibraryProvider>().setQuery(v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: library.category,
                    items: const [
                      DropdownMenuItem(value: 'Tümü', child: Text('Tümü')),
                      DropdownMenuItem(value: 'Genel', child: Text('Genel')),
                      DropdownMenuItem(value: 'Manga', child: Text('Manga')),
                      DropdownMenuItem(value: 'Kitap', child: Text('Kitap')),
                      DropdownMenuItem(value: 'Makale', child: Text('Makale')),
                    ],
                    onChanged: (v) => context.read<LibraryProvider>().setCategory(v ?? 'Tümü'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder(
                future: library.items.isEmpty ? context.read<LibraryProvider>().load() : null,
                builder: (context, snapshot) {
                  if (library.items.isEmpty) {
                    return const Center(child: Text('Henüz link yok. + ile ekleyin.'));
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: library.items.length,
                    itemBuilder: (context, index) {
                      final item = library.items[index];
                      final selected = item.id != null && _selectedIds.contains(item.id);
                      return GestureDetector(
                        onLongPress: () {
                          if (item.id == null) return;
                          setState(() {
                            if (_selectedIds.contains(item.id)) {
                              _selectedIds.remove(item.id);
                            } else {
                              _selectedIds.add(item.id!);
                            }
                          });
                        },
                        onDoubleTap: () {
                          Share.share(item.url, subject: item.title);
                        },
                        child: Stack(
                          children: [
                            _LibraryCard(item: item, index: index),
                            if (selected)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: CircleAvatar(
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  radius: 14,
                                  child: const Icon(Icons.check, size: 16, color: Colors.white),
                                ),
                              ),
                            Positioned(
                              top: 6,
                              left: 6,
                              child: PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, size: 18),
                                onSelected: (v) async {
                                  final prov = context.read<LibraryProvider>();
                                  if (v == 'share') {
                                    Share.share(item.url, subject: item.title);
                                  } else if (v == 'open_brave') {
                                    await openInExternalBrowser(item.url);
                                  } else if (v == 'edit') {
                                    // Undo için önceki halini sakla
                                    _undoStack.add({'type': 'single_update', 'before': [item.copyWith()]});
                                    showDialog(
                                      context: context,
                                      builder: (_) => EditLinkDialog(
                                        initialTitle: item.title,
                                        initialUrl: item.url,
                                        initialCategory: item.category,
                                        initialCover: item.coverPath,
                                        onSubmit: ({required String title, required String url, required String category, String? cover}) async {
                                          await prov.update(
                                            item.copyWith(
                                              title: title.isEmpty ? url : title,
                                              url: url,
                                              category: category,
                                              coverPath: cover,
                                            ),
                                        );
                                        },
                                      ),
                                    );
                                  } else if (v == 'delete') {
                                  _undoStack.add({'type': 'single_delete', 'before': [item.copyWith()]});
                                  if (item.id != null) await prov.remove(item.id!);
                                  }
                                },
                                itemBuilder: (ctx) => const [
                                  PopupMenuItem(value: 'share', child: Text('Paylaş')),
                                  PopupMenuItem(value: 'open_brave', child: Text('Brave\'de aç')),
                                  PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                                  PopupMenuItem(value: 'delete', child: Text('Sil')),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAdd() {
    showDialog(
      context: context,
      builder: (_) => AddLinkDialog(
        onSubmit: ({required String title, required String url, required String category, String? cover}) async {
          // Basit kapak üretme: site favicon denemesi
          String? coverUrl = cover;
          if ((coverUrl == null || coverUrl.isEmpty)) {
            try {
              final uri = Uri.parse(url);
              final guess = Uri.parse('https://www.google.com/s2/favicons?sz=128&domain_url=${uri.scheme}://${uri.host}');
              final res = await http.get(guess);
              if (res.statusCode == 200) coverUrl = guess.toString();
            } catch (_) {}
          }
          await context.read<LibraryProvider>().add(
                LinkItem(
                  title: title.isEmpty ? url : title,
                  url: url,
                  category: category,
                  coverPath: coverUrl,
                  createdAt: DateTime.now(),
                ),
              );
        },
      ),
    );
  }
}

Future<String?> _pickCategory(BuildContext context) async {
  String temp = 'Genel';
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Kategori seçin'),
      content: DropdownButton<String>(
        value: temp,
        items: const [
          DropdownMenuItem(value: 'Genel', child: Text('Genel')),
          DropdownMenuItem(value: 'Manga', child: Text('Manga')),
          DropdownMenuItem(value: 'Kitap', child: Text('Kitap')),
          DropdownMenuItem(value: 'Makale', child: Text('Makale')),
        ],
        onChanged: (v) => temp = v ?? 'Genel',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
        ElevatedButton(onPressed: () => Navigator.pop(context, temp), child: const Text('Uygula')),
      ],
    ),
  );
}

class _LibraryCard extends StatelessWidget {
  final LinkItem item;
  final int index;
  const _LibraryCard({required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReaderScreen(
              title: item.title,
              url: item.url,
              onUrlChanged: (newUrl) async {
                final prov = context.read<LibraryProvider>();
                if (item.id == null) return;
                await prov.update(item.copyWith(url: newUrl));
              },
            ),
          ),
        );
      },
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: item.coverPath == null || item.coverPath!.isEmpty
                    ? Container(
                        color: Colors.grey.shade300,
                        child: const Icon(Icons.public, size: 48),
                      )
                    : Image.network(
                        item.coverPath!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.public, size: 48),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.category,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Düzenle',
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => EditLinkDialog(
                              initialTitle: item.title,
                              initialUrl: item.url,
                              initialCategory: item.category,
                              initialCover: item.coverPath,
                              onSubmit: ({required String title, required String url, required String category, String? cover}) async {
                                final prov = context.read<LibraryProvider>();
                                await prov.update(
                                  item.copyWith(
                                    title: title.isEmpty ? url : title,
                                    url: url,
                                    category: category,
                                    coverPath: cover,
                                  ),
                                );
                              },
                            ),
                          );
                        },
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Brave\'de aç',
                        onPressed: () => openInExternalBrowser(item.url),
                        icon: const Icon(Icons.open_in_new),
                      ),
                      // Kart üzerinden silme kaldırıldı (Geri al uyumu için üst menüde kullanın)
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


