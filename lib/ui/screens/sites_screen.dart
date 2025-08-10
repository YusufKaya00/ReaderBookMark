import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../background/new_chapter_check.dart';

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
    // Sabit hostlardan sadece manuel liste (tracked_urls) yönetilebilir olsun
    // Sabitleri otomatik gösterelim, ancak kaldırılmasın
    final fixed = getAllowedHosts().map((h) => 'https://$h').toList();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Siteleri Yönet'),
        actions: [
          IconButton(
            tooltip: 'Temizle',
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
                    decoration: const InputDecoration(
                      hintText: 'Site URL ekle (https://...)',
                      border: OutlineInputBorder(),
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
                    // Sadece host başlangıçlarını kabul et (scheme + host)
                    Uri? uri;
                    try { uri = Uri.parse(u); } catch (_) {}
                    if (uri == null || uri.host.isEmpty) return;
                    final normalized = '${uri.scheme.isEmpty ? 'https' : uri.scheme}://${uri.host}';
                    if (!_urls.contains(normalized)) {
                      setState(() => _urls.add(u));
                      await _save();
                    }
                    _controller.clear();
                  },
                  child: const Text('Ekle'),
                )
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text('Sabit Siteler (değiştirilemez)', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ...getAllowedHosts().map((h) => ListTile(
                      leading: const Icon(Icons.lock),
                      title: Text('https://$h', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: const Text('Bildirim için sabit'),
                    )),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text('Manuel Eklenenler', style: TextStyle(fontWeight: FontWeight.bold)),
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


