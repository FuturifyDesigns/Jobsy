@echo off
echo ========================================
echo Running Jobsy in Debug Mode
echo ========================================
echo.

set SUPABASE_URL_ENC=IhsWAwobb2UFFAYVRywvAwcKG0IvJgUBHglWMWQcFwMYQyE5CkwQFg
set SUPABASE_KEY_ENC=LxYoGxtmIyMgCzkwdDoDXiwaMFIJJD1XEDpodgMEEisvYgpzQQcKM1EjeSILPBBrOi43IBsgTAYwNTE6CmguAAM4GjAXCScfUBcuWS0oKDQAI3ksIzZQSgpALQQbATsdWQkjGAsQFBgzEDwrRTBMBj8NUEcQbQMAHzsrKEgPICpRPRNGcwQrI0c2ZSc5Jg8lTUIDA1kvGTgVDg4iGj0TRnQFJ1JdTGwiBzk3HwpDCCFcC14AFiQjNgwdKhVwPzwzQRhiciMOLDYSRQYYNls3Gg

C:\Users\Leonm\Downloads\flutter\bin\flutter run ^
  --dart-define=SUPABASE_URL=%SUPABASE_URL_ENC% ^
  --dart-define=SUPABASE_ANON_KEY=%SUPABASE_KEY_ENC%
