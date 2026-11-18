# CinemaHub - APK Build & Deployment Guide

## 🚀 Quick Start: Build Your First APK for Beta Testing

### Prerequisites
- Flutter SDK installed
- Android Studio / JDK configured
- Firebase project created (with web app registered)
- TMDB API key obtained

### Step 1: Configure Environment Variables
You need to run the build with your API keys as dart-defines:

```bash
flutter run \
  --dart-define=TMDB_API_KEY=<your_tmdb_key> \
  --dart-define=FIREBASE_API_KEY=<firebase_api_key> \
  --dart-define=FIREBASE_PROJECT_ID=<project_id> \
  --dart-define=FIREBASE_APP_ID=<app_id> \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=<sender_id> \
  --dart-define=FIREBASE_STORAGE_BUCKET=<bucket>
```

**Where to find these values:**
1. **Firebase Config**: Go to Firebase Console → Project Settings → General → Your apps → Web App
2. **TMDB API Key**: https://www.themoviedb.org/settings/api

### Step 2: Build Release APK

```bash
# Clean and build release APK
flutter clean
flutter pub get
flutter build apk --release \
  --dart-define=TMDB_API_KEY=<your_tmdb_key> \
  --dart-define=FIREBASE_API_KEY=<firebase_api_key> \
  --dart-define=FIREBASE_PROJECT_ID=<project_id> \
  --dart-define=FIREBASE_APP_ID=<app_id> \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=<sender_id> \
  --dart-define=FIREBASE_STORAGE_BUCKET=<bucket>
```

Output location: `build/app/outputs/flutter-apk/app-release.apk`

### Step 3: Test on Device
```bash
# Install via ADB
adb install build/app/outputs/flutter-apk/app-release.apk

# Or share directly
export BETA_EMAILS="user1@example.com,user2@example.com"
# Use Google Play Internal Test or Firebase App Distribution
```

---

## 🐙 GitHub Setup & Code Push

### Option A: Initialize New Git Repository

```bash
# Initialize git in the project
cd C:\Users\Nadeem\Downloads\claude\cinemahub
git init
git add .
git commit -m "Initial CinemaHub commit"

# Create repo on GitHub (via CLI or web UI)
gh repo create cinemahub --public --description="Private invite-only streaming platform"
git remote add origin https://github.com/<username>/cinemahub.git
git push -u origin main
```

### Option B: Existing GitHub Repo
```bash
# Clone existing repo
git clone https://github.com/<username>/cinemahub.git
# Then copy all files from this project into it
```

---

## 🔑 Important Configuration Files Needed

### 1. Firebase Web App Credentials
Create at: https://console.firebase.google.com/

Go to Project Settings → Your apps → Add web app → Register app → Copy config

### 2. Google Services for Android
Add file: `android/app/google-services.json`
(Download from Firebase Console → Project Settings → General → Download google-services.json)

### 3. Android App Signing
For production builds, you'll need:
- Keystore file (.jks)
- Passwords for signing

Generate keystore:
```bash
keytool -genkeypair -v -storetype PKCS12 -keystore my-release-key.jks -alias my-key-alias -keyalg RSA -keysize 2048 -validity 10000
```

---

## 📱 Beta Distribution Options

### 1. Google Play Internal Testing (Recommended)
1. Upload APK to Play Console
2. Set up Internal Testing track
3. Invite testers by email
4. APK auto-updates for testers

### 2. Firebase App Distribution
1. Upload APK via Firebase console
2. Add testers by email
3. Testers get notification email
4. Works for both iOS and Android

### 3. Direct Share (Quick)
Just send the APK file:
```bash
# Find the APK
open build/app/outputs/flutter-apk/

# Or share via command line
# (Requires user to enable "Install from unknown sources")
```

---

## ⚠️ Before You Build - Checklist

- [ ] Firebase project created and configured
- [ ] Firebase web app registered (for get firebase config)
- [ ] google-services.json downloaded and placed in `android/app/`
- [ ] TMDB API key obtained and valid
- [ ] All environment variables ready for build
- [ ] Android Studio/Java setup verified (`flutter doctor`)

---

## 🛠️ Troubleshooting Common Issues

### Issue: "Firebase not configured" error on launch
**Solution:** Ensure `--dart-define=FIREBASE_API_KEY=...` is passed during build, not just development

### Issue: APK installs but crashes immediately
**Solution:** Check Android logcat:
```bash
adb logcat | grep -i flutter
```
Common causes:
- Missing google-services.json
- Incorrect API key format
- Missing internet permission

### Issue: Images don't load (broken poster URLs)
**Solution:** Verify TMDB image paths start with `/`:
```dart
// In tmdb_service.dart, the URL should be:
'https://image.tmdb.org/t/p/w200$posterPath'
// where posterPath = '/path/to/poster.jpg'
```

---

## 📦 Next Steps After First APK

1. **Set up CI/CD** - Automatically build when pushing to GitHub
2. **Configure automated testing** - Run tests before building
3. **Add analytics** - Track beta tester usage
4. **Prepare for production** - Set up paid releases

---
*Generated: 2024-01-19*