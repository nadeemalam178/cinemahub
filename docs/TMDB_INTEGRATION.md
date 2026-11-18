# TMDB API Key Verification

## How to Verify Your TMDB API Key is Working

### 1. Run with dart-define
The app must be run with your TMDB API key:

```bash
flutter run --dart-define=TMDB_API_KEY=your_actual_key_here
```

### 2. What Happens When Key is Valid
- ✅ App loads normally (no error screen)
- ✅ Home screen shows movie posters with real data
- ✅ "Trending" section displays popular movies
- ✅ "Popular" section shows recent popular content
- ✅ Tap a movie → navigates to detail screen

### 3. Error Screen (Key Missing/Invalid)
- ❌ Shows "TMDB API Key Missing" error screen
- ❌ Instructions to add `--dart-define=TMDB_API_KEY=...`
- ❌ Button link to tmdb.org/settings/api

### 4. Test the Key Manually
You can test your key with a simple curl command:

```bash
curl "https://api.themoviedb.org/3/movie/popular?api_key=YOUR_KEY&language=en-US&page=1"
```

If working, you'll get a JSON response with `results` array containing movies.

### 5. Get a Free TMDB Key
1. Sign up at: https://www.themoviedb.org/account/signup
2. Go to Settings → API: https://www.themoviedb.org/settings/api
3. Apply for API key (free tier available)
4. Copy your "API Key (v3 auth)"

## Integration Points

### TMDB Service
- Located at: `lib/core/catalogue/tmdb_service.dart`
- Uses: `--dart-define=TMDB_API_KEY=...`
- Validates via: `isConfigured` property

### Home Screen
- Displays trending and popular content
- Uses `CatalogueService` which wraps `TmdbService`
- Shows poster images via `cached_network_image`

### Detail Screen
- Fetches full movie/series metadata
- Shows cast, crew, similar titles
- Navigation from home via `Navigator.pushNamed('/details')`

## Troubleshooting

### "TMDB API Key Missing" Screen
- Ensure you're running with `--dart-define=TMDB_API_KEY=...`
- Check key has no typos or extra spaces
- Verify key is for "API Key (v3 auth)", not "Read Access Token"

### No Movies Shown
- Check network connectivity
- Verify key is active in TMDB dashboard
- Check TMDB rate limits (40 req/10s free tier)

### Image Loading Errors
- TMDB image URLs are constructed as: `https://image.tmdb.org/t/p/w200{poster_path}`
- Poster paths must start with `/` in TMDB response