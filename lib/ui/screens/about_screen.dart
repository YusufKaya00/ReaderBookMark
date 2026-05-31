import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _githubUrl = 'https://github.com/YusufKaya00';

  Future<void> _openGithub() async {
    final uri = Uri.parse(_githubUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Yapımcı')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 48,
                backgroundImage: NetworkImage('https://github.com/YusufKaya00.png'),
              ),
              const SizedBox(height: 16),
              Text('Yusuf Kaya', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('ReaderBookMark', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Text(
                      'v${snapshot.data!.version}+${snapshot.data!.buildNumber}',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                    );
                  }
                  return const SizedBox();
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _openGithub,
                icon: const Icon(Icons.link),
                label: const Text('GitHub Profili'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


