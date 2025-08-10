import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart' as wv_mobile;
import 'package:webview_windows/webview_windows.dart' as wv_win;
import '../../background/new_chapter_check.dart';
import '../../utils/external_open.dart';

class ReaderScreen extends StatefulWidget {
  final String title;
  final String url;
  final ValueChanged<String>? onUrlChanged;
  const ReaderScreen({super.key, required this.title, required this.url, this.onUrlChanged});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final bool _isWindows = Platform.isWindows;
  wv_mobile.WebViewController? _mobile;
  wv_win.WebviewController? _win;
  double _progress = 0;
  Timer? _timer;
  late String _currentUrl;
  bool _canGoBack = false;
  bool _canGoForward = false;

  String get _scrollKey => 'scroll_${_currentUrl}';

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _init();
  }

  Future<void> _init() async {
    if (_isWindows) {
      final c = wv_win.WebviewController();
      await c.initialize();
      await c.setBackgroundColor(Colors.transparent);
      await c.setPopupWindowPolicy(wv_win.WebviewPopupWindowPolicy.deny);
      c.url.listen((u) {
        if (u != null && u.isNotEmpty && u != _currentUrl) {
          setState(() => _currentUrl = u);
          widget.onUrlChanged?.call(u);
          _updateNavState();
        }
      });
      c.loadingState.listen((s) async {
        if (s == wv_win.LoadingState.navigationCompleted) {
          await _restoreScroll();
          await _applyDark();
          setState(() => _progress = 1);
          _updateNavState();
        }
      });
      await c.loadUrl(widget.url);
      _win = c;
    } else {
      final c = wv_mobile.WebViewController()
        ..setJavaScriptMode(wv_mobile.JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          wv_mobile.NavigationDelegate(
            onPageStarted: (u) {
              if (u.isNotEmpty && u != _currentUrl) {
                setState(() => _currentUrl = u);
                widget.onUrlChanged?.call(u);
              }
              _updateNavState();
            },
            onProgress: (p) => setState(() => _progress = p / 100),
            onPageFinished: (_) async {
              await _restoreScroll();
              await _applyDark();
              _updateNavState();
            },
            onNavigationRequest: (req) {
              final u = req.url;
              if (_isAdUrl(u)) {
                return wv_mobile.NavigationDecision.prevent;
              }
              // Sadece izinli hostlara gidişlerde otomatik takibe ekle
              // İstek üzerine otomatik ekleme kaldırıldı.
              return wv_mobile.NavigationDecision.navigate;
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.url));
      _mobile = c;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _saveScroll());
  }

  bool _isAdUrl(String url) {
    final u = url.toLowerCase();
    const adPatterns = [
      'doubleclick.net',
      'googlesyndication.com',
      'adservice.google',
      'taboola',
      'outbrain',
      'zedo',
      'onclick',
      'popad',
      'propeller',
      'intent://',
      'facebook.com/tr',
      'utm_source=push',
    ];
    for (final p in adPatterns) {
      if (u.contains(p)) return true;
    }
    return false;
  }

  Future<void> _updateNavState() async {
    if (_isWindows) {
      try {
        final r = await _win?.executeScript('history.length');
        int len = 0;
        if (r is String) len = int.tryParse(r) ?? 0;
        setState(() {
          _canGoBack = len > 1;
          _canGoForward = false; // ileri tespiti güvenilir değil
        });
      } catch (_) {}
    } else {
      try {
        final canBack = await _mobile?.canGoBack() ?? false;
        final canFwd = await _mobile?.canGoForward() ?? false;
        setState(() {
          _canGoBack = canBack;
          _canGoForward = canFwd;
        });
      } catch (_) {}
    }
  }

  Future<void> _applyDark() async {
    // Dark + Opsiyonel basit CSS reklam engel (basic hide rules)
    final sp = await SharedPreferences.getInstance();
    final adOn = sp.getBool('ad_block_css') ?? false;
    final cssBuffer = StringBuffer();
    cssBuffer.writeln('html,body{background:#000!important;color:#fff!important}');
    cssBuffer.writeln('img,video{filter:brightness(.85) contrast(1.05)}');
    cssBuffer.writeln('a{color:#8ab4f8!important}');
    if (adOn) {
      cssBuffer.writeln('[id*="ad"], [class*="ad"], .ads, .ad, .advert, .banner, .sponsor, .sponsored, iframe[src*="ad"], iframe[src*="doubleclick"], div[id^="google_ads"], .cookie, .gdpr, .notification, .push-notification {display:none!important}');
    }
    final css = cssBuffer.toString().replaceAll("'", "\'");
    final js = """
const style = document.getElementById('reader-dark-style')||document.createElement('style');
style.id='reader-dark-style';
style.innerHTML='""" + css + """';
document.head.appendChild(style);
""";
    if (_isWindows) {
      await _win?.executeScript(js);
    } else {
      await _mobile?.runJavaScript(js);
    }
  }

  Future<void> _restoreScroll() async {
    final sp = await SharedPreferences.getInstance();
    final y = sp.getDouble(_scrollKey) ?? 0.0;
    if (y <= 0) return;
    final js = '(() => { const el = document.scrollingElement || document.documentElement || document.body; el.scrollTo(0, ${y.toStringAsFixed(0)}); })();';
    Future<void> apply() async {
      if (_isWindows) {
        await _win?.executeScript(js);
      } else {
        await _mobile?.runJavaScript(js);
      }
    }
    // İlk deneme ve birkaç gecikmeli deneme (dinamik içerik için)
    await apply();
    for (final delay in [300, 700, 1200, 2000]) {
      // ignore: use_build_context_synchronously
      await Future.delayed(Duration(milliseconds: delay));
      await apply();
    }
  }

  Future<void> _saveScroll() async {
    try {
      double y = 0;
      const getJs = '(() => { const el = document.scrollingElement || document.documentElement || document.body; return el.scrollTop; })();';
      if (_isWindows) {
        final r = await _win?.executeScript(getJs);
        if (r is String) y = double.tryParse(r) ?? 0;
      } else {
        final r = await _mobile?.runJavaScriptReturningResult(getJs);
        if (r is num) y = r.toDouble();
        if (r is String) y = double.tryParse(r) ?? 0;
      }
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble(_scrollKey, y);
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: WillPopScope(
        onWillPop: () async {
          try {
            if (_isWindows) {
              // Windows WebView goBack
              await _win?.goBack();
              return false;
            } else {
              if (await _mobile?.canGoBack() == true) {
                await _mobile?.goBack();
                return false;
              }
            }
          } catch (_) {}
          return true;
        },
        child: Column(
        children: [
          if (_progress < 1) LinearProgressIndicator(value: _progress, minHeight: 2),
          Expanded(
            child: _isWindows
                ? (_win == null
                    ? const SizedBox()
                    : wv_win.Webview(
                        _win!,
                        permissionRequested: (url, kind, isUserInitiated) async =>
                            wv_win.WebviewPermissionDecision.allow,
                      ))
                : wv_mobile.WebViewWidget(controller: _mobile!),
          )
        ],
      ),
      ),
      bottomNavigationBar: BottomAppBar(
        height: 64,
        child: Row(
          children: [
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Geri',
              onPressed: _canGoBack
                  ? () async {
                      try {
                        if (_isWindows) {
                          await _win?.goBack();
                        } else {
                          await _mobile?.goBack();
                        }
                      } catch (_) {}
                      _updateNavState();
                    }
                  : null,
              icon: const Icon(Icons.arrow_back),
            ),
            IconButton(
              tooltip: 'İleri',
              onPressed: _canGoForward
                  ? () async {
                      try {
                        if (_isWindows) {
                          await _win?.goForward();
                        } else {
                          await _mobile?.goForward();
                        }
                      } catch (_) {}
                      _updateNavState();
                    }
                  : null,
              icon: const Icon(Icons.arrow_forward),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Yenile',
              onPressed: () async {
                if (_isWindows) {
                  await _win?.reload();
                } else {
                  await _mobile?.reload();
                }
              },
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Tarayıcıda aç',
              onPressed: () async {
                // Dış tarayıcıya aç (Brave/Safari)
                try {
                  await openInExternalBrowser(_currentUrl);
                } catch (_) {}
              },
              icon: const Icon(Icons.open_in_new),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}


