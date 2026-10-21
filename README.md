# Viral Clips AI – Android APK client

This is the Android Flutter client for the Viral Clips AI FastAPI + FFmpeg backend.

## GitHub Actions APK
Open **Actions → Android APK → latest successful run → Artifacts → ViralClipsAI-Android-APK** to download `app-release.apk`.

GitHub workflow generates the Android scaffold, analyzes code, runs widget tests, builds a release APK and uploads the unsigned-for-store (debug-key-signed) release artifact.

## Requirements
- Personal backend running over HTTPS with the `APP_API_KEY`
- YouTube API key for adding source channels
- TikTok developer app with Login Kit + Content Posting API permissions for real account connecting and posting
- Media you own or have redistribution permission to use

Source channels use the YouTube API for metadata; YouTube Premium does not grant reuse rights or enable downloading via this app.

## Version
Flutter Android client 0.3.1; requires the separately deployed Viral Clips AI backend 0.3.x. No claim of completed live TikTok OAuth or real TikTok publish testing.

© mortadaa.
