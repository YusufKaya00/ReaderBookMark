@echo off
echo ====================================
echo   Flutter APK Build Baslatiliyor
echo ====================================
echo.

echo 1. Flutter clean...
flutter clean

echo.
echo 2. Dependencies yukleniyor...
flutter pub get

echo.
echo 3. Release APK olusturuluyor...
flutter build apk --release

echo.
echo ====================================
echo   APK Build Tamamlandi!
echo ====================================
echo.
echo APK dosyasi konumu:
echo build\app\outputs\flutter-apk\app-release.apk
echo.
echo Test icin bu APK'yi kullanabilirsiniz.
echo Play Store icin AAB formatini tercih edin.
echo.
pause

