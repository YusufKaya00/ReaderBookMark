import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openInExternalBrowser(String url) async {
  final uri = Uri.parse(url);
  if (Platform.isAndroid) {
    try {
      // Brave'e doğrudan gönderme denemesi
      final intent = AndroidIntent(
        action: 'action_view',
        data: uri.toString(),
        package: 'com.brave.browser',
      );
      await intent.launch();
      return;
    } catch (_) {
      // Devam et ve launcher'ı dene
    }
  }
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}


