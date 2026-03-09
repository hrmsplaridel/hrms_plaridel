#!/usr/bin/env bash
# HRMS Plaridel - Run Flutter app with API URL from single config file.
# Edit config/api_base_url.txt to switch between localhost and LAN (e.g. http://192.168.1.100:3000)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../config/api_base_url.txt"

if [[ ! -f "$CONFIG" ]]; then
  echo "Error: config/api_base_url.txt not found. Create it with one line: http://localhost:3000"
  exit 1
fi

API_BASE_URL=$(head -n1 "$CONFIG" | tr -d '\r\n' | xargs)
if [[ -z "$API_BASE_URL" ]]; then
  echo "Error: config/api_base_url.txt is empty. Add: http://localhost:3000"
  exit 1
fi

echo "Using API: $API_BASE_URL"
cd "$SCRIPT_DIR/.."
flutter run --dart-define=API_BASE_URL="$API_BASE_URL" "$@"
