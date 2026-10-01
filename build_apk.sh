#!/usr/bin/env bash
# Release APK with the Supabase config baked in. Plain `flutter build apk`
# omits it and the app freezes on first launch.
set -euo pipefail
cd "$(dirname "$0")"
[ -f env.json ] || { echo "env.json missing (see env.example.json)"; exit 1; }
flutter build apk --release --dart-define-from-file=env.json "$@"
