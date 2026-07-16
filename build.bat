@echo off
echo ========================================
echo Building Jobsy APK with Jobsy Icon
echo ========================================
echo.

set SUPABASE_URL_ENC=IhsWAwobb2UFFAYVRywvAwcKG0IvJgUBHglWMWQcFwMYQyE5CkwQFg
set SUPABASE_KEY_ENC=LxYoGxtmIyMgCzkwdDoDXiwaMFIJJD1XEDpodgMEEisvYgpzQQcKM1EjeSILPBBrOi43IBsgTAYwNTE6CmguAAM4GjAXCScfUBcuWS0oKDQAI3ksIzZQSgpALQQbATsdWQkjGAsQFBgzEDwrRTBMBj8NUEcQbQMAHzsrKEgPICpRPRNGcwQrI0c2ZSc5Jg8lTUIDA1kvGTgVDg4iGj0TRnQFJ1JdTGwiBzk3HwpDCCFcC14AFiQjNgwdKhVwPzwzQRhiciMOLDYSRQYYNls3Gg
set GOOGLE_CLIENT_ID_ENC=c1dQR00Xd31YVkRJDDR7CBEAFRF5J1ZbQk4QLS8DUBkfU3UpXBFDD1EiLFZQXRhRMDlBBRwWRiwvGhEWC0IvJBsHHQ0PIyUC
set GOOGLE_DART_DEFINE=--dart-define=GOOGLE_WEB_CLIENT_ID=%GOOGLE_CLIENT_ID_ENC%

echo [1/3] Cleaning previous build...
C:\Users\Leonm\Downloads\flutter\bin\flutter clean
echo.

echo [2/3] Getting dependencies...
C:\Users\Leonm\Downloads\flutter\bin\flutter pub get
echo.

echo [3/3] Building release APK (Google Sign-In enabled)...
C:\Users\Leonm\Downloads\flutter\bin\flutter build apk --release ^
  --dart-define=SUPABASE_URL=%SUPABASE_URL_ENC% ^
  --dart-define=SUPABASE_ANON_KEY=%SUPABASE_KEY_ENC% ^
  %GOOGLE_DART_DEFINE%
echo.

echo ========================================
echo Build Complete!
echo APK Location: build\app\outputs\flutter-apk\app-release.apk
echo ========================================
echo.
echo The app icon is now the Jobsy logo!
echo Install the APK to see it.
echo ========================================
pause
