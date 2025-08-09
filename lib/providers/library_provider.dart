import 'package:flutter/foundation.dart';
import '../data/app_database.dart';
import '../models/link_item.dart';

class LibraryProvider extends ChangeNotifier {
  final AppDatabase _db = AppDatabase();

  List<LinkItem> _items = [];
  String _query = '';
  String _category = 'Tümü';

  List<LinkItem> get items => _items;
  String get query => _query;
  String get category => _category;

  Future<void> load() async {
    _items = await _db.getAllLinks(query: _query, category: _category);
    notifyListeners();
  }

  Future<void> add(LinkItem item) async {
    await _db.insertLink(item);
    await load();
  }

  Future<void> remove(int id) async {
    await _db.deleteLink(id);
    await load();
  }

  Future<void> removeMany(List<int> ids) async {
    await _db.deleteLinks(ids);
    await load();
  }

  Future<void> update(LinkItem item) async {
    await _db.updateLink(item);
    await load();
  }

  Future<void> updateScroll(int id, double y) async {
    await _db.updateScrollPosition(id: id, y: y);
    final i = _items.indexWhere((e) => e.id == id);
    if (i >= 0) {
      _items[i] = _items[i].copyWith(lastScrollPosition: y);
      notifyListeners();
    }
  }

  void setQuery(String v) {
    _query = v;
    load();
  }

  void setCategory(String v) {
    _category = v;
    load();
  }

  Future<void> updateCategoryMany(List<int> ids, String category) async {
    await _db.updateCategoryMany(ids: ids, category: category);
    await load();
  }
}


