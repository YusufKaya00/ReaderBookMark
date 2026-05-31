import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import '../../utils/translations.dart';

class AddLinkDialog extends StatefulWidget {
  final void Function({required String title, required String url, required String category, String? cover}) onSubmit;
  const AddLinkDialog({super.key, required this.onSubmit});

  @override
  State<AddLinkDialog> createState() => _AddLinkDialogState();
}

class _AddLinkDialogState extends State<AddLinkDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _urlController = TextEditingController();
  final _coverController = TextEditingController();
  String _category = 'Genel';
  String? _clipboardUrl;
  bool _isFetchingTitle = false;

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    _coverController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _readClipboard();
    _urlController.addListener(_onUrlChanged);
  }

  void _onUrlChanged() {
    final url = _urlController.text.trim();
    if (url.isNotEmpty && Uri.tryParse(url)?.hasScheme == true) {
      _fetchTitle(url);
    }
  }

  Future<void> _fetchTitle(String url) async {
    if (_isFetchingTitle) return;
    
    setState(() => _isFetchingTitle = true);
    
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        
        // Try multiple selectors for manga sites
        String? title;
        
        // AsuraScans and similar manga sites
        title ??= document.querySelector('h1.entry-title')?.text.trim();
        title ??= document.querySelector('h1.text-center')?.text.trim();
        title ??= document.querySelector('.post-title h1')?.text.trim();
        title ??= document.querySelector('.series-title')?.text.trim();
        title ??= document.querySelector('.manga-title')?.text.trim();
        
        // Generic title tags
        title ??= document.querySelector('meta[property="og:title"]')?.attributes['content']?.trim();
        title ??= document.querySelector('meta[name="twitter:title"]')?.attributes['content']?.trim();
        title ??= document.querySelector('title')?.text.trim();
        
        if (title != null && title.isNotEmpty && mounted) {
          // Clean up title
          title = title.replaceAll(RegExp(r'\s+'), ' ');
          title = title.replaceAll(RegExp(r'\s*[-|]\s*AsuraScans.*$', caseSensitive: false), '');
          title = title.replaceAll(RegExp(r'\s*[-|]\s*Read.*$', caseSensitive: false), '');
          
          if (_titleController.text.trim().isEmpty) {
            _titleController.text = title;
          }
        }
        
        // Try to get cover image
        String? cover;
        cover ??= document.querySelector('meta[property="og:image"]')?.attributes['content'];
        cover ??= document.querySelector('meta[name="twitter:image"]')?.attributes['content'];
        cover ??= document.querySelector('.series-thumb img')?.attributes['src'];
        cover ??= document.querySelector('.manga-cover img')?.attributes['src'];
        
        if (cover != null && cover.isNotEmpty && mounted) {
          if (_coverController.text.trim().isEmpty) {
            _coverController.text = cover;
          }
        }
      }
    } catch (e) {
      // Silently fail
    } finally {
      if (mounted) {
        setState(() => _isFetchingTitle = false);
      }
    }
  }

  Future<void> _readClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final t = data?.text?.trim();
      if (t != null && t.isNotEmpty) {
        final uri = Uri.tryParse(t);
        if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
          setState(() {
            _clipboardUrl = t;
            if (_urlController.text.trim().isEmpty) {
              _urlController.text = t;
            }
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('add')),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: context.tr('languageCode') == 'tr' ? 'Başlık' : 'Title',
                  suffixIcon: _isFetchingTitle 
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? (context.tr('languageCode') == 'tr' ? 'Başlık gerekli' : 'Title is required')
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: 'URL',
                  suffixIcon: (_clipboardUrl != null)
                      ? IconButton(
                          tooltip: context.tr('languageCode') == 'tr' ? 'Panodaki linki yapıştır' : 'Paste from clipboard',
                          icon: const Icon(Icons.paste),
                          onPressed: () {
                            setState(() {
                              _urlController.text = _clipboardUrl!;
                            });
                          },
                        )
                      : null,
                ),
                keyboardType: TextInputType.url,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return context.tr('languageCode') == 'tr' ? 'URL gerekli' : 'URL is required';
                  }
                  final ok = Uri.tryParse(v)?.hasAbsolutePath ?? false;
                  return ok ? null : (context.tr('languageCode') == 'tr' ? 'Geçerli bir URL girin' : 'Enter a valid URL');
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _category,
                items: [
                  DropdownMenuItem(value: 'Genel', child: Text(context.tr('general'))),
                  DropdownMenuItem(value: 'Manga', child: Text(context.tr('manga'))),
                  DropdownMenuItem(value: 'Kitap', child: Text(context.tr('book'))),
                  DropdownMenuItem(value: 'Makale', child: Text(context.tr('article'))),
                  DropdownMenuItem(value: 'İzlenecekler', child: Text(context.tr('watchlist'))),
                ],
                onChanged: (v) => setState(() => _category = v ?? 'Genel'),
                decoration: InputDecoration(
                  labelText: context.tr('languageCode') == 'tr' ? 'Kategori' : 'Category',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _coverController,
                decoration: InputDecoration(
                  labelText: context.tr('languageCode') == 'tr'
                      ? 'Kapak Görseli (isteğe bağlı URL)'
                      : 'Cover Image (optional URL)',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('cancel')),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              widget.onSubmit(
                title: _titleController.text.trim(),
                url: _urlController.text.trim(),
                category: _category,
                cover: _coverController.text.trim().isEmpty ? null : _coverController.text.trim(),
              );
              Navigator.of(context).pop();
            }
          },
          child: Text(context.tr('add')),
        ),
      ],
    );
  }
}


