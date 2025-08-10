import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openInExternalBrowser(String url) async {
  final uri = Uri.parse(url);
  if (Platform.isAndroid) {
    // 1) Paket bazlı Android intent (öncelikli ve en güvenilir yöntem)
    const candidates = <String>[
      'com.brave.browser',
      'com.brave.browser_beta',
      'com.brave.browser_nightly',
      // bazı cihazlarda eski default paket adı
      'com.brave.browser_default',
    ];
    for (final pkg in candidates) {
      try {
        final intent = AndroidIntent(
          action: 'android.intent.action.VIEW',
          data: uri.toString(),
          package: pkg,
          flags: <int>[268435456], // FLAG_ACTIVITY_NEW_TASK
        );
        await intent.launch();
        return;
      } catch (_) {
        // sonraki pakete dene
      }
    }

    // 2) Brave URL scheme dene (bazı cihazlarda destekli)
    final braveUri = Uri.parse('brave://open-url?url=${Uri.encodeComponent(uri.toString())}');
    if (await canLaunchUrl(braveUri)) {
      final ok = await launchUrl(braveUri, mode: LaunchMode.externalApplication);
      if (ok) return;
    }
  }

  // 3) Fallback: sistem varsayılan
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}


