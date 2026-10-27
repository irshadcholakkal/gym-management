param([Parameter(Mandatory=$true)][string]$SupabaseUrl,
      [Parameter(Mandatory=$true)][string]$SupabaseAnonKey,
      [Parameter(Mandatory=$true)][string]$AuthRedirectUrl,
      [string]$VapidPublicKey = '')
$ErrorActionPreference = 'Stop'
flutter build web --pwa-strategy=none --no-web-resources-cdn "--dart-define=SUPABASE_URL=$SupabaseUrl" "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey" "--dart-define=AUTH_REDIRECT_URL=$AuthRedirectUrl" "--dart-define=VAPID_PUBLIC_KEY=$VapidPublicKey"
if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed' }
node (Join-Path $PSScriptRoot 'prepare_web.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Offline shell preparation failed' }
Write-Output 'Built GymPro. Deploy build/web over HTTPS.'
