# CinemaHub Firebase Setup

This document explains how to configure Firebase for CinemaHub.

## 1. Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Add project"
3. Enter project name: `cinemahub`
4. Continue through setup (disable Google Analytics if desired)
5. Wait for project creation
6. Note the **Project ID** (format: `cinemahub-XXXXX`)

## 2. Register Android App

1. In Firebase console, click "Add app" → "Android app"
2. Android package name: `com.cinemahub.app`
3. App nickname: `CinemaHub`
4. Download `google-services.json`
5. Place `google-services.json` in `android/app/`

## 3. Configure Authentication

1. In Firebase console, go to Authentication → Sign-in method
2. Enable providers:
   - **Google** → Enable
   - **Email/Password** → Enable
3. Add authorized domains:
   - `localhost` (for local testing)
   - Your production domain when deploying

## 4. Configure Firestore

1. In Firebase console, go to Firestore Database
2. Create database in "test mode" initially
3. Security rules: `firestore.rules`
4. Set Firestore location (choose closest to your users)

## 5. Initialize Firebase Core

The app initializes Firebase on Android using the `google-services.json` file automatically via the Google Services Gradle plugin.

For local development, the app checks if Firebase is configured:
```dart
final firebaseConfigured = DefaultFirebaseOptions.isConfigured;
```

If not configured (e.g., missing `FIREBASE_API_KEY`), the app falls back to test mode.

## 6. GitHub Actions Secrets

Add these secrets to the GitHub repository (Settings → Secrets → Actions):

| Secret | Value | Source |
|--------|-------|--------|
| `TMDB_API_KEY` | Your TMDB API key | [TMDB Settings](https://www.themoviedb.org/settings/api) |
| `FIREBASE_API_KEY` | From `google-services.json` | `project_info.project_id` or Firebase Settings |
| `FIREBASE_APP_ID` | Android app ID | `client[0].client_info.mobilesdk_app_id` |
| `FIREBASE_MESSAGING_SENDER_ID` | Project number | `project_info.project_number` |
| `FIREBASE_PROJECT_ID` | Project ID | Firebase Console Settings → General |
| `FIREBASE_STORAGE_BUCKET` | Storage bucket | `project_info.storage_bucket` |
| `FIREBASE_AUTH_DOMAIN` | Auth domain | `{project_id}.firebaseapp.com` |

## 7. Add Admin User

After initial setup, add the first admin user:

1. In Firestore, manually create a document in `users/{uid}`
2. Set fields:
   - `email`: user's email
   - `role`: "owner"
   - `status`: "approved"
3. The first user who signs in becomes the admin

## 8. Build & Release

1. Push a git tag: `git tag v1.0.0-beta.1 && git push origin v1.0.0-beta.1`
2. GitHub Actions will:
   - Run tests
   - Build Android APK (arm64)
   - Create GitHub Release with `app-arm64_v8a-release.apk`

## Troubleshooting

### "Firebase is not configured"
- Ensure `google-services.json` is in `android/app/`
- Check Android package name matches `com.cinemahub.app`
- Verify all `--dart-define` secrets are set in GitHub Actions
- Run `flutter clean` locally

### "Authentication failed"
- Verify Google Sign-In is enabled in Firebase console
- Check OAuth consent screen is configured (if prompted)
- Verify authorized domains include `localhost`

### "Security rules blocked access"
- Verify user document exists in `users/{uid}`
- Check `status` field is "approved"
- Verify `role` field includes "admin" or "owner"

### "APK not building"
- Check GitHub Actions logs for build errors
- Verify all secrets are set in repository settings
- Ensure `google-services.json` is committed to the repo