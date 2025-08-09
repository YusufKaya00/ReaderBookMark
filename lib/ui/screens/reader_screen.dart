import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart' as wv_mobile;
import 'package:webview_windows/webview_windows.dart' as wv_win;

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
        }
      });
      c.loadingState.listen((s) async {
        if (s == wv_win.LoadingState.navigationCompleted) {
          await _restoreScroll();
          await _applyDark();
          setState(() => _progress = 1);
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
            },
            onProgress: (p) => setState(() => _progress = p / 100),
            onPageFinished: (_) async {
              await _restoreScroll();
              await _applyDark();
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.url));
      _mobile = c;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _saveScroll());
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
      cssBuffer.writeln('[id*="ad"], [class*="ad"], .ads, .ad, .advert, .banner, .sponsor, .sponsored {display:none!important}');
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
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: () async {
              if (_isWindows) {
                await _win?.reload();
              } else {
                await _mobile?.reload();
              }
            },
            icon: const Icon(Icons.refresh),
          )
        ],
      ),
      body: Column(
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
    );
  }
}


