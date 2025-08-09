import 'dart:convert';

class LinkItem {
  final int? id;
  final String title;
  final String url;
  final String? coverPath;
  final String category;
  final DateTime createdAt;
  final double lastScrollPosition;

  const LinkItem({
    this.id,
    required this.title,
    required this.url,
    this.coverPath,
    required this.category,
    required this.createdAt,
    this.lastScrollPosition = 0.0,
  });

  LinkItem copyWith({
    int? id,
    String? title,
    String? url,
    String? coverPath,
    String? category,
    DateTime? createdAt,
    double? lastScrollPosition,
  }) {
    return LinkItem(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      coverPath: coverPath ?? this.coverPath,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      lastScrollPosition: lastScrollPosition ?? this.lastScrollPosition,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'url': url,
      'cover_path': coverPath,
      'category': category,
      'created_at': createdAt.millisecondsSinceEpoch,
      'last_scroll_position': lastScrollPosition,
    };
  }

  factory LinkItem.fromMap(Map<String, dynamic> map) {
    return LinkItem(
      id: map['id'] as int?,
      title: map['title'] as String,
      url: map['url'] as String,
      coverPath: map['cover_path'] as String?,
      category: map['category'] as String? ?? 'Genel',
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int? ?? 0),
      lastScrollPosition: (map['last_scroll_position'] as num?)?.toDouble() ??
          0.0,
    );
  }

  String toJson() => json.encode(toMap());
  factory LinkItem.fromJson(String source) =>
      LinkItem.fromMap(json.decode(source) as Map<String, dynamic>);
}


