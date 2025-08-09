import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'dart:io' as io;
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
  // YusufKaya00/ReaderBookMark releases/latest manifest
  static const String manifestUrl =
      'https://github.com/YusufKaya00/ReaderBookMark/releases/latest/download/latest.json';

  static Future<UpdateManifest?> fetchManifest() async {
    try {
      final res = await http.get(Uri.parse(manifestUrl));
      if (res.statusCode != 200) return null;
      final map = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return UpdateManifest.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isUpdateAvailable() async {
    if (!Platform.isAndroid) return false;
    final manifest = await fetchManifest();
    if (manifest == null) return false;
    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;
    return manifest.buildNumber > currentBuild;
  }

  static Future<void> startUpdate({UpdateManifest? manifest}) async {
    if (!Platform.isAndroid) return;
    manifest ??= await fetchManifest();
    if (manifest == null) return;
    // APK'yi app-specific external files dizinine indir
    final baseDir = await io.Directory('/sdcard/Android/data/com.example.deneme/files/Download').create(recursive: true);
    final savePath = '${baseDir.path}/readerbookmark_update.apk';
    final dio = Dio();
    await dio.download(manifest.apkUrl, savePath);
    if (manifest.sha256 != null) {
      final f = io.File(savePath);
      final bytes = await f.readAsBytes();
      final sum = sha256OfBytes(bytes);
      if (sum.toLowerCase() != manifest.sha256!.toLowerCase()) {
        await f.delete().catchError((_) => f);
        return;
      }
    }
    // FileProvider URI ile kurulum ekranı aç
    // FileProvider URI: content://<authority>/...
    final file = io.File(savePath);
    final uriString = 'content://${'${'com.example.deneme'}.fileprovider'}${file.path}';
    try {
      final intent = AndroidIntent(
        action: 'action_view',
        data: uriString,
        type: 'application/vnd.android.package-archive',
        flags: <int>[268435456, 1, 2],
      );
      await intent.launch();
    } catch (_) {
      await OpenFilex.open(savePath);
    }
  }

  static String sha256OfBytes(List<int> bytes) => sha256.convert(bytes).toString();
}


