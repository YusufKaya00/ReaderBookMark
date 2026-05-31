import 'package:flutter/material.dart';
import '../data/app_database.dart';

class NotificationProvider extends ChangeNotifier {
  final AppDatabase _db = AppDatabase();
  List<Map<String, dynamic>> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;

  List<Map<String, dynamic>> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;

  NotificationProvider() {
    load();
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    try {
      final list = await _db.getAllNotifications();
      _notifications = list;
      _unreadCount = list.where((item) => (item['is_read'] as int? ?? 0) == 0).length;
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  Future<void> markAsRead(int id) async {
    try {
      await _db.markNotificationAsRead(id);
      
      // Update local state without full reload
      final idx = _notifications.indexWhere((item) => item['id'] == id);
      if (idx != -1) {
        final mutable = Map<String, dynamic>.from(_notifications[idx]);
        if ((mutable['is_read'] as int? ?? 0) == 0) {
          mutable['is_read'] = 1;
          _notifications[idx] = mutable;
          _unreadCount = (_unreadCount - 1).clamp(0, _notifications.length);
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  Future<void> markAllAsRead() async {
    try {
      await _db.markAllNotificationsAsRead();
      _notifications = _notifications.map((item) {
        final mutable = Map<String, dynamic>.from(item);
        mutable['is_read'] = 1;
        return mutable;
      }).toList();
      _unreadCount = 0;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> delete(int id) async {
    try {
      await _db.deleteNotification(id);
      
      final idx = _notifications.indexWhere((item) => item['id'] == id);
      if (idx != -1) {
        final wasUnread = (_notifications[idx]['is_read'] as int? ?? 0) == 0;
        _notifications.removeAt(idx);
        if (wasUnread) {
          _unreadCount = (_unreadCount - 1).clamp(0, _notifications.length);
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> clearAll() async {
    try {
      await _db.deleteAllNotifications();
      _notifications.clear();
      _unreadCount = 0;
      notifyListeners();
    } catch (_) {}
  }
}
