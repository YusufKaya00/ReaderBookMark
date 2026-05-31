import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/link_item.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../../background/new_chapter_check.dart';
import '../widgets/add_link_dialog.dart';
import '../widgets/edit_link_dialog.dart';
import 'reader_screen.dart';
import '../../utils/external_open.dart';
import '../../update/update_service.dart';
import 'about_screen.dart';
import 'sites_screen.dart';
import 'settings_screen.dart';
import 'notifications_screen.dart';
import '../../utils/translations.dart';
import '../../utils/export_helper.dart';
import '../../providers/notification_provider.dart';

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
  bool _loaded = false;
  bool _showFilters = false; // Filter visibility toggle

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final settings = context.read<SettingsProvider>();
    final library = context.read<LibraryProvider>();
    await settings.load();
    await library.load();
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final library = context.watch<LibraryProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: _buildAppBar(context, settings, library, theme),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAdd,
        icon: const Icon(Icons.add),
        label: Text(context.tr('add')),
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
        child: Column(
          children: [
            // Search bar with filter button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: context.tr('search'),
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: theme.cardColor.withValues(alpha: 0.8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                      ),
                      onChanged: (v) => context.read<LibraryProvider>().setQuery(v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Filter toggle button
                  IconButton(
                    icon: Icon(
                      _showFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
                      color: _showFilters ? theme.colorScheme.primary : null,
                    ),
                    tooltip: context.tr('filters'),
                    onPressed: () => setState(() => _showFilters = !_showFilters),
                  ),
                ],
              ),
            ),

            // Collapsible filter section
            if (_showFilters) _buildFilterRow(context, library),

            // Content
            Expanded(child: _buildContent(context, library, theme)),
          ],
        ),
      ),
    );
  }

  // ─── AppBar ───
  PreferredSizeWidget _buildAppBar(BuildContext context, SettingsProvider settings, LibraryProvider library, ThemeData theme) {
    return AppBar(
      title: _selectionMode
          ? Text('${_selectedIds.length} ${context.tr('selected_count')}')
          : Text(context.tr('title'), style: const TextStyle(fontWeight: FontWeight.bold)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      actions: [
        if (_selectionMode) ...[
          IconButton(
            tooltip: context.tr('pick_state'),
            onPressed: () async {
              final newState = await _pickReadingState(context);
              if (newState != null && mounted) {
                await context.read<LibraryProvider>().updateReadingStateMany(_selectedIds.toList(), newState);
                setState(() => _selectedIds.clear());
              }
            },
            icon: const Icon(Icons.bookmark_added_outlined),
          ),
          IconButton(
            tooltip: context.tr('pick_category'),
            onPressed: () async {
              final newCat = await _pickCategory(context);
              if (newCat != null && mounted) {
                await context.read<LibraryProvider>().updateCategoryMany(_selectedIds.toList(), newCat);
                setState(() => _selectedIds.clear());
              }
            },
            icon: const Icon(Icons.label_outline),
          ),
          IconButton(
            tooltip: context.tr('delete'),
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
            tooltip: context.tr('cancel'),
            onPressed: () => setState(() => _selectedIds.clear()),
            icon: const Icon(Icons.clear),
          ),
        ],
        if (!_selectionMode) ...[
          // Notifications Star Badge
          Consumer<NotificationProvider>(
            builder: (ctx, notProvider, _) {
              final count = notProvider.unreadCount;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    tooltip: Localizations.localeOf(ctx).languageCode == 'tr' 
                        ? 'Bildirimler' 
                        : 'Notifications',
                    icon: Icon(
                      count > 0 ? Icons.star : Icons.star_border_outlined, 
                      size: 24, 
                      color: count > 0 ? Colors.amber : null,
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
                      );
                    },
                  ),
                  if (count > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          // Dark mode toggle
          IconButton(
            tooltip: settings.isDarkMode ? 'Light Mode' : 'Dark Mode',
            icon: Icon(settings.isDarkMode ? Icons.wb_sunny : Icons.nightlight_round, size: 22),
            onPressed: () => context.read<SettingsProvider>().toggleDarkMode(),
          ),
          // Settings
          IconButton(
            tooltip: context.tr('settings'),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
            icon: const Icon(Icons.settings, size: 22),
          ),
          // Main menu - çevirileri önceden hesapla (itemBuilder içinde context.watch kullanılamaz)
          Builder(builder: (btnContext) {
            final trCheckChapters = context.tr('check_chapters');
            final trCheckUpdate = context.tr('check_update');
            final trExport = context.tr('export');
            final trManageSites = context.tr('manage_sites');
            final trAbout = context.tr('about');
            return PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Menü',
              onSelected: (value) => _handleMenuAction(value, context),
              itemBuilder: (_) => [
                _menuItem(Icons.notifications_active_outlined, trCheckChapters, 'check_chapters'),
                _menuItem(Icons.system_update, trCheckUpdate, 'check_update'),
                _menuItem(Icons.share, trExport, 'export'),
                const PopupMenuDivider(),
                _menuItem(Icons.public, trManageSites, 'sites'),
                _menuItem(Icons.info_outline, trAbout, 'about'),
              ],
            );
          }),
        ],
        // Undo button
        if (_undoStack.isNotEmpty)
          IconButton(
            tooltip: context.tr('undo'),
            onPressed: () async {
              final last = _undoStack.removeLast();
              final type = last['type'] as String;
              final before = (last['before'] as List).cast<dynamic>();
              final prov = context.read<LibraryProvider>();
              if (type == 'bulk_delete' || type == 'single_delete') {
                for (final m in before) await prov.add(m);
              } else if (type == 'bulk_category' || type == 'single_update') {
                for (final m in before) await prov.update(m);
              }
            },
            icon: const Icon(Icons.undo),
          ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(IconData icon, String text, String value) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(text),
        ],
      ),
    );
  }

  Future<void> _handleMenuAction(String v, BuildContext context) async {
    if (v == 'export') {
      showExportDialog(context);
    } else if (v == 'check_chapters') {
      _showLoadingThen(context, () => runCheckNow(), context.tr('check_chapters_done'));
    } else if (v == 'check_update') {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      final manifest = await UpdateService.getUpdateInfo();
      if (!mounted) return;
      Navigator.of(context).pop();
      if (manifest != null) {
        _showUpdateDialog(context, manifest);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('app_up_to_date'))),
        );
      }
    } else if (v == 'about') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen()));
    } else if (v == 'sites') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SitesScreen()));
    }
  }

  void _showLoadingThen(BuildContext ctx, Future<void> Function() task, String doneMsg) async {
    showDialog(context: ctx, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    await task();
    if (!mounted) return;
    Navigator.of(ctx).pop();
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(doneMsg)));
  }

  void _showUpdateDialog(BuildContext ctx, UpdateManifest manifest) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(ctx.tr('update_available')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${ctx.tr('languageCode') == 'tr' ? 'Yeni sürüm' : 'New version'}: ${manifest.versionName}'),
            if (manifest.changelog != null && manifest.changelog!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                manifest.changelog!,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Text(ctx.tr('update_prompt')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _startDownloadWithProgress(ctx, manifest);
            },
            child: Text(ctx.tr('update_btn')),
          ),
        ],
      ),
    );
  }

  void _startDownloadWithProgress(BuildContext ctx, UpdateManifest manifest) {
    final progressNotifier = ValueNotifier<double>(0);
    
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<double>(
            valueListenable: progressNotifier,
            builder: (_, progress, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(value: progress > 0 ? progress : null),
                const SizedBox(height: 16),
                Text(
                  progress > 0
                      ? '${ctx.tr('downloading')} %${(progress * 100).toInt()}'
                      : ctx.tr('downloading'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    UpdateService.startUpdate(
      manifest: manifest,
      onProgress: (received, total) {
        if (total > 0) {
          progressNotifier.value = received / total;
        }
      },
    ).then((_) {
      if (mounted) Navigator.of(ctx).pop();
    }).catchError((e) {
      if (mounted) {
        Navigator.of(ctx).pop();
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('${ctx.tr('error')}: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });
  }

  // ─── Filter Row (two separate rows) ───
  Widget _buildFilterRow(BuildContext context, LibraryProvider library) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reading State filters (top row)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip(context, library, 'Tümü', '📚 ${context.tr('all')}', isCategory: false),
                _chip(context, library, 'reading', '📖 ${context.tr('reading')}', isCategory: false),
                _chip(context, library, 'completed', '✅ ${context.tr('completed')}', isCategory: false),
                _chip(context, library, 'notStarted', '⏳ ${context.tr('not_started')}', isCategory: false),
              ],
            ),
          ),
        ),
        // Category filters (bottom row)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip(context, library, 'Tümü', context.tr('all'), isCategory: true),
                _chip(context, library, 'Genel', context.tr('general'), isCategory: true),
                _chip(context, library, 'Manga', context.tr('manga'), isCategory: true),
                _chip(context, library, 'Kitap', context.tr('book'), isCategory: true),
                _chip(context, library, 'Makale', context.tr('article'), isCategory: true),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, LibraryProvider library, String value, String label, {required bool isCategory}) {
    final isSelected = isCategory
        ? library.category == value
        : library.readingState == value;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        selected: isSelected,
        label: Text(label, style: const TextStyle(fontSize: 12)),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: (_) {
          if (isCategory) {
            context.read<LibraryProvider>().setCategory(value);
          } else {
            context.read<LibraryProvider>().setReadingState(value);
          }
        },
      ),
    );
  }

  // ─── Content Area ───
  Widget _buildContent(BuildContext context, LibraryProvider library, ThemeData theme) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (library.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.0),
              duration: const Duration(milliseconds: 1500),
              curve: Curves.easeInOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(opacity: value, child: child),
                );
              },
              child: Icon(Icons.bookmark_outline, size: 80, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('no_links'),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('languageCode') == 'tr' ? '+ butonuna basarak eklemeye başlayın' : 'Tap + to start adding',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
      itemCount: library.items.length,
      // Performance optimizations
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      cacheExtent: 500,
      itemExtent: 130, // Sabit yükseklik = daha hızlı layout
      itemBuilder: (context, index) {
        final item = library.items[index];
        final selected = item.id != null && _selectedIds.contains(item.id);
        return RepaintBoundary(
          key: ValueKey(item.id),
          child: _buildItemCard(context, item, selected, theme),
        );
      },
    );
  }

  // ─── Individual Item Card (List style) ───
  Widget _buildItemCard(BuildContext context, LinkItem item, bool selected, ThemeData theme) {
    Color stateColor;
    String stateLabel;
    IconData stateIcon;
    switch (item.readingState) {
      case 'reading':
        stateColor = Colors.teal;
        stateLabel = context.tr('reading');
        stateIcon = Icons.auto_stories;
        break;
      case 'completed':
        stateColor = Colors.indigo;
        stateLabel = context.tr('completed');
        stateIcon = Icons.check_circle;
        break;
      case 'notStarted':
      default:
        stateColor = Colors.blueGrey;
        stateLabel = context.tr('not_started');
        stateIcon = Icons.schedule;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: selected ? 6 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: selected
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openReader(context, item),
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
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Cover thumbnail - daha büyük
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 72,
                  height: 96,
                  child: item.coverPath != null && item.coverPath!.isNotEmpty
                      ? Image.network(
                          item.coverPath!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _defaultCover(stateColor),
                          cacheWidth: 144, // Performance: cache smaller size
                        )
                      : _defaultCover(stateColor),
                ),
              ),
              const SizedBox(width: 14),

              // Title + badges
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, height: 1.3),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        // Category badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            item.category,
                            style: TextStyle(
                              color: theme.colorScheme.secondary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        // State badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: stateColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: stateColor.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(stateIcon, size: 13, color: stateColor),
                              const SizedBox(width: 4),
                              Text(
                                stateLabel,
                                style: TextStyle(color: stateColor, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // Scroll progress bar
                    if (item.lastScrollPosition > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: (item.lastScrollPosition / 5000).clamp(0.0, 1.0),
                            minHeight: 4,
                            backgroundColor: Colors.grey.shade300,
                            valueColor: AlwaysStoppedAnimation(stateColor),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Three-dot menu
              IconButton(
                icon: Icon(Icons.more_vert, color: theme.iconTheme.color, size: 24),
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => _showItemMenu(context, item),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Show item menu using bottom sheet for better reliability
  void _showItemMenu(BuildContext context, LinkItem item) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share),
              title: Text(context.tr('share')),
              onTap: () {
                Navigator.pop(ctx);
                _handleItemAction('share', item, context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_browser),
              title: Text(context.tr('open_brave')),
              onTap: () {
                Navigator.pop(ctx);
                _handleItemAction('open_brave', item, context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(context.tr('edit')),
              onTap: () {
                Navigator.pop(ctx);
                _handleItemAction('edit', item, context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(context.tr('not_started')),
              onTap: () {
                Navigator.pop(ctx);
                _handleItemAction('state_notStarted', item, context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_stories),
              title: Text(context.tr('reading')),
              onTap: () {
                Navigator.pop(ctx);
                _handleItemAction('state_reading', item, context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle),
              title: Text(context.tr('completed')),
              onTap: () {
                Navigator.pop(ctx);
                _handleItemAction('state_completed', item, context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: Text(context.tr('delete'), style: const TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                _handleItemAction('delete', item, context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _defaultCover(Color color) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.6), color],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(child: Icon(Icons.menu_book, size: 34, color: Colors.white)),
    );
  }

  // ─── Item Actions ───
  Future<void> _handleItemAction(String action, LinkItem item, BuildContext ctx) async {
    final prov = ctx.read<LibraryProvider>();
    switch (action) {
      case 'share':
        Share.share(item.url, subject: item.title);
        break;
      case 'open_brave':
        await openInExternalBrowser(item.url);
        break;
      case 'edit':
        _undoStack.add({'type': 'single_update', 'before': [item.copyWith()]});
        if (!ctx.mounted) return;
        showDialog(
          context: ctx,
          builder: (_) => EditLinkDialog(
            initialTitle: item.title,
            initialUrl: item.url,
            initialCategory: item.category,
            initialCover: item.coverPath,
            onSubmit: ({required String title, required String url, required String category, String? cover}) async {
              await prov.update(item.copyWith(
                title: title.isEmpty ? url : title,
                url: url,
                category: category,
                coverPath: cover,
              ));
            },
          ),
        );
        break;
      case 'delete':
        _undoStack.add({'type': 'single_delete', 'before': [item.copyWith()]});
        if (item.id != null) await prov.remove(item.id!);
        break;
      case 'state_notStarted':
        await prov.update(item.copyWith(readingState: 'notStarted'));
        break;
      case 'state_reading':
        await prov.update(item.copyWith(readingState: 'reading'));
        break;
      case 'state_completed':
        await prov.update(item.copyWith(readingState: 'completed'));
        break;
    }
  }

  void _openReader(BuildContext ctx, LinkItem item) async {
    final prov = ctx.read<LibraryProvider>();
    if (item.readingState == 'notStarted') {
      await prov.update(item.copyWith(readingState: 'reading'));
    }
    if (!ctx.mounted) return;
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          title: item.title,
          url: item.url,
          onUrlChanged: (newUrl) async {
            if (item.id == null) return;
            await prov.update(item.copyWith(url: newUrl));
          },
          onScrollChanged: (y) async {
            if (item.id == null) return;
            await prov.updateScroll(item.id!, y);
          },
        ),
      ),
    );
  }

  // ─── Add Dialog ───
  void _showAdd() {
    showDialog(
      context: context,
      builder: (_) => AddLinkDialog(
        onSubmit: ({required String title, required String url, required String category, String? cover}) async {
          String? coverUrl = cover;
          if (coverUrl == null || coverUrl.isEmpty) {
            try {
              final uri = Uri.parse(url);
              final guess = Uri.parse('https://www.google.com/s2/favicons?sz=128&domain_url=${uri.scheme}://${uri.host}');
              final res = await http.get(guess).timeout(const Duration(seconds: 2));
              if (res.statusCode == 200) coverUrl = guess.toString();
            } catch (_) {}
          }
          if (!mounted) return;
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

// ─── Dialogs ───
Future<String?> _pickCategory(BuildContext context) async {
  String temp = 'Genel';
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(context.tr('pick_category')),
      content: DropdownButtonFormField<String>(
        value: temp,
        items: [
          DropdownMenuItem(value: 'Genel', child: Text(context.tr('general'))),
          DropdownMenuItem(value: 'Manga', child: Text(context.tr('manga'))),
          DropdownMenuItem(value: 'Kitap', child: Text(context.tr('book'))),
          DropdownMenuItem(value: 'Makale', child: Text(context.tr('article'))),
        ],
        onChanged: (v) => temp = v ?? 'Genel',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
        ElevatedButton(onPressed: () => Navigator.pop(context, temp), child: Text(context.tr('apply'))),
      ],
    ),
  );
}

Future<String?> _pickReadingState(BuildContext context) async {
  String temp = 'notStarted';
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(context.tr('pick_state')),
      content: DropdownButtonFormField<String>(
        value: temp,
        items: [
          DropdownMenuItem(value: 'notStarted', child: Text(context.tr('not_started'))),
          DropdownMenuItem(value: 'reading', child: Text(context.tr('reading'))),
          DropdownMenuItem(value: 'completed', child: Text(context.tr('completed'))),
        ],
        onChanged: (v) => temp = v ?? 'notStarted',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
        ElevatedButton(onPressed: () => Navigator.pop(context, temp), child: Text(context.tr('apply'))),
      ],
    ),
  );
}
