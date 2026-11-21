# 🚀 CinemaHub v1.5.1 — Video Playback Hotfix & Player Control Optimization

CinemaHub **v1.5.1** is a high-priority stability hotfix resolving video playback issues, optimizing player embed loading, and unlocking all interactive player controls.

---

## 🛠️ What's Fixed in v1.5.1

### 🎬 Video Embed & Stream Playback Fix
* **Eliminated Nested Iframe Sandboxing:** Removed the broken outer sandboxed iframe (`loadHtmlString`) that was causing video embeds (VidSrc, SuperEmbed, VidLink, AutoEmbed, 2Embed, Embed.su, MoviesAPI, etc.) to load under an opaque `null` origin with empty `Referer` headers.
* **Direct Origin & Referer Preservation:** All web embeds now load directly in the hardware-accelerated WebView with full `Origin`, `Referer`, and DOM storage (`localStorage`) access, allowing video player scripts, decoders, and HLS/MP4 streams to initialize cleanly.

### 🛡️ Player Controls & Click Neutralizer Fix
* **Unblocked Player UI Interactions:** Fixed an overly aggressive click interceptor in `AdBlockEngine.antiAdScript` that was catching relative URLs (`#`, `""`, `/server/...`) on the capture phase, which previously disabled clicks on play/pause buttons, server selectors, audio tracks, and episode pickers.
* **Intelligent Outbound Blocking:** Outbound ad popups and new tabs remain strictly blocked, while internal player controls now respond immediately.

### 🌐 Cross-Platform & Startup Stability
* **Web & Platform Guards:** Added `kIsWeb` guards to prevent `dart:io` platform crashes on non-Android runtimes.
* **Un-themed Lockout Removal:** Removed the hard white configuration error screen, ensuring CinemaHub's dark theme and Stremio community shelves always load reliably.

---

## 📥 Download & Install

* **File:** `app-arm64-v8a-release.apk`
* **Architecture:** Android ARM64 (`arm64-v8a`)
* **OTA Availability:** Available immediately via in-app update prompt or Settings ➔ Check for Updates.
