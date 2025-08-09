import 'package:flutter/material.dart';

class EditLinkDialog extends StatefulWidget {
  final String initialTitle;
  final String initialUrl;
  final String initialCategory;
  final String? initialCover;
  final void Function({required String title, required String url, required String category, String? cover}) onSubmit;

  const EditLinkDialog({
    super.key,
    required this.initialTitle,
    required this.initialUrl,
    required this.initialCategory,
    required this.initialCover,
    required this.onSubmit,
  });

  @override
  State<EditLinkDialog> createState() => _EditLinkDialogState();
}

class _EditLinkDialogState extends State<EditLinkDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _urlController;
  late final TextEditingController _coverController;
  late String _category;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _urlController = TextEditingController(text: widget.initialUrl);
    _coverController = TextEditingController(text: widget.initialCover ?? '');
    _category = widget.initialCategory;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    _coverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Linki Düzenle'),
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
                decoration: const InputDecoration(labelText: 'URL'),
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
              Navigator.of(context).pop();
            }
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}


