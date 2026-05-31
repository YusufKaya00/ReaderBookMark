import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'dart:io' as io;
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class UpdateManifest {
  final String versionName;
  final int buildNumber;
  final String apkUrl;
  final String? sha256;
  final String? changelog;

  UpdateManifest({
    required this.versionName,
    required this.buildNumber,
    required this.apkUrl,
    this.sha256,
    this.changelog,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> map) => UpdateManifest(
        versionName: map['versionName'] as String,
        buildNumber: (map['buildNumber'] as num).toInt(),
        apkUrl: map['apkUrl'] as String,
        sha256: map['sha256'] as String?,
        changelog: map['changelog'] as String?,
      );
}

class UpdateService {
  // GitHub repo bilgileri
  static const String _owner = 'YusufKaya00';
  static const String _repo = 'ReaderBookMark';

  // Önce latest.json manifest'i dene, sonra GitHub API
  static const String _manifestUrl =
      'https://github.com/$_owner/$_repo/releases/latest/download/latest.json';
  static const String _apiUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  /// GitHub Releases'tan en son sürümü kontrol et
  static Future<UpdateManifest?> fetchManifest() async {
    // Yöntem 1: latest.json manifest dosyası
    try {
      final res = await http.get(Uri.parse(_manifestUrl)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final map = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return UpdateManifest.fromJson(map);
      }
    } catch (e) {
      debugPrint('Manifest fetch failed: $e');
    }

    // Yöntem 2: GitHub API
    try {
      final res = await http.get(
        Uri.parse(_apiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final tagName = data['tag_name'] as String? ?? '';
        final body = data['body'] as String? ?? '';
        final assets = data['assets'] as List<dynamic>? ?? [];

        // APK asset'ini bul
        String? apkUrl;
        for (final asset in assets) {
          final name = (asset['name'] as String? ?? '').toLowerCase();
          if (name.endsWith('.apk')) {
            apkUrl = asset['browser_download_url'] as String?;
            break;
          }
        }

        if (apkUrl == null) return null;

        // Version bilgisini tag'den çıkar: v1.1.0+3 → versionName=1.1.0, buildNumber=3
        final versionMatch = RegExp(r'v?(\d+\.\d+\.\d+)\+?(\d+)?').firstMatch(tagName);
        final versionName = versionMatch?.group(1) ?? tagName;
        final buildNumber = int.tryParse(versionMatch?.group(2) ?? '0') ?? 0;

        return UpdateManifest(
          versionName: versionName,
          buildNumber: buildNumber,
          apkUrl: apkUrl,
          changelog: body.isNotEmpty ? body : 'Release $tagName',
        );
      }
    } catch (e) {
      debugPrint('GitHub API fetch failed: $e');
    }

    return null;
  }

  /// Güncelleme var mı kontrol et
  static Future<bool> isUpdateAvailable() async {
    if (!Platform.isAndroid) return false;
    final manifest = await fetchManifest();
    if (manifest == null) return false;
    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;
    return manifest.buildNumber > currentBuild;
  }

  /// Manifest bilgisini döndür (dialog'da changelog göstermek için)
  static Future<UpdateManifest?> getUpdateInfo() async {
    if (!Platform.isAndroid) return null;
    final manifest = await fetchManifest();
    if (manifest == null) return null;
    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;
    if (manifest.buildNumber > currentBuild) return manifest;
    return null;
  }

  /// APK'yı indir ve kur
  static Future<void> startUpdate({
    UpdateManifest? manifest,
    void Function(int received, int total)? onProgress,
  }) async {
    if (!Platform.isAndroid) return;
    manifest ??= await fetchManifest();
    if (manifest == null) return;

    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}/readerbookmark_update.apk';

      // Eski dosyayı temizle
      final oldFile = io.File(savePath);
      if (await oldFile.exists()) {
        await oldFile.delete();
      }

      // APK'yı indir
      final dio = Dio();
      await dio.download(
        manifest.apkUrl,
        savePath,
        onReceiveProgress: (received, total) {
          onProgress?.call(received, total);
        },
        options: Options(
          receiveTimeout: const Duration(minutes: 5),
          headers: {
            'Accept': 'application/octet-stream',
          },
        ),
      );

      // SHA256 doğrulama
      if (manifest.sha256 != null && manifest.sha256!.isNotEmpty) {
        final f = io.File(savePath);
        final bytes = await f.readAsBytes();
        final sum = sha256OfBytes(bytes);
        if (sum.toLowerCase() != manifest.sha256!.toLowerCase()) {
          debugPrint('SHA256 mismatch! Expected: ${manifest.sha256}, Got: $sum');
          await f.delete().catchError((_) => f);
          return;
        }
      }

      // APK'yı aç ve kur
      final openResult = await OpenFilex.open(savePath, type: 'application/vnd.android.package-archive');
      debugPrint('OpenFilex result: ${openResult.type} - ${openResult.message}');

      if (openResult.type != ResultType.done) {
        // Alternatif yöntem: Android Intent
        try {
          final info = await PackageInfo.fromPlatform();
          final authority = '${info.packageName}.fileprovider';
          final intent = AndroidIntent(
            action: 'action_view',
            data: 'content://$authority${savePath}',
            type: 'application/vnd.android.package-archive',
            flags: <int>[
              268435456, // FLAG_ACTIVITY_NEW_TASK
              1,         // FLAG_GRANT_READ_URI_PERMISSION
              2,         // FLAG_GRANT_WRITE_URI_PERMISSION
            ],
          );
          await intent.launch();
        } catch (e) {
          debugPrint('Intent launch failed: $e');
        }
      }
    } catch (e) {
      debugPrint('Update failed: $e');
      rethrow;
    }
  }

  static String sha256OfBytes(List<int> bytes) => sha256.convert(bytes).toString();
}
