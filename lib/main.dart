import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/settings_provider.dart';
import 'providers/library_provider.dart';
import 'ui/screens/home_screen.dart';
import 'background/new_chapter_check.dart';
import 'update/update_service.dart';
import 'package:background_fetch/background_fetch.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initBackground();
  // İsteğe bağlı: açılışta güncelleme kontrolü (Android)
  UpdateService.isUpdateAvailable().then((available) async {
    if (available) {
      // Basit tetikleyici: OTA başlat (gerçekte UI diyalogu göstermeyi tercih edebilirsiniz)
      await UpdateService.startUpdate();
    }
  });
  runApp(const AppRoot());
  BackgroundFetch.registerHeadlessTask(_backgroundHeadless); // Android headless
}

@pragma('vm:entry-point')
void _backgroundHeadless(HeadlessTask task) async {
  final taskId = task.taskId;
  final timeout = task.timeout;
  if (timeout) {
    BackgroundFetch.finish(taskId);
    return;
  }
  await runCheckNow();
  BackgroundFetch.finish(taskId);
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          final theme = ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: settings.isDarkMode ? Brightness.dark : Brightness.light,
            ),
            useMaterial3: true,
          );
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'WebView Kitaplık',
            theme: theme,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}


