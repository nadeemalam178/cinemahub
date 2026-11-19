# CinemaHub

A private streaming platform for approved friends — built with Flutter and Firebase.

## 🎬 Overview

CinemaHub is a premium, invite-only streaming application that combines a polished Netflix-inspired interface with robust privacy controls. It integrates with Firebase for authentication and Stremio-compatible providers for content delivery.

## ✨ Features

- **Premium UI**: Cinematic design with glass morphism effects, smooth transitions, and adaptive dark/light themes
- **Private Access**: Google authentication with approval-based access control
- **Multi-Provider Support**: Stremio-compatible add-on integration with health monitoring
- **Watch Progress**: Synchronized playback positions across devices
- **Watchlists**: Personal content collections that sync automatically
- **Admin Dashboard**: Owner-managed user approval and provider management
- **Cloud APK Builds**: Automated CI/CD via GitHub Actions

## 🛠️ Technology Stack

- **Flutter 3.47.9** (stable)
- **Dart 3.13.7**
- **Material 3 Design**
- **Firebase Authentication** (Google Sign-In)
- **Cloud Firestore** (secure database)
- **TMDB Integration** (metadata API)
- **Stremio Add-on SDK** (content providers)
- **GitHub Actions** (cloud APK builds)

## 📱 Screens

1. Splash Screen
2. Google Sign-In
3. Pending Access (approval required)
4. Home (featured, continue watching, trending)
5. Search (movies, series, genres)
6. Browse by Genre
7. Movie/Series Details
8. Video Player
9. Continue Watching
10. My List
11. Watch History
12. Profile Selection
13. User Settings
14. Provider Settings
15. Admin Dashboard
16. About & Updates

## 🔧 Setup

### Prerequisites

- Flutter SDK 3.47.9+
- Java 17+
- Node.js 24+
- GitHub account with repository access

### Firebase Configuration

1. Create Firebase project at [console.firebase.google.com](https://console.firebase.google.com/)
2. Register Android app (package: `com.cinemahub.app`)
3. Download `google-services.json` → place in `android/app/`
4. Enable Google Sign-In in Firebase Auth
5. Configure Firestore with security rules
6. Add admin user manually in Firestore

See [docs/FIREBASE_SETUP.md](docs/FIREBASE_SETUP.md) for detailed instructions.

### GitHub Actions Secrets

Add these secrets to your GitHub repository (Settings → Secrets → Actions):

| Secret | Value | Source |
|--------|-------|--------|
| `TMDB_API_KEY` | Your TMDB API key | [TMDB Settings](https://www.themoviedb.org/settings/api) |
| `FIREBASE_API_KEY` | From `google-services.json` | `project_info.project_id` or Firebase Settings |
| `FIREBASE_APP_ID` | Android app ID | `client[0].client_info.mobilesdk_app_id` |
| `FIREBASE_MESSAGING_SENDER_ID` | Project number | `project_info.project_number` |
| `FIREBASE_PROJECT_ID` | Project ID | Firebase Console Settings → General |
| `FIREBASE_STORAGE_BUCKET` | Storage bucket | `project_info.storage_bucket` |
| `FIREBASE_AUTH_DOMAIN` | Auth domain | `{project_id}.firebaseapp.com` |

## 🚀 Development

```bash
# Clone and setup
git clone https://github.com/nadeemalam178/cinemahub.git
cd cinemahub

# Install dependencies
flutter pub get

# Run locally (requires Firebase config)
flutter run

# Analyze code
flutter analyze

# Run tests
flutter test
```

## 📊 Database Schema

```
users/{uid}
├── profiles/{profileId}
├── watchHistory/{contentId}
├── watchlist/{contentId}
└── settings

catalogue/{contentId}
├── episodes/{episodeId}
└── metadata

providers/{providerId}
└── health/{timestamp}

accessRequests/{uid}
└── {status, createdAt, ...}

admin/{docId}
└── {stats, logs, ...}
```

## 🔒 Security

- Firestore rules enforce access control
- Users can only access their own data
- Admin-only user approval and provider management
- Never expose Firebase credentials in client code
- All network requests are authenticated

## 🎨 Design System

- Color tokens for consistent theming
- Typography scale with cinematic feel
- Glass morphism effects (used sparingly)
- Smooth transitions and micro-interactions
- Responsive layouts for all screen sizes

## 🚀 Deployment

APK builds are automated via GitHub Actions:

1. Push to main branch → builds debug APK
2. Create release tag (e.g., `v1.0.0`) → builds signed release APK
3. APK is attached to GitHub release

## 📝 Provider Integration

CinemaHub supports Stremio-compatible add-ons with:

- Manifest parsing
- Catalog and metadata fetching
- Stream URL resolution
- Subtitle support
- Health monitoring

Only authorized providers are supported. See [docs/PROVIDER_INTEGRATION.md](docs/PROVIDER_INTEGRATION.md).

## 🧪 Testing

- Unit tests for core services
- Widget tests for UI components
- Integration tests for auth flows
- Firebase security rule testing

## 📈 Roadmap

- [ ] TMDB catalogue integration
- [ ] Video player with subtitle support
- [ ] Push notifications
- [ ] Multi-profile support
- [ ] Advanced provider management
- [ ] Offline mode
- [ ] Analytics dashboard

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## 📄 License

This project is private. All rights reserved.

---

**CinemaHub** — Your private cinema, built on trust.