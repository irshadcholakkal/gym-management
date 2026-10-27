param([int]$Port = 8080)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'load_public_config.ps1')
Push-Location (Join-Path $PSScriptRoot '..')
try {
  flutter run -d chrome --web-port $Port --dart-define-from-file=config.local.json
} finally { Pop-Location }
