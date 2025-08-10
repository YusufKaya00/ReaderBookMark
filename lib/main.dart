import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:provider/provider.dart';
import 'providers/settings_provider.dart';
import 'providers/library_provider.dart';
import 'ui/screens/home_screen.dart';
import 'background/new_chapter_check.dart';
import 'update/update_service.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _ensureNotificationPermission();
  initBackground();
  // İsteğe bağlı: açılışta güncelleme kontrolü (Android)
  UpdateService.isUpdateAvailable().then((available) async {
    if (available) {
      // Basit tetikleyici: OTA başlat (gerçekte UI diyalogu göstermeyi tercih edebilirsiniz)
      await UpdateService.startUpdate();
    }
  });
  runApp(const AppRoot());
  Workmanager().initialize(_backgroundHeadless, isInDebugMode: false);
}

Future<void> _ensureNotificationPermission() async {
  if (!Platform.isAndroid) return;
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidInit));

  // Android 13+ için runtime bildirim izni
  final status = await Permission.notification.status;
  if (status.isDenied || status.isRestricted || status.isPermanentlyDenied) {
    await Permission.notification.request();
  }
}

@pragma('vm:entry-point')
void _backgroundHeadless() {
  Workmanager().executeTask((task, input) async {
    await runCheckNow();
    return Future.value(true);
  });
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


