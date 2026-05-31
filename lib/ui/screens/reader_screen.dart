import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart' as wv_mobile;
import 'package:webview_windows/webview_windows.dart' as wv_win;

import '../../utils/external_open.dart';
import '../../utils/translations.dart';

class ReaderScreen extends StatefulWidget {
  final String title;
  final String url;
  final ValueChanged<String>? onUrlChanged;
  final ValueChanged<double>? onScrollChanged;

  const ReaderScreen({
    super.key,
    required this.title,
    required this.url,
    this.onUrlChanged,
    this.onScrollChanged,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final bool _isWindows = Platform.isWindows;

  wv_mobile.WebViewController? _mobile;
  wv_win.WebviewController? _win;

  bool _winReady = false; // Windows WebView hazır mı?
  double _progress = 0;
  Timer? _scrollTimer;
  late String _currentUrl;
  late String _originalUrl;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String _lastBlockedUrl = '';

  // Çeviri
  String _selectedText = '';
  String _translatedText = '';
  bool _isTranslating = false;
  bool _showTranslation = false;
  Timer? _translateDebounce;
  SharedPreferences? _prefs; // Cached for performance

  String get _scrollKey => 'scroll_${widget.url}';

  // ─── Reklam URL listesi ───
  static const _adPatterns = [
    'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
    'adservice.google', 'taboola', 'outbrain', 'popads', 'popcash',
    'exoclick', 'adsterra', 'propellerads', 'mgid.com',
    'intent://', 'market://',
  ];

  bool _isAdUrl(String url) {
    final u = url.toLowerCase();
    for (final p in _adPatterns) {
      if (u.contains(p)) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _originalUrl = widget.url;
    _initWebView();
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _translateDebounce?.cancel();
    _win?.dispose();
    super.dispose();
  }

  // ─── Init ───
  Future<void> _initWebView() async {
    _prefs = await SharedPreferences.getInstance();
    if (_isWindows) {
      await _initWindows();
    } else {
      _initMobile();
    }
    _scrollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _saveScroll());
  }

  // ─── Windows WebView ───
  Future<void> _initWindows() async {
    try {
      final c = wv_win.WebviewController();
      await c.initialize();
      await c.setPopupWindowPolicy(wv_win.WebviewPopupWindowPolicy.deny);

      c.url.listen((u) {
        if (!mounted || u.isEmpty || u == _currentUrl) return;
        if (_isAdUrl(u)) {
          _lastBlockedUrl = u;
          return;
        }
        setState(() => _currentUrl = u);
        widget.onUrlChanged?.call(u);
        _updateNavState();
      });

      c.loadingState.listen((s) async {
        if (!mounted) return;
        if (s == wv_win.LoadingState.loading) {
          setState(() => _progress = 0.3);
        } else if (s == wv_win.LoadingState.navigationCompleted) {
          setState(() => _progress = 1.0);
          await _onPageLoaded(winController: c);
          _updateNavState();
        }
      });

      c.webMessage.listen((msg) {
        if (msg is String && msg.trim().isNotEmpty && mounted) {
          _handleTextSelection(msg.trim());
        }
      });

      await c.loadUrl(widget.url);

      if (mounted) {
        setState(() {
          _win = c;
          _winReady = true;
        });
      }
    } catch (e) {
      debugPrint('Windows WebView init error: $e');
    }
  }

  // ─── Mobile WebView ───
  void _initMobile() {
    final c = wv_mobile.WebViewController()
      ..setJavaScriptMode(wv_mobile.JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        wv_mobile.NavigationDelegate(
          onPageStarted: (u) {
            if (!mounted) return;
            setState(() => _progress = 0.1);
            if (u.isNotEmpty && u != _currentUrl && !_isAdUrl(u)) {
              setState(() => _currentUrl = u);
              widget.onUrlChanged?.call(u);
            } else if (_isAdUrl(u)) {
              _lastBlockedUrl = u;
            }
            _updateNavState();
          },
          onProgress: (p) {
            if (mounted) setState(() => _progress = p / 100);
          },
          onPageFinished: (_) async {
            if (!mounted) return;
            setState(() => _progress = 1.0);
            await _onPageLoaded();
            _updateNavState();
          },
          onNavigationRequest: (req) {
            if (_isAdUrl(req.url)) {
              _lastBlockedUrl = req.url;
              return wv_mobile.NavigationDecision.prevent;
            }
            return wv_mobile.NavigationDecision.navigate;
          },
          onWebResourceError: (err) {
            debugPrint('WebView error: ${err.description}');
          },
        ),
      )
      ..addJavaScriptChannel(
        'TranslationChannel',
        onMessageReceived: (msg) {
          if (msg.message.trim().isNotEmpty && mounted) {
            _handleTextSelection(msg.message.trim());
          }
        },
      )
      ..loadRequest(Uri.parse(widget.url));

    setState(() => _mobile = c);
  }

  // ─── Sayfa yüklenince çalışır ───
  Future<void> _onPageLoaded({wv_win.WebviewController? winController}) async {
    final controller = winController ?? _win;

    // Scroll geri yükle
    await _restoreScroll(controller: controller);

    // Reklam engelleme CSS
    await _applyAdBlockCss(controller: controller);

    // JS enjekte et (popup engelle + çeviri)
    const js = r"""
      (() => {
        // Popup engelle
        window.open = () => null;
        window.alert = () => {};
        window.confirm = () => false;
        window.prompt = () => null;

        // Çeviri: metin seçince gönder
        let _lastSel = '';
        const sendSel = () => {
          const sel = window.getSelection().toString().trim();
          if (sel && sel !== _lastSel && sel.length < 500) {
            _lastSel = sel;
            if (window.TranslationChannel) {
              window.TranslationChannel.postMessage(sel);
            } else if (window.chrome && window.chrome.webview) {
              window.chrome.webview.postMessage(sel);
            }
          }
        };
        document.addEventListener('mouseup', () => setTimeout(sendSel, 150));
        document.addEventListener('touchend', () => setTimeout(sendSel, 150));
      })();
    """;

    try {
      if (_isWindows) {
        await (controller ?? _win)?.executeScript(js);
      } else {
        await _mobile?.runJavaScript(js);
      }
    } catch (e) {
      debugPrint('JS inject error: $e');
    }
  }

  // ─── Reklam engelleme CSS ───
  Future<void> _applyAdBlockCss({wv_win.WebviewController? controller}) async {
    final sp = _prefs ?? await SharedPreferences.getInstance();
    final adOn = sp.getBool('ad_block_css') ?? false;
    if (!adOn) return;

    const css = '.ads,.ad,.advertisement,.banner,ins.adsbygoogle,'
        'iframe[src*="doubleclick"],.popup,.popunder,'
        '.cookie-notice,.cookie-banner,.push-notification'
        '{display:none!important}';

    final js = '''
      (() => {
        const s = document.getElementById('_rbm_ad')||document.createElement('style');
        s.id='_rbm_ad';
        s.textContent='$css';
        document.head && document.head.appendChild(s);
      })();
    ''';

    try {
      if (_isWindows) {
        await (controller ?? _win)?.executeScript(js);
      } else {
        await _mobile?.runJavaScript(js);
      }
    } catch (_) {}
  }

  // ─── Scroll kaydet / geri yükle ───
  Future<void> _restoreScroll({wv_win.WebviewController? controller}) async {
    final sp = _prefs ?? await SharedPreferences.getInstance();
    final y = sp.getDouble(_scrollKey) ?? 0.0;
    if (y <= 0) return;

    await Future.delayed(const Duration(milliseconds: 600));
    final js = 'window.scrollTo(0, ${y.toStringAsFixed(0)});';
    try {
      if (_isWindows) {
        await (controller ?? _win)?.executeScript(js);
      } else {
        await _mobile?.runJavaScript(js);
      }
    } catch (_) {}
  }

  Future<void> _saveScroll() async {
    try {
      const js = '(document.scrollingElement||document.documentElement||document.body).scrollTop';
      double y = 0;
      if (_isWindows) {
        final r = await _win?.executeScript(js);
        if (r is String) y = double.tryParse(r) ?? 0;
        if (r is num) y = r.toDouble();
      } else {
        final r = await _mobile?.runJavaScriptReturningResult(js);
        if (r is num) y = r.toDouble();
        if (r is String) y = double.tryParse(r) ?? 0;
      }
      if (y > 0) {
        final sp = _prefs ?? await SharedPreferences.getInstance();
        await sp.setDouble(_scrollKey, y);
        widget.onScrollChanged?.call(y);
      }
    } catch (_) {}
  }

  // ─── Nav state ───
  Future<void> _updateNavState() async {
    if (!mounted) return;
    try {
      if (_isWindows) {
        final r = await _win?.executeScript('history.length');
        final len = r is String ? (int.tryParse(r) ?? 0) : 0;
        if (mounted) setState(() { _canGoBack = len > 1; _canGoForward = false; });
      } else {
        final back = await _mobile?.canGoBack() ?? false;
        final fwd = await _mobile?.canGoForward() ?? false;
        if (mounted) setState(() { _canGoBack = back; _canGoForward = fwd; });
      }
    } catch (_) {}
  }

  // ─── Çeviri ───
  void _handleTextSelection(String text) {
    if (text == _selectedText) return;
    setState(() {
      _selectedText = text;
      _showTranslation = true;
      _isTranslating = true;
      _translatedText = '';
    });
    _translateDebounce?.cancel();
    _translateDebounce = Timer(const Duration(milliseconds: 500), () => _translate(text));
  }

  Future<void> _translate(String text) async {
    try {
      final uri = Uri.parse(
        'https://translate.googleapis.com/translate_a/single'
        '?client=gtx&sl=auto&tl=tr&dt=t&q=${Uri.encodeComponent(text)}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && mounted) {
        final data = json.decode(res.body);
        if (data is List && data[0] is List) {
          final buf = StringBuffer();
          for (final item in data[0] as List) {
            if (item is List && item.isNotEmpty && item[0] is String) buf.write(item[0]);
          }
          setState(() { _translatedText = buf.toString(); _isTranslating = false; });
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() { _translatedText = '—'; _isTranslating = false; });
  }

  // ─── Build ───
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          // Yükleme çubuğu
          if (_progress > 0 && _progress < 1)
            LinearProgressIndicator(value: _progress, minHeight: 3),

          // Çeviri barı
          if (_showTranslation && _selectedText.isNotEmpty)
            _buildTranslationBar(context),

          // WebView
          Expanded(child: _buildWebView()),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(context),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      title: Text(
        widget.title,
        overflow: TextOverflow.ellipsis,
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        if (_currentUrl != _originalUrl)
          IconButton(
            tooltip: context.tr('recover_url'),
            icon: const Icon(Icons.restore, color: Colors.orange),
            onPressed: _recoverUrl,
          ),
        if (_lastBlockedUrl.isNotEmpty)
          IconButton(
            tooltip: context.tr('blocked'),
            icon: const Icon(Icons.block, color: Colors.redAccent, size: 20),
            onPressed: () => _showBlockedDialog(context),
          ),
      ],
    );
  }

  Widget _buildTranslationBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade800, Colors.indigo.shade700],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _isTranslating
                ? Row(children: [
                    const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _selectedText,
                        style: const TextStyle(color: Colors.white60, fontSize: 14),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _translatedText,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _selectedText,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
          ),
          if (!_isTranslating) ...[
            IconButton(
              icon: const Icon(Icons.copy, size: 18, color: Colors.white),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _translatedText));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('copied')), duration: const Duration(seconds: 1)),
                );
              },
            ),
            const SizedBox(width: 4),
          ],
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.white),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => setState(() { _showTranslation = false; _selectedText = ''; }),
          ),
        ],
      ),
    );
  }

  Widget _buildWebView() {
    if (_isWindows) {
      if (!_winReady || _win == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return wv_win.Webview(
        _win!,
        permissionRequested: (_, __, ___) async => wv_win.WebviewPermissionDecision.allow,
      );
    } else {
      if (_mobile == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return wv_mobile.WebViewWidget(controller: _mobile!);
    }
  }

  Widget _buildBottomBar(BuildContext context) {
    return BottomAppBar(
      height: 56,
      child: Row(
        children: [
          IconButton(
            tooltip: context.tr('web_back'),
            icon: const Icon(Icons.arrow_back),
            onPressed: _canGoBack ? _goBack : null,
          ),
          IconButton(
            tooltip: context.tr('web_forward'),
            icon: const Icon(Icons.arrow_forward),
            onPressed: _canGoForward ? _goForward : null,
          ),
          const Spacer(),
          IconButton(
            tooltip: context.tr('refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
          IconButton(
            tooltip: context.tr('open_browser'),
            icon: const Icon(Icons.open_in_new),
            onPressed: () => openInExternalBrowser(_currentUrl),
          ),
        ],
      ),
    );
  }

  // ─── Aksiyonlar ───
  Future<void> _goBack() async {
    try {
      if (_isWindows) await _win?.goBack();
      else await _mobile?.goBack();
    } catch (_) {}
    _updateNavState();
  }

  Future<void> _goForward() async {
    try {
      if (_isWindows) await _win?.goForward();
      else await _mobile?.goForward();
    } catch (_) {}
    _updateNavState();
  }

  Future<void> _reload() async {
    try {
      if (_isWindows) await _win?.reload();
      else await _mobile?.reload();
    } catch (_) {}
  }

  void _recoverUrl() {
    setState(() => _currentUrl = _originalUrl);
    if (_isWindows) _win?.loadUrl(_originalUrl);
    else _mobile?.loadRequest(Uri.parse(_originalUrl));
    widget.onUrlChanged?.call(_originalUrl);
  }

  void _showBlockedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('blocked_url')),
        content: SelectableText(_lastBlockedUrl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('ok'))),
        ],
      ),
    );
  }
}
