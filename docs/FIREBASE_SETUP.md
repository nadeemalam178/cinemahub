# CinemaHub Firebase Setup

This document explains how to configure Firebase for CinemaHub.

## 1. Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Add project"
3. Enter project name: `cinemahub`
4. Continue through setup (disable Google Analytics if desired)
5. Wait for project creation

## 2. Register Android App

1. In Firebase console, click "Add app" → "Android app"
2. Android package name: `com.cinemahub.cinemahub`
3. App nickname: `CinemaHub`
4. Download `google-services.json`
5. Place `google-services.json` in `android/app/`

## 3. Configure Authentication

1. In Firebase console, go to Authentication
2. Enable Google Sign-In:
   - Sign-in method → Google → Enable
   - Configure OAuth consent screen if required
3. Add authorized domains:
   - `localhost` (for local testing)
   - Add your domain when deploying

## 4. Configure Firestore

1. In Firebase console, go to Firestore Database
2. Create database in "test mode" initially
3. Set security rules to `firestore.rules`
4. Create indexes from `firestore.indexes.json`
5. Switch to production mode after testing

## 5. Add Admin User

After initial setup, add the first admin user:

1. In Firestore, manually create a document in `users/{uid}`
2. Set email, role: "owner", status: "approved"

## 6. GitHub Actions Configuration

Add these secrets to GitHub repository:

```
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
ANDROID_SIGNING_KEY
```

## 7. Firebase SDK Initialization

The app will automatically detect `google-services.json` and configure Firebase.

## 8. Testing

1. Run locally: `flutter run`
2. Test Google Sign-In flow
3. Verify user appears in Firestore with "pending" status
4. Approve user via admin dashboard
5. Verify access to app features

## Troubleshooting

### "Firebase is not configured"
- Ensure `google-services.json` is in `android/app/`
- Check Android package name matches
- Run `flutter clean` and rebuild

### "Authentication failed"
- Verify Google Sign-In is enabled in Firebase console
- Check OAuth consent screen is configured
- Verify authorized domains

### "Security rules blocked access"
- Verify user document exists in Firestore
- Check status is "approved"
- Verify admin role is set correctly