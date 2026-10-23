#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK required: install Flutter or run GitHub Actions." >&2
  exit 1
fi
# Flutter create fills missing Android platform scaffolding and leaves source Dart intact.
flutter create --project-name murtada_star --org com.murtada.star --platforms=android .
python3 patch_android.py
flutter pub get
dart run flutter_launcher_icons
if [[ "${1:-}" != "--prepare-only" ]]; then
  flutter analyze --no-fatal-infos --no-fatal-warnings
  flutter test
  flutter build apk --release
  echo "APK: build/app/outputs/flutter-apk/app-release.apk"
fi
