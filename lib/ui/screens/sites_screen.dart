import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/translations.dart';

const List<String> kAllowedHosts = [
  'hayalistic.com.tr',
  'tortugaceviri.com',
  'ruyamanga.net',
  'asuracomic.net',
  'tempestmangas.com',
  'asurascans.com.tr',
  'uzaymanga.com',
];

class SitesScreen extends StatefulWidget {
  const SitesScreen({super.key});

  @override
  State<SitesScreen> createState() => _SitesScreenState();
}

class _SitesScreenState extends State<SitesScreen> {
  List<String> _urls = [];
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final manual = sp.getStringList('tracked_urls') ?? <String>[];
    setState(() {
      _urls = manual;
    });
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList('tracked_urls', _urls);
  }

  @override
  Widget build(BuildContext context) {
    final isTr = Localizations.localeOf(context).languageCode == 'tr';

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('manage_sites')),
        actions: [
          IconButton(
            tooltip: isTr ? 'Temizle' : 'Clear',
            onPressed: () async {
              setState(() => _urls.clear());
              await _save();
            },
            icon: const Icon(Icons.delete_sweep),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: isTr ? 'Site URL ekle (https://...)' : 'Add Site URL (https://...)',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.url,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final u = _controller.text.trim();
                    if (u.isEmpty) return;
                    Uri? uri;
                    try {
                      uri = Uri.parse(u);
                    } catch (_) {}
                    if (uri == null || uri.host.isEmpty) return;
                    final normalized = '${uri.scheme.isEmpty ? 'https' : uri.scheme}://${uri.host}';
                    if (!_urls.contains(normalized)) {
                      setState(() => _urls.add(u));
                      await _save();
                    }
                    _controller.clear();
                  },
                  child: Text(context.tr('add')),
                )
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    isTr ? 'Sabit Siteler (değiştirilemez)' : 'Fixed Sites (non-removable)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ...kAllowedHosts.map((h) => ListTile(
                      leading: const Icon(Icons.lock),
                      title: Text('https://$h', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(isTr ? 'Bildirim için sabit' : 'Fixed for notifications'),
                    )),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    isTr ? 'Manuel Eklenenler' : 'Manually Added',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ..._urls.asMap().entries.map((e) {
                  final i = e.key;
                  final u = e.value;
                  return ListTile(
                    title: Text(u, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        setState(() => _urls.removeAt(i));
                        await _save();
                      },
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


