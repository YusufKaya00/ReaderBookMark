import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      title: const Text('Yeni Link Ekle'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Başlık'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Başlık gerekli' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: 'URL',
                  suffixIcon: (_clipboardUrl != null)
                      ? IconButton(
                          tooltip: 'Panodaki linki yapıştır',
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
                  if (v == null || v.trim().isEmpty) return 'URL gerekli';
                  final ok = Uri.tryParse(v)?.hasAbsolutePath ?? false;
                  return ok ? null : 'Geçerli bir URL girin';
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _category,
                items: const [
                  DropdownMenuItem(value: 'Genel', child: Text('Genel')),
                  DropdownMenuItem(value: 'Manga', child: Text('Manga')),
                  DropdownMenuItem(value: 'Kitap', child: Text('Kitap')),
                  DropdownMenuItem(value: 'Makale', child: Text('Makale')),
                ],
                onChanged: (v) => setState(() => _category = v ?? 'Genel'),
                decoration: const InputDecoration(labelText: 'Kategori'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _coverController,
                decoration: const InputDecoration(
                  labelText: 'Kapak Görseli (isteğe bağlı URL)'
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
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
              // tracked_urls listesine otomatik eklemek için SharedPreferences'a yaz
              // Bu sayede yeni bölüm kontrolü bu URL'leri de izler
              // Hata olursa sessiz geçilir
              // Otomatik takip ekleme kaldırıldı (istek üzerine).
              Navigator.of(context).pop();
            }
          },
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}


