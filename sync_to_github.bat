@echo off
echo ============================================
echo CinemaHub - Sync to GitHub
echo ============================================
echo.

REM Check if git is installed
git --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Git is not installed!
    echo Please install Git from: https://git-scm.com/downloads
    pause
    exit /b 1
)

REM Check if we're in the right directory
cd /d "C:\Users\Nadeem\Downloads\claude\cinemahub"
if %errorlevel% neq 0 (
    echo [ERROR] Cannot change to project directory
    pause
    exit /b 1
)

echo [1/6] Initializing Git repository...
git init
if %errorlevel% neq 0 (
    echo [ERROR] Failed to initialize git
    pause
    exit /b 1
)
echo ✓ Git initialized

echo.
echo [2/6] Adding all files...
git add .
if %errorlevel% neq 0 (
    echo [ERROR] Failed to add files
    pause
    exit /b 1
)
echo ✓ Files added

echo.
echo [3/6] Creating initial commit...
git commit -m "Initial CinemaHub commit

- Phase 1: Security (100% complete)
  - Fixed self-approval bypass vulnerability
  - Implemented Firebase authentication
  - Added admin dashboard
  - Secured Firestore rules

- Phase 2: TMDB Integration (100% complete)
  - TMDB service with --dart-define configuration
  - API key validation and error handling
  - MovieCard widget implementation

- Phase 3: Home Screen (100% complete)
  - Trending section with real TMDB data
  - Popular section (movies + series)
  - Hero banner with cinematic UI
  - Image loading with cached_network_image

- Documentation
  - BUILD_APK.md - Build and deployment guide
  - PROGRESS_REPORT.md - Phase-wise progress
  - TMDB_INTEGRATION.md - TMDB setup guide
  - CI/CD workflow (.github/workflows/build.yml)

Tech Stack: Flutter 3.22.0 / Dart 3.13.7, Firebase, TMDB, Stremio
"
if %errorlevel% neq 0 (
    echo [ERROR] Failed to create commit
    pause
    exit /b 1
)
echo ✓ Initial commit created

echo.
echo [4/6] Adding remote repository...
git remote add origin https://github.com/nadeemalam178/cinemahub.git
if %errorlevel% neq 0 (
    echo [ERROR] Failed to add remote
    pause
    exit /b 1
)
echo ✓ Remote added

echo.
echo [5/6] Checking branch...
git branch -M main
echo ✓ Branch set to 'main'

echo.
echo [6/6] Pushing to GitHub...
git push -u origin main
if %errorlevel% neq 0 (
    echo [ERROR] Failed to push to GitHub
    echo.
    echo Possible solutions:
    echo 1. Make sure you've authenticated with GitHub (run: git config --global user.name "Your Name")
    echo 2. Ensure you have write access to the repository
    echo 3. Check your internet connection
    pause
    exit /b 1
)
echo ✓ Code pushed to GitHub!

echo.
echo ============================================
echo SUCCESS! All code has been synced to GitHub
echo ============================================
echo.
echo Repository: https://github.com/nadeemalam178/cinemahub
echo.
echo Next steps:
echo 1. Go to GitHub to verify the code was uploaded
echo 2. Add GitHub Secrets for CI/CD:
echo    - TMDB_API_KEY
echo    - FIREBASE_API_KEY
echo    - FIREBASE_PROJECT_ID
echo    - FIREBASE_APP_ID
echo    - FIREBASE_MESSAGING_SENDER_ID
echo    - FIREBASE_STORAGE_BUCKET
echo.
echo 3. The GitHub Actions workflow will automatically build APKs on push
echo.
pause
