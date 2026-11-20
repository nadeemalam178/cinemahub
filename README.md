<div align="center">

# 🎬 CinemaHub

### *The Private Streaming Platform for You & Your Friends*

[![Release](https://img.shields.io/github/v/release/nadeemalam178/cinemahub?color=E50914&label=Latest%20Release&style=for-the-badge)](https://github.com/nadeemalam178/cinemahub/releases/latest)
[![Platform](https://img.shields.io/badge/Platform-Android%20(ARM64)-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/nadeemalam178/cinemahub/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.47.9-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Auth%20%26%20Firestore-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)](https://firebase.google.com)
[![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)](LICENSE)

<br/>

<a href="https://github.com/nadeemalam178/cinemahub/releases/latest">
  <img src="https://img.shields.io/badge/⬇️%20DOWNLOAD%20LATEST%20APK-v1.1.0-E50914?style=for-the-badge&labelColor=1a0b18&logo=android&logoColor=white" height="42" alt="Download APK"/>
</a>

<br/><br/>

**CinemaHub** is a self-hosted, invite-only cinematic streaming application built with Flutter and Firebase. It combines the sleek aesthetic of premium streaming services with private gatekeeper access control and multi-source streaming engines.

</div>

---

## 🌟 Highlights

<table>
  <tr>
    <td width="50%">
      <h3>🔐 Private Community Gatekeeper</h3>
      <ul>
        <li><b>Dual Authentication:</b> Sign in with Google or Email/Password.</li>
        <li><b>Approval Workflow:</b> New accounts start in <i>Pending Access</i> until an admin approves them.</li>
        <li><b>Live Synchronization:</b> Real-time Firestore listeners grant instant access the moment an admin hits approve — zero app restarts needed.</li>
      </ul>
    </td>
    <td width="50%">
      <h3>🍿 TMDB-Powered Discovery</h3>
      <ul>
        <li><b>Trending & Popular:</b> Curated carousels of top movies and TV shows updated daily.</li>
        <li><b>Debounced Instant Search:</b> Fast, flicker-free search across movies, series, and cast.</li>
        <li><b>Rich Metadata:</b> High-res backdrops, trailers, ratings, genres, and complete season/episode selectors.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td width="50%">
      <h3>⚡ High-Performance Playback</h3>
      <ul>
        <li><b>Native Video Engine:</b> Hardware-accelerated streaming with custom cinema controls (`video_player` + `chewie`).</li>
        <li><b>Multi-Provider Resolution:</b> Stremio add-on compatibility with multi-stream fallbacks.</li>
        <li><b>External Player Handoff:</b> One-tap launch to VLC, MX Player, or Just Player.</li>
      </ul>
    </td>
    <td width="50%">
      <h3>🔄 Over-The-Air (OTA) Updates</h3>
      <ul>
        <li><b>Auto-Update Checks:</b> Automatically discovers new releases directly from GitHub on app startup.</li>
        <li><b>In-App Updater Dialog:</b> View release changelogs and download updates with a single tap.</li>
        <li><b>Settings Hub:</b> View current version and check for updates anytime under <i>Settings &gt; About &amp; Updates</i>.</li>
      </ul>
    </td>
  </tr>
</table>

---

## 📱 App Experience & Flow

```mermaid
graph TD
    A[Launch CinemaHub] --> B{Signed In?}
    B -->|No| C[Google / Email Sign-In]
    C --> D{Account Approved?}
    B -->|Yes| D
    D -->|Pending| E[Pending Access Screen]
    E -. Real-time Live Listener .->|Admin Approves| F[Home Screen]
    D -->|Approved| F
    
    F --> G[Browse Trending / Search TMDB]
    G --> H[Content Detail View]
    H --> I[Select Stream Provider]
    I --> J{Player Preference}
    J -->|In-App| K[CinemaPlayer with Hardware Acceleration]
    J -->|External| L[Launch VLC / MX Player]
    
    E -. Admin Sign-In .-> M[Admin Dashboard]
    M -->|Approve Users / Toggle Providers| F
```

---

## 🛠️ Technology Stack

| Layer | Technologies |
|---|---|
| **Frontend Framework** | [Flutter 3.47.9](https://flutter.dev) (Dart 3.13.7) |
| **Design System** | Custom CinemaHub Design Tokens (Material 3, Deep Canvas, Gold Accents) |
| **Authentication** | [Firebase Auth](https://firebase.google.com/docs/auth) (Google Sign-In + Email/Password) |
| **Database & Sync** | [Cloud Firestore](https://firebase.google.com/docs/firestore) (Real-time snapshots & Security Rules) |
| **Metadata Engine** | [The Movie Database (TMDB) API v3](https://developer.themoviedb.org) |
| **Playback & Streaming** | `video_player`, `chewie`, `url_launcher` |
| **Over-The-Air (OTA)** | GitHub Releases REST API + PackageInfo |
| **CI/CD Pipeline** | GitHub Actions (Cloud ARM64 APK compilation & Keystore signing) |

---

## 📥 Installation

1. Navigate to the **[Releases](https://github.com/nadeemalam178/cinemahub/releases)** page.
2. Download the latest **`app-arm64-v8a-release.apk`**.
3. Open the APK on your Android device (ensure *"Install unknown apps"* permission is granted for your browser/file manager).
4. Launch CinemaHub, sign in, and ask the administrator for approval!

---

## ⚙️ Building from Source

### Prerequisites
* Flutter SDK `3.47.9+`
* Java JDK `17+`
* Android SDK (API 34+)

```bash
# 1. Clone the repository
git clone https://github.com/nadeemalam178/cinemahub.git
cd cinemahub

# 2. Install dependencies
flutter pub get

# 3. Run static analysis & test suite
flutter analyze
flutter test

# 4. Run on a connected device
flutter run --dart-define=TMDB_API_KEY=YOUR_TMDB_KEY
```

---

## 🗺️ Roadmap & Upcoming Features

- [x] Firebase Google & Email Authentication
- [x] Admin approval gatekeeper with live real-time sync
- [x] TMDB catalogue, search debounce, and details screen
- [x] Hardware-accelerated video player with external player fallback
- [x] Custom CinemaHub branding & multi-density launcher icons
- [x] In-app Over-The-Air (OTA) updates from GitHub Releases
- [ ] **FMHY Video Multi-Server Embed Scrapers** (VidSrc, SuperEmbed, 2Embed, VidLink)
- [ ] Pre-configured community Stremio addons (Torrentio, Cyberflix)
- [ ] Watch progress synchronization & resume playback across devices
- [ ] Offline download caching

---

## 📄 License

This project is open source and available under the [MIT License](LICENSE).
