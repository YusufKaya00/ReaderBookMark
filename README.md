# 📖 ReaderBookMark

<p align="center">
  <img src="logo1.jpg" width="120" alt="ReaderBookMark Logo"/>
</p>

<p align="center">
  <strong>Manga, kitap ve web içeriklerini tek yerden takip edin.</strong><br/>
  <em>Track manga, books, and web content from a single place.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.7+-02569B?logo=flutter&logoColor=white" alt="Flutter"/>
  <img src="https://img.shields.io/badge/Dart-3.7+-0175C2?logo=dart&logoColor=white" alt="Dart"/>
  <img src="https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white" alt="Android"/>
  <img src="https://img.shields.io/badge/License-Private-lightgrey" alt="License"/>
</p>

---

## ✨ Özellikler / Features

### 📚 Kitaplık Yönetimi / Library Management
- Manga, kitap, makale, izlenecekler (watchlist) ve genel kategorileriyle linkleri düzenleyin
- Okuma durumu takibi: **Başlanmadı**, **Okunuyor**, **Tamamlandı**
- Toplu link ekleme ve düzenleme
- URL'den otomatik başlık çıkarma (manga siteleri için optimize)
- Kapak görseli desteği

### 🔔 Yeni Bölüm Bildirimleri / New Chapter Notifications
- Desteklenen manga sitelerinden otomatik yeni bölüm taraması
- Arka planda çalışan akıllı kontrol mekanizması
- Uygulama içi bildirim ekranı (Yıldız ikonu ile)
- Android yerel bildirimleri

### 🌐 Entegre Okuyucu / Built-in Reader
- Uygulama içi web görüntüleyici (WebView)
- Reklam engelleyici desteği
- Metin çeviri özelliği
- Tarayıcıda veya Brave'de açma seçenekleri

### 📤 Dışa/İçe Aktarma / Export & Import
- JSON dosyası olarak paylaşma
- JSON verisini panoya kopyalama
- Sadece linkleri dışa aktarma
- JSON yedekten geri yükleme

### 🔄 Otomatik Güncelleme / Auto-Update
- GitHub Releases üzerinden uygulama içi güncelleme kontrolü
- Tek dokunuşla indirme ve kurulum
- SHA-256 doğrulama ile güvenli güncelleme

### 🎨 Kullanıcı Deneyimi / User Experience
- 🌙 Karanlık tema / Dark mode
- 🌍 Türkçe ve İngilizce dil desteği
- 📱 Modern Material Design arayüzü
- ⭐ Güncelleme sonrası "Yenilikler" ekranı

---

## 📁 Proje Yapısı / Project Structure

```
lib/
├── background/          # Arka plan servisleri (yeni bölüm kontrolü)
├── data/                # Veritabanı (SQLite) katmanı
├── models/              # Veri modelleri
├── providers/           # State management (Provider)
│   ├── library_provider.dart
│   ├── settings_provider.dart
│   └── notification_provider.dart
├── ui/
│   ├── screens/         # Uygulama ekranları
│   │   ├── home_screen.dart
│   │   ├── reader_screen.dart
│   │   ├── settings_screen.dart
│   │   ├── notifications_screen.dart
│   │   ├── sites_screen.dart
│   │   └── about_screen.dart
│   └── widgets/         # Yeniden kullanılabilir bileşenler
│       ├── add_link_dialog.dart
│       └── edit_link_dialog.dart
├── update/              # Uygulama içi güncelleme servisi
├── utils/               # Yardımcı araçlar (çeviriler, paylaşım vb.)
└── main.dart            # Uygulama giriş noktası
```

---

## 🏗️ Kurulum / Setup

### Gereksinimler / Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) `>= 3.7.0`
- Android SDK
- Java 17

### Derleme / Build

```bash
# Bağımlılıkları yükle / Install dependencies
flutter pub get

# Debug modunda çalıştır / Run in debug mode
flutter run

# Release APK derle / Build release APK
flutter build apk --release

# Release App Bundle derle / Build release AAB
flutter build appbundle --release
```

Derlenen APK dosyası:
```
build/app/outputs/flutter-apk/app-release.apk
```

---

## 🚀 CI/CD

Proje, GitHub Actions ile otomatik derleme ve release oluşturma sürecine sahiptir.

| Tetikleyici | Açıklama |
|---|---|
| `push → main` | Her push'ta otomatik APK derlenir ve GitHub Release oluşturulur |
| Tag `v*` | Versiyon taglarında release tetiklenir |

Her release şunları içerir:
- `app-release.apk` — kuruluma hazır APK dosyası
- `latest.json` — uygulama içi güncelleme manifest dosyası (sürüm, APK URL, SHA-256)

---

## 📦 Desteklenen Siteler / Supported Sites

Yeni bölüm kontrolü için varsayılan olarak desteklenen manga siteleri:

| Site | URL |
|---|---|
| Hayalistic | `hayalistic.com.tr` |
| Tortuga Çeviri | `tortugaceviri.com` |
| Rüya Manga | `ruyamanga.net` |
| Asura Comic | `asuracomic.net` |
| Tempest Mangas | `tempestmangas.com` |
| Asura Scans TR | `asurascans.com.tr` |
| Uzay Manga | `uzaymanga.com` |

> 💡 Uygulama içinden **Siteleri Yönet** ekranı ile kendi sitelerinizi de ekleyebilirsiniz.

---

## 🛠️ Kullanılan Teknolojiler / Tech Stack

| Paket | Kullanım Amacı |
|---|---|
| `provider` | State management |
| `sqflite` | Yerel SQLite veritabanı |
| `webview_flutter` | Uygulama içi web görüntüleyici |
| `flutter_local_notifications` | Yerel bildirimler |
| `workmanager` | Arka plan görevleri |
| `dio` | HTTP dosya indirme (güncelleme) |
| `http` | Web istekleri |
| `html` | HTML parsing (başlık çıkarma) |
| `shared_preferences` | Yerel ayar depolama |
| `package_info_plus` | Uygulama sürüm bilgisi |
| `share_plus` | İçerik paylaşma |
| `permission_handler` | Android izin yönetimi |
| `url_launcher` | Harici tarayıcı açma |

---

## 📄 Sürüm Geçmişi / Changelog

### v1.1.0+25 (Güncel / Latest)
- 🎬 **İzlenecekler kategorisi** — Dizi, film ve video takibi için yeni kategori
- 🎉 **Yenilikler ekranı** — Güncelleme sonrası otomatik yenilikler diyaloğu
- 🔔 **Bölüm bildirimi kontrolü** — Arka plan yeni bölüm taraması
- ⭐ **Bildirim ekranı** — Uygulama içi bildirim tepsisi
- 📤 **Toplu link ekleme & dışa/içe aktarma** — JSON yedekleme ve geri yükleme
- 🏷️ **Otomatik isim ayırma** — URL'den manga adı çıkarma
- 🔄 **Otomatik güncelleme** — GitHub Releases üzerinden uygulama içi güncelleme

---

## 👨‍💻 Geliştirici / Developer

**Yusuf Kaya**

---

<p align="center">
  <sub>Made with ❤️ and Flutter</sub>
</p>
