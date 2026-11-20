# 🎬 CinemaHub v1.0.0 — Official Beta Launch

Welcome to the inaugural beta release of **CinemaHub**! CinemaHub is a private, premium streaming platform crafted specifically for approved friends and family, combining curated movie discovery with seamless Stremio-powered video playback.

---

### ✨ Key Features

#### 🔐 Private Access & Admin Approval
* **Dual Sign-In:** Authenticate effortlessly using **Google Sign-In** or **Email & Password**.
* **Gatekeeper Security:** Fresh registrations enter a secure *Pending Approval* state until verified.
* **Real-time Live Sync:** Once an admin approves your profile from the built-in **Admin Dashboard**, the app instantly transitions to Home without needing a restart.

#### 🍿 Cinematic Catalogue (Powered by TMDB)
* **Discover Trending & Popular:** Browse top-rated movies and binge-worthy TV series with high-resolution artwork and smooth horizontal carousels.
* **Instant Search:** Fast search with automatic keystroke debounce — search effortlessly without UI stutter.
* **Detailed Info:** Full metadata including synopsis, genres, runtime, release dates, and complete season/episode selectors for series.
* **My List:** Bookmark movies and series to your personal watchlist.

#### ⚡ Stremio Playback Engine & Player
* **High-Speed Streaming:** Native hardware-accelerated playback with integrated controls via `video_player` and `chewie`.
* **Stremio Addon Support:** Resolves multi-source streams directly from community Stremio addons.
* **External Player Support:** Prefer VLC, MX Player, or Just Player? Launch external video players with a single tap.
* **Graceful Error Recovery:** Built-in network listeners and clear error handling for dead streams or lost connections.

#### 🎨 Premium Cinematic UI
* **Immersive Design System:** Built with custom CinemaHub design tokens, deep blacks, gold accents, and fluid transitions.
* **Adaptive Theme:** Seamless toggle between System, Dark, and Light themes.

---

### 📦 Android Installation Note
* **Target Architecture:** Optimized for `arm64-v8a` modern Android devices.
* **Signed APK:** Built and signed in GitHub Actions cloud with release credentials.
* **How to Install:** Download `app-arm64-v8a-release.apk` below, tap to install, and allow installation from unknown sources if prompted.
