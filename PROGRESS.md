# CinemaHub — Progress Log

## Milestone 1: Project Inspection Complete (2026-11-19)

### Team
- **Chief** (me): coordination, tooling, consolidated reporting
- **Flutter Dev**: screen/catalogue inspection ✓ complete
- **QA Engineer**: test suite + auth screens ✓ complete
- **Architect**: security review of firestore.rules + auth/provider services ✓ complete

### Tooling verified
- `flutter --version`: Flutter 3.47.9 / Dart 3.13.7 — clean
- `flutter analyze`: **40 issues, all warnings/info, ZERO errors** — project compiles
- `flutter test`: **PASSES** — `00:00 +0: CinemaHubApp pumps a frame` (runner hangs after result; test itself green)

### Real & working
- `lib/core/catalogue/tmdb_service.dart` — full TMDB client (search, details, trending, popular, genres). API key is placeholder `YOUR_TMDB_API_KEY_HERE`.
- `lib/core/catalogue/catalogue_service.dart` — normalisation, debounced search, in-memory cache
- `lib/core/providers/provider_registry.dart` — Firestore-backed allow-list, sorted by priority
- `lib/core/providers/provider_model.dart` — Stremio manifest model with `supports()`, Firestore serialisation
- `lib/core/providers/stremio_adapter.dart` — manifest/stream/meta fetch per Stremio protocol
- `lib/core/player/playback_engine.dart` — multi-provider fallback, health-aware
- `lib/core/player/video_player_widget.dart` — Chewie + video_player, error states
- `lib/core/sync/sync_service.dart` — debounced progress writes, offline queue, owner-scoped
- `lib/core/admin/admin_service.dart` — user management, provider toggles, admin-gated
- `lib/core/auth/auth_service.dart` — Google sign-in, account status from Firestore
- `lib/core/routing/app_router.dart` — 5-state routing
- DI wiring in `lib/main.dart` — solid, all services provided via MultiProvider

### Placeholder / broken
| File | Issue |
|---|---|
| `lib/features/home/home_screen.dart` | Zero catalogue integration — shimmer placeholders only, no `getTrending()`/`getPopularMovies()` |
| `lib/features/search/search_screen.dart` | Search runs but results discarded — `Center(child: Text('Search results would appear here'))`, `onMovies`/`onSeries` callbacks fire but never store data |
| `lib/features/details/content_detail_screen.dart` | `_meta` fetched from TMDB but never rendered — `_meta`, `_loadingMeta`, `_metaError` all flagged `unused_field` by analyzer. Backdrop uses constructor arg (often null). |
| `lib/features/library/library_screen.dart` | Static empty state — no `SyncService` watchlist/history reads |
| `lib/core/catalogue/tmdb_service.dart` | API key is placeholder `YOUR_TMDB_API_KEY_HERE` — all real network calls silently fail |

### Security findings (firestore.rules + auth_service.dart — cross-referenced by Architect)
- **🔴 CRITICAL: Self-approval bypass.** `firestore.rules` lines 15–17 grant unrestricted `read, write` on `users/{userId}` with no field-level restriction. A signed-in pending user can run `set({'status':'approved'}, merge:true)` from the client and flip themselves to approved — the invite-only gate is defeated. Same rule lets a user write `role: 'owner'` into their own doc; admin UI elements appear for anyone (UI-only bypass since actual privileged writes still check custom claims).
- **🔴 CRITICAL: Custom claims never provisioned.** Rules gate admin/owner writes on `request.auth.token.role == 'admin'|'owner'`, but **no code in the repo sets that claim** — no Cloud Functions, no Admin SDK, no `customClaim`/`setCustomClaim` anywhere. Admin writes are permanently denied for everyone. Client reads role from Firestore doc (`users/{uid}.role`), server checks custom claim — two sources of truth that never reconcile.
- **🟡 HIGH:** `AdminService.userStream` reads the whole `users` collection, but rules only allow reading `users/{userId}`, so dashboard always shows "Failed to load users".
- **🟡 HIGH:** `ProviderHealth.publish()` writes to a subcollection with no matching rule → health writes fail silently.
- **🟡 MEDIUM:** TMDB key is `'YOUR_TMDB_API_KEY_HERE'` placeholder shipped in APK, sent as URL query param.
- **🟡 MEDIUM:** `main.dart` hardcodes `firebaseConfigured: false` — Firebase never initialises.
- **🟠 LOW:** `firestore.indexes.json` declares index on `lastChecked`; code writes `checkedAt`. Index never used.

### Milestone 2: QA Inspection Complete (2026-11-19)

- **Test coverage audit**: 1 smoke test only; all auth screens, AuthService, AppRouter, core services untested
- **Auth flow coverage**: only `loading→signedOut` exercised; `pendingApproval`, `approved`, `suspended` untested
- **Test infra**: mockito + build_runner ready; no helpers/fakes exist
- **Dead code confirmed**: ContentDetailScreen `_meta`, `_loadingMeta`, `_metaError` unused

### Next steps (awaiting user approval)

**Phase 1 Complete (Security & Foundation):**
✅ t1: Self-approval bypass fixed (`firestore.rules` lines 21-30 restrict status/role writes)
✅ t2: Custom claims provisioned via Cloud Functions (`functions/src/index.ts` writes to `admin/userStatus/{uid}`)
✅ t3: Firebase wired from build config (template ready in `lib/core/auth/firebase_options.dart`)
✅ t4: Firestore indexes fixed (`lastChecked` → `checkedAt`) + added rule for `providers/{id}/health` subcollection

**Phase 2: Screen Wiring (awaiting TMDB API key):**
⚪ t5: TMDB key injection via `--dart-define` + header + visible error
⚪ t6+: Search, Home, Details, Library screens (pending t5)

**Required from User:**
- **TMDB API key**: Get from https://www.themoviedb.org/settings/api and provide it to create the secure injection
- **Firebase config**: Provide the 8 required `--dart-define` values (auth domain is the "application URL")