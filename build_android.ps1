# build_android.ps1 - Flutter Android AAB production build
# Usage: .\build_android.ps1
#
# Mirrors build_web.ps1 but outputs a signed Android App Bundle.
#
# Requirements:
#   - android/key.properties (storePassword, keyPassword, keyAlias, storeFile)
#   - android/app/koala-release.jks (signing keystore - MUST match Play Store upload key)
#
# Output: build/app/outputs/bundle/release/app-release.aab
# Upload to: https://play.google.com/console

$ErrorActionPreference = "Stop"

# -- Configuration (identical to build_web.ps1) --
$KOALA_API_URL        = "https://koala-api-olive.vercel.app"
$SUPABASE_URL         = "https://xgefjepaqnghaotqybpi.supabase.co"
$SUPABASE_ANON_KEY    = "sb_publishable_ogP9BmI1n7xxUCTz3xDijA_xeIDyl7k"
$EVLUMBA_URL          = "https://vgtgcjnrsladdharzkwn.supabase.co"
$EVLUMBA_ANON_KEY     = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZndGdjam5yc2xhZGRoYXJ6a3duIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM0MjU1NzEsImV4cCI6MjA4OTAwMTU3MX0.7P5QagZdPntMliL1m5Zte7DSDR0CYkgwoHR7js4wqPg"

# -- Pre-flight checks --
Write-Host "Pre-flight checks..." -ForegroundColor Cyan

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: flutter not found in PATH" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path "android/key.properties")) {
    Write-Host "ERROR: android/key.properties missing - release signing requires it." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path "android/app/koala-release.jks")) {
    Write-Host "ERROR: android/app/koala-release.jks keystore missing." -ForegroundColor Red
    Write-Host "Without the original keystore, existing users cannot upgrade (signature mismatch)." -ForegroundColor Yellow
    exit 1
}

if ([string]::IsNullOrEmpty($SUPABASE_ANON_KEY)) {
    Write-Host "ERROR: SUPABASE_ANON_KEY is empty" -ForegroundColor Red
    exit 1
}

# -- Clean --
Write-Host "`nCleaning previous build artifacts..." -ForegroundColor Cyan
flutter clean | Out-Null
flutter pub get | Out-Null

# -- Build AAB --
Write-Host "`nBuilding Android App Bundle (release)..." -ForegroundColor Green

flutter build appbundle --release `
  --dart-define=AI_PROVIDER=gemini `
  --dart-define=KOALA_API_URL=$KOALA_API_URL `
  --dart-define=SUPABASE_URL=$SUPABASE_URL `
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY `
  --dart-define=EVLUMBA_SUPABASE_URL=$EVLUMBA_URL `
  --dart-define=EVLUMBA_SUPABASE_ANON_KEY=$EVLUMBA_ANON_KEY `
  --dart-define=REQUIRE_LOGIN=false

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Flutter AAB build failed" -ForegroundColor Red
    exit 1
}

# -- Verify --
$aabPath = "build/app/outputs/bundle/release/app-release.aab"

if (-not (Test-Path $aabPath)) {
    Write-Host "ERROR: AAB not found at expected path: $aabPath" -ForegroundColor Red
    exit 1
}

$aabSize = [math]::Round((Get-Item $aabPath).Length / 1MB, 2)
$versionLine = (Get-Content pubspec.yaml | Select-String '^version:').ToString()

Write-Host "`nAAB built successfully." -ForegroundColor Green
Write-Host "  $versionLine" -ForegroundColor White
Write-Host "  Path: $aabPath" -ForegroundColor White
Write-Host "  Size: $aabSize MB" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Play Console -> Koala -> Production -> Create release -> Upload this AAB" -ForegroundColor White
Write-Host "  2. Or for direct install: run 'flutter build apk --release ...' with same dart-defines" -ForegroundColor White
Write-Host ""
