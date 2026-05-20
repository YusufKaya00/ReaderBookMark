@echo off
echo ====================================
echo   Flutter Release Build Baslatiliyor
echo ====================================
echo.

echo 1. Flutter clean...
flutter clean

echo.
echo 2. Dependencies yukleniyor...
flutter pub get

echo.
echo 3. Android App Bundle (AAB) olusturuluyor...
flutter build appbundle --release

echo.
echo ====================================
echo   Build Tamamlandi!
echo ====================================
echo.
echo AAB dosyasi konumu:
echo build\app\outputs\bundle\release\app-release.aab
echo.
echo Bu dosyayi Google Play Console'a yukleyebilirsiniz.
echo.
pause

