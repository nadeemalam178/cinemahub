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
  <img src="https://img.shields.io/badge/⬇️%20DOWNLOAD%20LATEST%20APK-v1.5.0-E50914?style=for-the-badge&labelColor=1a0b18&logo=android&logoColor=white" height="42" alt="Download APK"/>
</a>

<br/><br/>

**CinemaHub** is a self-hosted, invite-only cinematic streaming application built with Flutter and Firebase. It combines the sleek aesthetic of premium streaming platforms with private gatekeeper access control, multi-source streaming engines, zero-ad sandboxed playback, and Real-Debrid 4K integration.

</div>

---

## 🌟 Highlights

<table>
  <tr>
    <td width="50%">
      <h3>🛡️ Zero-Ad Sandboxed Video Player</h3>
      <ul>
        <li><b>Isolated Iframe Shield:</b> Blocks 100% of popups, new tabs, and malicious redirects at the browser engine level using restricted sandbox attributes.</li>
        <li><b>Anti-Clickjacking:</b> Neutralizes invisible transparent overlays without affecting cross-origin video player frames.</li>
        <li><b>Media Autoplay & Audio Unlock:</b> Smooth one-tap playback without repetitive gesture prompts.</li>
      </ul>
    </td>
    <td width="50%">
      <h3>⚡ Real-Debrid & Community Addons</h3>
      <ul>
        <li><b>Real-Debrid 4K Cloud Streaming:</b> Converts torrents into instant, buffer-free, direct HTTPS streams hosted on high-speed debrid servers.</li>
        <li><b>Multi-Addon Scraper:</b> Aggregates streams from <i>Torrentio</i>, <i>MediaFusion</i>, <i>Comet</i>, and <i>KnightCrawler</i>.</li>
        <li><b>Custom Manifests:</b> Configure custom Stremio addon URLs directly inside app settings.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td width="50%">
      <h3>📺 TV Series Seasons & Episodes</h3>
      <ul>
        <li><b>Interactive Season Dropdown:</b> Instantly browse through every season of any TV show.</li>
        <li><b>Episode Carousel:</b> High-resolution TMDB episode backdrop stills, episode titles, and numbers.</li>
        <li><b>Smart Episode Resolution:</b> Automatically routes queries with <code>:season:episode</code> parameters to retrieve exact episode streams.</li>
      </ul>
    </td>
    <td width="50%">
      <h3>📲 In-App OTA Auto-Installer</h3>
      <ul>
        <li><b>Smart Version Check:</b> Compares semantic versions so installed versions are never prompted again.</li>
        <li><b>Live Download Progress:</b> Real-time progress bar with transferred MB, total size, percentage, and network speed.</li>
        <li><b>Native Android Installer:</b> Seamless handoff to Android's native package installer via FileProvider right after download finishes.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td width="50%">
      <h3>💎 Liquid Glassmorphism & 3D Logo</h3>
      <ul>
        <li><b>3D Faceted Ruby Emblem:</b> Handcrafted geometric crystal emblem with gold trim, ambient shadows, and neon pulse.</li>
        <li><b>Animated Splash Screen:</b> Radial light sweep, 3D emblem reveal, and smooth wordmark animation.</li>
        <li><b>Frosted Liquid Glass:</b> Depth-enhanced blur (sigma 16), subtle borders, and refined dark/light aesthetics.</li>
      </ul>
    </td>
    <td width="50%">
      <h3>🔐 Private Community Gatekeeper</h3>
      <ul>
        <li><b>Dual Authentication:</b> Sign in with Google or Email/Password.</li>
        <li><b>Approval Workflow:</b> New accounts start in <i>Pending Access</i> until an administrator approves them.</li>
        <li><b>Live Synchronization:</b> Real-time Firestore snapshot listeners grant instant access without restarting the app.</li>
      </ul>
    </td>
  </tr>
</table>

---

## 🧭 Multi-Stream Categories Breakdown

Every title in CinemaHub gives you instant access to 4 distinct streaming categories:

| Tab | Category | Providers & Capabilities |
|---|---|---|
| **1** | **FMHY Multi-Server** | 28+ verified embeds (VidSrc, SuperEmbed, 2Embed, VidLink, MoviesAPI, etc.) with Zero-Ad Sandboxed Protection |
| **2** | **Community Addons** | Torrentio, MediaFusion, Comet, KnightCrawler + Real-Debrid 4K Direct Cloud Streams |
| **3** | **Nuvio Streams** | Curated high-availability cloud scrapers |
| **4** | **CloudStream** | Direct cloud streaming servers with multi-quality resolution selectors |

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
    H --> S{Content Type}
    S -->|TV Series| T[Select Season & Episode]
    S -->|Movie| U[Auto-Resolve Streams]
    T --> U
    
    U --> V{Stream Category}
    V -->|FMHY Embeds| W[Zero-Ad Sandboxed Player]
    V -->|Real-Debrid 4K| X[Chewie Hardware Player]
    V -->|P2P Magnet| Y[Launch External Player VLC/Nova]
    V -->|CloudStream| X
```

---

## 🛠️ Technology Stack

| Layer | Technologies |
|---|---|
| **Frontend Framework** | [Flutter 3.47.9](https://flutter.dev) (Dart 3.13.7) |
| **Design System** | Liquid Glassmorphic Design Tokens (Material 3, Deep Canvas, Gold Accents, Frosted Blur) |
| **Authentication** | [Firebase Auth](https://firebase.google.com/docs/auth) (Google Sign-In + Email/Password) |
| **Database & Sync** | [Cloud Firestore](https://firebase.google.com/docs/firestore) (Real-time snapshots & Security Rules) |
| **Metadata Engine** | [The Movie Database (TMDB) API v3](https://developer.themoviedb.org) |
| **Video Playback** | Sandboxed `webview_flutter`, `video_player`, `chewie`, `url_launcher` |
| **Streaming Scrapers** | 28+ FMHY Embed Providers, Torrentio, MediaFusion, Comet, KnightCrawler, Real-Debrid REST API |
| **Over-The-Air (OTA)** | GitHub Releases API + Android `FileProvider` + Native Installer MethodChannel |
| **CI/CD Pipeline** | GitHub Actions (Cloud ARM64 APK compilation & Keystore signing) |

---

## 📥 Installation

1. Navigate to the **[Releases](https://github.com/nadeemalam178/cinemahub/releases)** page.
2. Download the latest **`app-arm64-v8a-release.apk`** (v1.5.0).
3. Open the APK on your Android device (ensure *"Install unknown apps"* permission is granted for your browser/file manager).
4. Launch CinemaHub, sign in, and ask the administrator for approval!

> 💡 **Tip:** Once installed, CinemaHub will automatically notify you of future updates and download/install them directly in-app!

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

## 🗺️ Roadmap & Features

- [x] Firebase Google & Email Authentication
- [x] Admin approval gatekeeper with live real-time sync
- [x] TMDB catalogue, search debounce, and details screen
- [x] Hardware-accelerated video player with external player fallback
- [x] Custom CinemaHub branding & multi-density launcher icons
- [x] In-app Over-The-Air (OTA) updates from GitHub Releases with live download & native auto-installer
- [x] Zero-Ad Sandboxed Stream Isolation (Popup & Redirect blocking)
- [x] FMHY Video Multi-Server Embed Scrapers (28+ servers)
- [x] Pre-configured community Stremio addons (Torrentio, MediaFusion, Comet, KnightCrawler)
- [x] Real-Debrid 4K Cloud Direct Streaming integration
- [x] Complete TV Series Season & Episode Navigation with TMDB thumbnails
- [x] Liquid Glassmorphic UI redesign & 3D faceted crystal branding
- [ ] Watch progress synchronization & resume playback across devices
- [ ] Offline download caching

---

## 📄 License

This project is open source and available under the [MIT License](LICENSE).
