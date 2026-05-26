# Build Flutter web for Firebase Hosting (avoids Firebase Pigeon channel-error on web).
# Default build = testing stack (DAAO Tests + test Railway). See docs/ENVIRONMENTS.md.
# --no-tree-shake-icons: release web otherwise may omit Material icon glyphs → blank icons.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)
flutter build web --release --no-wasm-dry-run --no-tree-shake-icons --pwa-strategy=none
Write-Host "Done. Deploy test site: firebase deploy --only hosting:testing"
Write-Host "For production: add --dart-define=DEPLOY_ENV=production to flutter build, then: firebase deploy --only hosting:production"
