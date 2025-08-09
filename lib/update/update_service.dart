import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
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
    // İsteğe bağlı: SHA256 doğrulaması (ota_update akışı içinde stream doğrulaması yoksa haricen indirip doğrulanabilir)
    // Basit yaklaşım: doğrudan OTA başlat.
    await OtaUpdate().execute(manifest.apkUrl, destinationFilename: 'update.apk');
  }

  static String sha256OfBytes(List<int> bytes) => sha256.convert(bytes).toString();
}


