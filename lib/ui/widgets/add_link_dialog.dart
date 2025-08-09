import 'package:flutter/material.dart';

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
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}


