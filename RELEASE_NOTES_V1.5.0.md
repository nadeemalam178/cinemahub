# 🚀 CinemaHub v1.5.0 — Zero-Ad Playback, Real-Debrid 4K, In-App Auto-Installer & Liquid Glassmorphism

CinemaHub **v1.5.0** is our biggest release yet! It introduces zero-ad sandboxed streaming, Real-Debrid 4K cloud streaming, a complete TV series episode browser, a seamless in-app APK updater with native installation, and a breathtaking liquid glassmorphic visual overhaul with a 3D faceted ruby brand emblem.

---

## 🌟 What's New in v1.5.0

### 🛡️ Zero-Ad Sandboxed Video Player
* **Engine-Level Ad & Popup Blocker:** Built an isolated iframe sandbox (`allow-scripts allow-same-origin allow-forms allow-presentation`) that strictly omits `allow-popups` and `allow-top-navigation`. Malicious popups, new tabs, and redirect hijackers are blocked at the browser engine level before they can even render.
* **Safe Overlay Neutralization:** Neutralizes deceptive transparent clickjack layers while keeping cross-origin video players intact.
* **Autoplay & Audio Unlock:** Automated media gesture unlocks on Android WebViews for seamless instant playback without repetitive play button tapping.

### ⚡ Real-Debrid & Community Addons (Torrentio 4K Direct Streaming)
* **Real-Debrid API Integration:** Enter your Real-Debrid API key to convert torrents into high-speed, direct HTTPS streams cached on high-bandwidth debrid servers — zero buffering, zero peer-to-peer tracking.
* **Multi-Addon Engine:** Scrapes **Torrentio**, **MediaFusion**, **Comet**, and **KnightCrawler** simultaneously.
* **Custom Addons Support:** Add your own Stremio addon manifest URLs in Settings to aggregate custom sources.
* **Direct Player Handoff:** Debrid streams play directly in the native Chewie hardware-accelerated player; magnet links automatically hand off to VLC or Nova Player.

### 📺 TV Series Episode & Season Browser
* **Interactive Season Dropdown:** Switch between seasons with automatic episode reloading.
* **Episode Carousel with TMDB Stills:** View episode titles, numbers, overview, and TMDB high-res backdrop stills.
* **Dynamic Stream Refresh:** Selecting an episode queries all scrapers with proper `:season:episode` formatting, instantly loading verified streams for that specific episode.

### 📲 In-App OTA Updater & Auto-Installer
* **Smart Version Checking:** Fixed version comparison logic so users already on the latest or equal release are never prompted again.
* **In-App Download with Live Progress:** Real-time download progress bar showing transferred megabytes, total size, download percentage, and network speed.
* **Native Android Package Installation:** Automatic handoff to Android's native package installer via FileProvider (`REQUEST_INSTALL_PACKAGES`), prompting "Install Update" right inside the app when download finishes.
* **Liquid Glass Changelog Modal:** Clean formatted markdown notes with release badges and gradient action buttons.

### 💎 Liquid Glassmorphism & 3D Faceted Emblem
* **3D Ruby Emblem:** Handcrafted multi-layered 3D faceted ruby emblem with gold trim, ambient drop shadows, and neon pulse.
* **Cinematic Splash Screen:** Dynamic logo animation with radial light sweeps, staggered wordmark reveal, and tagline.
* **Frosted Liquid Glass:** Depth-enhanced `GlassPanel` and `GlassCard` featuring dynamic frosted backdrop blur (`sigma 16`) and subtle borders across cards, carousels, and dialogs.
* **Cleaned Branding & Layout:** Removed all external plugin/Stremio phrasing from the homepage (now "CURATED SPOTLIGHT", "Global Movies", "Global Series") and removed redundant admin tiles from the Profile tab.

---

## 🛠️ Stream Categories Breakdown

CinemaHub v1.5.0 organizes streams into 4 distinct tabs on every content page:

| Tab | Category | Sources & Capabilities |
|---|---|---|
| **1** | **FMHY Multi-Server** | 28+ verified embeds (VidSrc, SuperEmbed, 2Embed, VidLink, MoviesAPI, etc.) with Zero-Ad Sandboxed Isolation |
| **2** | **Community Addons** | Torrentio, MediaFusion, Comet, KnightCrawler + Real-Debrid 4K Direct Cloud Streams |
| **3** | **Nuvio Streams** | Curated high-availability cloud scrapers |
| **4** | **CloudStream** | Direct cloud streaming servers with multi-quality resolution selectors |

---

## 📥 Download & Install

* **File:** `app-arm64-v8a-release.apk`
* **Architecture:** Android ARM64 (`arm64-v8a`)
* **Minimum Android:** Android 7.0 (API Level 24)
* **Target Android:** Android 14 (API Level 34)
* **Signed:** Production release keystore
