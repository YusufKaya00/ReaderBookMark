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
  double _progress = 0;
  Timer? _timer;
  late String _currentUrl;
  late String _originalUrl; // Store original URL for recovery
  bool _canGoBack = false;
  bool _canGoForward = false;
  
  // URL change tracking for ad blocking
  DateTime _lastUrlChange = DateTime.now();
  int _rapidUrlChangeCount = 0;
  String _lastBlockedUrl = '';

  // Translation State - Simple single-line version
  String _selectedText = '';
  String _translatedText = '';
  bool _isTranslating = false;
  bool _showTranslation = false;
  Timer? _translateDebounce;

  String get _scrollKey => 'scroll_$_currentUrl';

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _originalUrl = widget.url; // Store original URL
    _init();
  }

  Future<void> _init() async {
    final blockJs = """
      (() => {
        const blockPopups = () => {
          window.open = function() { return null; };
          window.alert = function() {};
          window.confirm = function() { return false; };
          window.prompt = function() { return null; };
        };
        blockPopups();
        document.addEventListener('DOMContentLoaded', blockPopups);

        // Text selection listener for translation
        document.addEventListener('selectionchange', () => {
          const selection = window.getSelection().toString().trim();
          if (selection.length > 0 && selection.length < 500) {
            if (window.TranslationChannel) {
              window.TranslationChannel.postMessage(selection);
            } else if (window.chrome && window.chrome.webview) {
              window.chrome.webview.postMessage(selection);
            }
          }
        });
      })();
    """;

    if (_isWindows) {
      final c = wv_win.WebviewController();
      await c.initialize();
      await c.setBackgroundColor(Colors.transparent);
      await c.setPopupWindowPolicy(wv_win.WebviewPopupWindowPolicy.deny);
      
      c.url.listen((u) {
        if (u.isNotEmpty && u != _currentUrl) {
          // Check for rapid URL changes (ad redirects)
          final now = DateTime.now();
          final timeSinceLastChange = now.difference(_lastUrlChange).inMilliseconds;
          
          if (timeSinceLastChange < 500) {
            _rapidUrlChangeCount++;
            if (_rapidUrlChangeCount > 2 || _isAdUrl(u)) {
              // Block rapid changes or ad URLs
              _lastBlockedUrl = u;
              if (_currentUrl.isNotEmpty) {
                c.loadUrl(_currentUrl); // Stay on current page
              }
              return;
            }
          } else {
            _rapidUrlChangeCount = 0;
          }
          
          _lastUrlChange = now;
          
          if (!_isAdUrl(u)) {
            setState(() => _currentUrl = u);
            widget.onUrlChanged?.call(u);
            _updateNavState();
          } else {
            // Block ad URL
            _lastBlockedUrl = u;
            if (_currentUrl.isNotEmpty) {
              c.loadUrl(_currentUrl);
            }
          }
        }
      });

      c.loadingState.listen((s) async {
        if (s == wv_win.LoadingState.navigationCompleted) {
          await _restoreScroll();
          await _applyDarkAndBlockers();
          await c.executeScript(blockJs);
          setState(() => _progress = 1);
          _updateNavState();
        }
      });

      c.webMessage.listen((message) {
        if (message is String && message.trim().isNotEmpty) {
          _handleTextSelection(message.trim());
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
                // Check for rapid URL changes (ad redirects)
                final now = DateTime.now();
                final timeSinceLastChange = now.difference(_lastUrlChange).inMilliseconds;
                
                if (timeSinceLastChange < 500) {
                  _rapidUrlChangeCount++;
                } else {
                  _rapidUrlChangeCount = 0;
                }
                
                _lastUrlChange = now;
                
                if (!_isAdUrl(u) && _rapidUrlChangeCount <= 2) {
                  setState(() => _currentUrl = u);
                  widget.onUrlChanged?.call(u);
                } else {
                  _lastBlockedUrl = u;
                }
              }
              _updateNavState();
            },
            onProgress: (p) => setState(() => _progress = p / 100),
            onPageFinished: (_) async {
              await _restoreScroll();
              await _applyDarkAndBlockers();
              await _mobile?.runJavaScript(blockJs);
              _updateNavState();
            },
            onNavigationRequest: (req) {
              final u = req.url;
              
              // Check for rapid navigation (ad redirects)
              final now = DateTime.now();
              final timeSinceLastChange = now.difference(_lastUrlChange).inMilliseconds;
              
              if (timeSinceLastChange < 500) {
                _rapidUrlChangeCount++;
                if (_rapidUrlChangeCount > 2) {
                  _lastBlockedUrl = u;
                  return wv_mobile.NavigationDecision.prevent;
                }
              }
              
              if (_isAdUrl(u)) {
                _lastBlockedUrl = u;
                return wv_mobile.NavigationDecision.prevent;
              }
              return wv_mobile.NavigationDecision.navigate;
            },
          ),
        )
        ..addJavaScriptChannel(
          'TranslationChannel',
          onMessageReceived: (msg) {
            if (msg.message.trim().isNotEmpty) {
              _handleTextSelection(msg.message.trim());
            }
          },
        )
        ..loadRequest(Uri.parse(widget.url));
      _mobile = c;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _saveScroll());
  }

  bool _isAdUrl(String url) {
    final u = url.toLowerCase();
    
    // Comprehensive ad blocking patterns
    const adPatterns = [
      // Ad networks
      'doubleclick.net',
      'googlesyndication.com',
      'googleadservices.com',
      'adservice.google',
      'google-analytics.com',
      'googletagmanager.com',
      'googletagservices.com',
      
      // Popular ad networks
      'taboola',
      'outbrain',
      'zedo',
      'propeller',
      'popcash',
      'popads',
      'popad',
      'popunder',
      'onclick',
      'onclickads',
      'exoclick',
      'exdynsrv',
      'juicyads',
      'adsterra',
      'adpushup',
      'adroll',
      'adtrack',
      'adcolony',
      'adnxs',
      'adform',
      'adnxs.com',
      
      // Tracking & Analytics
      'facebook.com/tr',
      'analytics',
      'statcounter',
      'histats',
      'amung.us',
      'addthis',
      'sharethis',
      
      // Crypto miners
      'coinhive',
      'coinad',
      'crypto-loot',
      'jsecoin',
      
      // Betting/Casino
      'bet365',
      '1xbet',
      'mostbet',
      'pin-up',
      'casino',
      'betting',
      
      // Mobile redirects
      'intent://',
      'market://',
      'play.google.com/store',
      'whatsapp://',
      'tg://',
      'telegram://',
      '.apk',
      
      // Programmatic ads
      'mgid.com',
      'criteo.com',
      'pubmatic',
      'casalemedia',
      'rubiconproject',
      'openx.net',
      'smartadserver',
      'bidswitch',
      'yieldlab',
      'indexww',
      'amazon-adsystem',
      'applovin',
      'unity3d.com/ads',
      'mobfox',
      'inmobi',
      'clickbank',
      'daum.net',
      
      // Yandex ads
      'yandex.ru/ads',
      'an.yandex.ru',
      
      // Push notifications
      'utm_source=push',
      'push-notification',
      'onesignal',
      'pushwoosh',
      
      // Suspicious patterns
      '/ad/',
      '/ads/',
      '/adv/',
      '/banner/',
      '/popup',
      '/popunder',
      'redirect',
      'click.php',
      'track.php',
      'ad.php',
      'banner.php',
      
      // Cookie consent (annoying)
      'cookiebot',
      'cookielaw',
      'cookie-consent',
      
      // Video ads
      'videoadex',
      'video-ad',
      'preroll',
      'midroll',
    ];
    
    for (final p in adPatterns) {
      if (u.contains(p)) return true;
    }
    
    // Block URLs with suspicious query parameters
    if (u.contains('utm_') || 
        u.contains('click=') || 
        u.contains('redirect=') ||
        u.contains('aff=') ||
        u.contains('affiliate')) {
      return true;
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
          _canGoForward = false;
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

  Future<void> _applyDarkAndBlockers() async {
    final sp = await SharedPreferences.getInstance();
    final adOn = sp.getBool('ad_block_css') ?? true; // Default to true
    final cssBuffer = StringBuffer();
    
    // Dark mode styles
    cssBuffer.writeln('html,body{background:#000!important;color:#fff!important}');
    cssBuffer.writeln('img,video{filter:brightness(.85) contrast(1.05)}');
    cssBuffer.writeln('a{color:#8ab4f8!important}');
    
    if (adOn) {
      // Aggressive ad blocking CSS
      cssBuffer.writeln('''
        /* Ad containers */
        [id*="ad"], [class*="ad"], [id*="Ad"], [class*="Ad"],
        .ads, .ad, .advert, .advertisement, .banner, .sponsor, .sponsored,
        #ad, #ads, #advert, #advertisement,
        
        /* Iframes */
        iframe[src*="ad"], iframe[src*="doubleclick"], iframe[src*="googlesyndication"],
        iframe[src*="taboola"], iframe[src*="outbrain"], iframe[id*="google_ads"],
        
        /* Specific ad elements */
        div[id^="google_ads"], div[id*="taboola"], div[id*="outbrain"],
        div[class*="adsbygoogle"], ins.adsbygoogle,
        
        /* Popups & overlays */
        .popup, .popunder, .overlay, .modal[class*="ad"],
        #popunder, #popads, .popads, .pop-ad,
        
        /* Cookie & GDPR notices */
        .cookie, .gdpr, .cookie-notice, .cookie-banner, .cookie-consent,
        #cookie-notice, #gdpr-notice,
        
        /* Notifications */
        .notification, .push-notification, .subscribe-popup,
        [class*="notification"][class*="popup"],
        
        /* Social widgets */
        .social-share-popup, .share-overlay,
        
        /* Video ads */
        .video-ad, .preroll, .midroll, [class*="video-ad"],
        
        /* Tracking pixels */
        img[width="1"][height="1"], img[style*="display:none"],
        
        /* Sticky elements (often ads) */
        [style*="position:fixed"][style*="bottom"], 
        [style*="position:sticky"][class*="ad"],
        
        /* Common ad class patterns */
        [class*="adsense"], [class*="adslot"], [class*="ad-slot"],
        [class*="ad-container"], [class*="ad-wrapper"], [class*="ad-banner"],
        [class*="ad-box"], [class*="ad-unit"], [class*="ad-space"],
        
        /* Manga site specific */
        .code-block, [class*="download-app"], [class*="app-banner"]
        
        {display:none!important; visibility:hidden!important; opacity:0!important; height:0!important; width:0!important; position:absolute!important; left:-9999px!important;}
      ''');
    }
    
    final css = cssBuffer.toString().replaceAll("'", "\\'").replaceAll('\n', ' ');
    final js = """
      (() => {
        const style = document.getElementById('reader-dark-style')||document.createElement('style');
        style.id='reader-dark-style';
        style.innerHTML='$css';
        document.head.appendChild(style);
        
        // Remove ad elements dynamically
        const removeAds = () => {
          document.querySelectorAll('[id*="ad"], [class*="ad"], iframe[src*="ad"]').forEach(el => {
            if (el.offsetHeight > 50 || el.offsetWidth > 50) {
              el.remove();
            }
          });
        };
        removeAds();
        setInterval(removeAds, 2000);
      })();
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
    await apply();
    for (final delay in [300, 700, 1200, 2000]) {
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
      widget.onScrollChanged?.call(y);
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _translateDebounce?.cancel();
    super.dispose();
  }

  void _handleTextSelection(String text) {
    if (text == _selectedText) return;
    
    setState(() {
      _selectedText = text;
      _showTranslation = true;
      _isTranslating = true;
      _translatedText = '';
    });

    _translateDebounce?.cancel();
    _translateDebounce = Timer(const Duration(milliseconds: 500), () {
      _performTranslation(text);
    });
  }

  Future<void> _performTranslation(String text) async {
    try {
      final url = 'https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=tr&dt=t&q=${Uri.encodeComponent(text)}';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        if (data is List && data.isNotEmpty && data[0] is List) {
          final buffer = StringBuffer();
          for (final item in data[0]) {
            if (item is List && item.isNotEmpty && item[0] is String) {
              buffer.write(item[0]);
            }
          }
          setState(() {
            _translatedText = buffer.toString();
            _isTranslating = false;
          });
          return;
        }
      }
    } catch (_) {}
    
    if (mounted) {
      setState(() {
        _translatedText = context.tr('error');
        _isTranslating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // URL Recovery button
          if (_currentUrl != _originalUrl)
            IconButton(
              tooltip: context.tr('recover_url'),
              icon: const Icon(Icons.restore, color: Colors.orange),
              onPressed: () {
                setState(() => _currentUrl = _originalUrl);
                if (_isWindows) {
                  _win?.loadUrl(_originalUrl);
                } else {
                  _mobile?.loadRequest(Uri.parse(_originalUrl));
                }
                widget.onUrlChanged?.call(_originalUrl);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('url_recovered'))),
                );
              },
            ),
          // Show blocked URL count
          if (_lastBlockedUrl.isNotEmpty)
            IconButton(
              tooltip: '${context.tr('blocked')}: $_lastBlockedUrl',
              icon: const Icon(Icons.block, color: Colors.red, size: 20),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(context.tr('blocked_url')),
                    content: SelectableText(_lastBlockedUrl),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(context.tr('ok')),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 1) LinearProgressIndicator(value: _progress, minHeight: 2),
          
          // Simple single-line translation bar
          if (_showTranslation && _selectedText.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.blue.shade700,
              child: Row(
                children: [
                  Expanded(
                    child: _isTranslating
                        ? Row(
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedText,
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _translatedText,
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _selectedText,
                                style: const TextStyle(color: Colors.white60, fontSize: 10),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                  ),
                  if (!_isTranslating)
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16, color: Colors.white),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _translatedText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(context.tr('copied')),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.white),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() => _showTranslation = false),
                  ),
                ],
              ),
            ),
          
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
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        height: 64,
        child: Row(
          children: [
            const SizedBox(width: 8),
            IconButton(
              tooltip: context.tr('web_back'),
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
              tooltip: context.tr('web_forward'),
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
              tooltip: context.tr('refresh'),
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
              tooltip: context.tr('open_browser'),
              onPressed: () async {
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
