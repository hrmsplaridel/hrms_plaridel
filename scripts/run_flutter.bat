@echo off
REM HRMS Plaridel - Run Flutter app with API URL from single config file.
REM Edit config\api_base_url.txt to switch between localhost and LAN (e.g. http://192.168.1.100:3000)

set CONFIG=%~dp0..\config\api_base_url.txt
if not exist "%CONFIG%" (
  echo Error: config\api_base_url.txt not found. Create it with one line: http://localhost:3000
  exit /b 1
)

set /p API_BASE_URL=<"%CONFIG%"
set API_BASE_URL=%API_BASE_URL: =%
if "%API_BASE_URL%"=="" (
  echo Error: config\api_base_url.txt is empty. Add: http://localhost:3000
  exit /b 1
)

echo Using API: %API_BASE_URL%
cd /d "%~dp0.."
flutter run --dart-define=API_BASE_URL=%API_BASE_URL% %*
