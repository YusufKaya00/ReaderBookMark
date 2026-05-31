import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/link_item.dart';
import 'reader_screen.dart';
import '../../utils/translations.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  String _getRelativeTime(BuildContext context, int milliseconds) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = now - milliseconds;
    final isTr = Localizations.localeOf(context).languageCode == 'tr';

    if (diff < 60000) {
      return isTr ? 'Şimdi' : 'Just now';
    }
    final mins = (diff / 60000).round();
    if (mins < 60) {
      return isTr ? '$mins dk önce' : '${mins}m ago';
    }
    final hours = (diff / 3600000).round();
    if (hours < 24) {
      return isTr ? '$hours sa önce' : '${hours}h ago';
    }
    final days = (diff / 86400000).round();
    return isTr ? '$days gün önce' : '${days}d ago';
  }

  void _handleTapNotification(BuildContext context, Map<String, dynamic> notification) async {
    final nav = Navigator.of(context);
    final lib = context.read<LibraryProvider>();
    final notificationProvider = context.read<NotificationProvider>();

    // Mark as read
    final id = notification['id'] as int?;
    if (id != null) {
      await notificationProvider.markAsRead(id);
    }

    final url = notification['url'] as String;
    final linkId = notification['link_id'] as int?;

    // Look up matching bookmarked item
    LinkItem? foundItem;
    for (final item in lib.items) {
      if ((linkId != null && item.id == linkId) || item.url == url) {
        foundItem = item;
        break;
      }
    }

    if (foundItem != null) {
      final item = foundItem;
      // If not started, mark as reading
      if (item.readingState == 'notStarted') {
        await lib.update(item.copyWith(readingState: 'reading'));
      }
      
      nav.push(
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            title: item.title,
            url: url, // Open the new chapter URL from notification
            onUrlChanged: (newUrl) async {
              await lib.update(item.copyWith(url: newUrl));
            },
            onScrollChanged: (y) async {
              if (item.id != null) {
                await lib.updateScroll(item.id!, y);
              }
            },
          ),
        ),
      );
    } else {
      // Not in library, open a generic reader
      nav.push(
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            title: notification['title'] as String? ?? 'Okuyucu',
            url: url,
          ),
        ),
      );
    }
  }

  void _showDeleteConfirmDialog(BuildContext context, NotificationProvider provider) {
    final isTr = Localizations.localeOf(context).languageCode == 'tr';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isTr ? 'Tümünü Temizle' : 'Clear All'),
        content: Text(
          isTr 
              ? 'Tüm bildirimleri silmek istediğinize emin misiniz?' 
              : 'Are you sure you want to delete all notifications?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              provider.clearAll();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(isTr ? 'Temizle' : 'Clear'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();
    final settings = context.watch<SettingsProvider>();
    final isDark = settings.isDarkMode;
    final isTr = Localizations.localeOf(context).languageCode == 'tr';

    return Scaffold(
      appBar: AppBar(
        title: Text(isTr ? 'Bildirimler' : 'Notifications'),
        actions: [
          if (provider.notifications.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.playlist_add_check),
              tooltip: isTr ? 'Tümünü Okundu İşaretle' : 'Mark All as Read',
              onPressed: () => provider.markAllAsRead(),
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: isTr ? 'Tümünü Temizle' : 'Clear All',
              onPressed: () => _showDeleteConfirmDialog(context, provider),
            ),
          ]
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF0C0C0C), Colors.blueGrey.shade900]
                : [Colors.blue.shade50, Colors.teal.shade50],
          ),
        ),
        child: provider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : provider.notifications.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_none_outlined,
                          size: 72,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isTr ? 'Hiç bildiriminiz yok.' : 'You have no notifications.',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: provider.notifications.length,
                    itemBuilder: (ctx, index) {
                      final item = provider.notifications[index];
                      final id = item['id'] as int;
                      final isRead = (item['is_read'] as int? ?? 0) == 1;
                      final createdAt = item['created_at'] as int;

                      return Dismissible(
                        key: ValueKey(id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withAlpha(200),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) {
                          provider.delete(id);
                        },
                        child: Card(
                          elevation: isRead ? 1 : 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          color: isRead
                              ? (isDark ? const Color(0xFF161616) : Colors.white.withAlpha(200))
                              : (isDark ? const Color(0xFF222828) : const Color(0xFFE8F5F5)),
                          child: InkWell(
                            onTap: () => _handleTapNotification(context, item),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  // Favicon / Cover
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white10 : Colors.black12,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: item['cover_path'] != null &&
                                              (item['cover_path'] as String).isNotEmpty
                                          ? Image.network(
                                              item['cover_path'] as String,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => const Icon(
                                                Icons.bookmark_outline,
                                                color: Colors.teal,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.star,
                                              color: Colors.teal,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Text Content
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['title'] as String? ?? '',
                                          style: TextStyle(
                                            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          item['message'] as String? ?? '',
                                          style: TextStyle(
                                            color: isDark ? Colors.white60 : Colors.black87,
                                            fontSize: 12,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _getRelativeTime(context, createdAt),
                                          style: TextStyle(
                                            color: isDark ? Colors.white38 : Colors.black38,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Status Indicator Dot
                                  if (!isRead)
                                    Container(
                                      width: 10,
                                      height: 10,
                                      margin: const EdgeInsets.only(left: 8),
                                      decoration: const BoxDecoration(
                                        color: Colors.teal,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
