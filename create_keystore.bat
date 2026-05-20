@echo off
echo Android Keystore olusturuluyor...
echo.
echo Lutfen asagidaki bilgileri girin:
echo - Keystore sifresi (en az 6 karakter)
echo - Alias adi (ornek: readerbookmark)
echo - Alias sifresi
echo - Ad Soyad
echo - Organizasyon
echo - Sehir
echo - Ulke kodu (TR)
echo.

keytool -genkey -v -keystore readerbookmark-release-key.keystore -alias readerbookmark -keyalg RSA -keysize 2048 -validity 10000

echo.
echo Keystore basariyla olusturuldu: readerbookmark-release-key.keystore
echo Bu dosyayi guvenli bir yerde saklayin!
pause

