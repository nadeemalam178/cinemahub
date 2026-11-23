<div align="center">

  <h1>🎬 CinemaHub</h1>
  <p><strong>A private, high-performance streaming platform built with Flutter & Firebase.</strong></p>
  <p><em>Featuring cinematic glassmorphic UI, TMDB discovery, Stremio/FMHY multi-provider scraping, and advanced multi-engine video playback.</em></p>

  <p>
    <img src="https://img.shields.io/badge/Flutter-3.13%2B-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter">
    <img src="https://img.shields.io/badge/Dart-3.x-0175C2?style=flat-square&logo=dart&logoColor=white" alt="Dart">
    <img src="https://img.shields.io/badge/Firebase-Auth%20%7C%20Firestore%20%7C%20Storage-FFCA28?style=flat-square&logo=firebase&logoColor=black" alt="Firebase">
    <img src="https://img.shields.io/badge/License-Private-red?style=flat-square" alt="License">
  </p>

</div>

---

## 🌟 Overview

**CinemaHub** is an advanced, premium-grade cross-platform streaming client tailored for approved users. It combines a gorgeous, high-end cinematic user interface with a robust backend service mesh that aggregates catalogues from **TMDB** and resolves streaming sources from **Stremio Addons** (Torrentio, KnightCrawler, MediaFusion, Comet), **FMHY catalogs**, **Cloudstream**, and **Nuvio**.

---

## ✨ Key Features

### 🎨 1. Immersive Cinematic UI & Design System
- **Glassmorphism & Depth**: Custom glassmorphic containers (`Glass`) and tuned design tokens (`CinemahubTokens`) delivering a premium streaming box experience.
- **Adaptive Layouts**: Optimized for mobile phones, tablets, foldables, and Android TV landscapes.

### 🔐 2. Secure Access & Authentication
- **Firebase Auth & Google Sign-In**: Secure authentication pipeline with whitelist gating for approved friends.
- **Admin Dashboard**: Real-time user access management and platform telemetry.

### 🔍 3. Rich Content Discovery
- **TMDB Integration**: Seamless trending movies, TV shows, genre filtering, rich cast/crew details, trailers, and similar recommendations.
- **Offline Caching**: Robust local caching via `Drift` and `SQLite` for instant catalog browsing.

### ⚡ 4. Multi-Provider Scraping Ecosystem
- **Stremio Addon Protocol**: Full support for resolving streams from Torrentio, KnightCrawler, MediaFusion, and Comet with Real-Debrid and P2P torrent parsing.
- **FMHY & Cloudstream Engines**: Verified embed server resolution and automated health checking (`SourceHealthChecker`).

### 🍿 5. Advanced Playback Engine
- **Native Video Player**: ExoPlayer-powered progressive & HLS (`.m3u8`) playback via Chewie with hardware acceleration.
- **Web Embed & Adblock Player**: Sandboxed in-app WebView player with M3U8 network interception and ad-shielding.
- **P2P Torrent Streaming**: Integrated in-app BitTorrent stream processing via `torrent_streamer`.

---

## 🛠️ Tech Stack

| Category | Technologies / Libraries |
| :--- | :--- |
| **Framework** | Flutter, Dart |
| **State Management** | Provider (`ChangeNotifier`), StreamControllers |
| **Routing** | GoRouter (`/home`, `/details`, `/search`, `/library`, `/settings`, `/admin`) |
| **Networking & Caching** | Dio, CachedNetworkImage, ConnectivityPlus |
| **Database & Storage** | SQLite, Drift, SharedPreferences, PathProvider |
| **Backend & Services** | Firebase Core, Auth, Firestore, Storage, Messaging, Local Notifications |
| **Media Playback** | VideoPlayer, Chewie, Flutter InAppWebView, Torrent Streamer |

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.13.7 or higher)
- Android SDK / Xcode (for mobile builds)
- Firebase Project configured with `google-services.json`

### 1. Clone the Repository
```bash
git clone https://github.com/nadeemalam178/cinemahub.git
cd cinemahub
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Configure Environment Variables
Pass your TMDB API key and Google Client ID via `--dart-define`:
```bash
flutter run --dart-define=TMDB_API_KEY=your_tmdb_api_key_here
```

### 4. Run Tests
Ensure all unit and integration tests pass successfully:
```bash
flutter test
```

---

## 📂 Project Structure

```text
lib/
├── core/
│   ├── admin/           # Admin controls & user management
│   ├── auth/            # Firebase Auth & Session gating
│   ├── catalogue/       # TMDB & Stremio catalogue services
│   ├── network/         # Connectivity providers
│   ├── notifications/   # Push notifications & local alerts
│   ├── player/          # Adblocker, M3U8 interceptor & players
│   ├── providers/       # Stremio, Cloudstream, FMHY adapters
│   ├── routing/         # GoRouter navigation definitions
│   ├── streaming/       # Streaming diagnostics, models & players
│   ├── sync/            # Offline synchronization service
│   └── update/          # In-app APK update manager
├── features/
│   ├── admin/           # Admin dashboard UI
│   ├── auth/            # Sign-in & splash screens
│   ├── details/         # Content details & stream selector
│   ├── home/            # Discovery carousels & grids
│   ├── library/         # Watchlist & favorites
│   ├── search/          # Multi-filter search screen
│   ├── settings/        # Playback diagnostics & preferences
│   └── shell/           # Bottom navigation app shell
└── main.dart            # Application bootstrap & provider wiring
```

---

## 🧪 Testing & Quality Assurance

CinemaHub features comprehensive test coverage across routing, provider streaming protocols, addon fallbacks, and widget states:
```bash
flutter test
```

---

## 📜 License

This project is private and intended solely for approved friends and personal use.
