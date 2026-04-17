# build_web.ps1 — Flutter Web production build for Vercel deployment
# Usage: .\build_web.ps1
#
# IMPORTANT: Before running, ensure these are correct:
#   1. GEMINI_API_KEY — get from https://aistudio.google.com/apikey
#   2. SUPABASE_URL + SUPABASE_ANON_KEY — get from Supabase dashboard > Settings > API
#   3. Run this script, then deploy with: vercel --prod

$ErrorActionPreference = "Stop"

# ── Configuration ──
# NOTE: GEMINI_API_KEY removed — now handled server-side by Koala API proxy
$KOALA_API_URL        = "https://koala-api-olive.vercel.app"
$SUPABASE_URL         = "https://xgefjepaqnghaotqybpi.supabase.co"
$SUPABASE_ANON_KEY    = "sb_publishable_ogP9BmI1n7xxUCTz3xDijA_xeIDyl7k"
$EVLUMBA_URL          = "https://vgtgcjnrsladdharzkwn.supabase.co"
$EVLUMBA_ANON_KEY     = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZndGdjam5yc2xhZGRoYXJ6a3duIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM0MjU1NzEsImV4cCI6MjA4OTAwMTU3MX0.7P5QagZdPntMliL1m5Zte7DSDR0CYkgwoHR7js4wqPg"

# ── Pre-flight checks ──
Write-Host "Pre-flight checks..." -ForegroundColor Cyan

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: flutter not found in PATH" -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrEmpty($SUPABASE_ANON_KEY) -or $SUPABASE_ANON_KEY -eq "YOUR_KEY_HERE") {
    Write-Host "ERROR: SUPABASE_ANON_KEY not set. Get from Supabase dashboard > Settings > API" -ForegroundColor Red
    exit 1
}

# ── Build ──
Write-Host "`nBuilding Flutter Web (release)..." -ForegroundColor Green

flutter build web --release `
  --dart-define=AI_PROVIDER=gemini `
  --dart-define=KOALA_API_URL=$KOALA_API_URL `
  --dart-define=SUPABASE_URL=$SUPABASE_URL `
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY `
  --dart-define=EVLUMBA_SUPABASE_URL=$EVLUMBA_URL `
  --dart-define=EVLUMBA_SUPABASE_ANON_KEY=$EVLUMBA_ANON_KEY `
  --dart-define=REQUIRE_LOGIN=false

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Flutter build failed" -ForegroundColor Red
    exit 1
}

# ── Post-build cleanup: debug sembol dosyalarını sil ──
# canvaskit/*.symbols + skwasm.js.symbols = ~3 MB debug-only dosya.
# Prod'a gitmemeli, sadece disk/transfer şişirir.
Write-Host "`nPruning debug symbol files..." -ForegroundColor Cyan
Get-ChildItem -Path "build/web" -Recurse -Filter "*.symbols" -ErrorAction SilentlyContinue |
    ForEach-Object {
        Remove-Item $_.FullName -Force
        Write-Host "  deleted $($_.Name)" -ForegroundColor DarkGray
    }

# ── Post-build verification ──
Write-Host "`nVerifying build output..." -ForegroundColor Cyan

$buildDir = "build/web"
$requiredFiles = @("index.html", "main.dart.js", "flutter_bootstrap.js", "favicon.png")

foreach ($file in $requiredFiles) {
    if (-not (Test-Path "$buildDir/$file")) {
        Write-Host "WARNING: Missing $file in build output" -ForegroundColor Yellow
    }
}

# Check that koalas.webp asset exists
if (-not (Test-Path "$buildDir/assets/assets/images/koalas.webp")) {
    Write-Host "WARNING: koalas.webp asset missing from build" -ForegroundColor Yellow
}

# Verify main.dart.js doesn't leak any API keys
$mainJs = Get-Content "$buildDir/main.dart.js" -Raw -ErrorAction SilentlyContinue
if ($mainJs -match "AIzaSy") {
    Write-Host "WARNING: Gemini API key found in build output! Check dart-defines." -ForegroundColor Red
}

Write-Host "`nBuild complete! Output: $buildDir" -ForegroundColor Green
Write-Host "Deploy with: vercel --prod" -ForegroundColor Cyan
Write-Host ""
