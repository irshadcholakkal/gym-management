param(
  [string]$EnvFile = (Join-Path $PSScriptRoot '../.env'),
  [string]$OutputFile = (Join-Path $PSScriptRoot '../config.local.json')
)
$ErrorActionPreference = 'Stop'
$values = @{}
foreach ($line in Get-Content -LiteralPath $EnvFile) {
  if ($line -match '^\s*(?:export\s+)?([A-Z_][A-Z0-9_]*)\s*=\s*(.*?)\s*$') {
    $values[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
  }
}
$publicKey = $values['SUPABASE_PUBLISHABLE_KEY']
if (!$publicKey) { $publicKey = $values['SUPABASE_ANON_KEY'] }
if (!$values['SUPABASE_URL'] -or !$publicKey) {
  throw 'Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (or SUPABASE_ANON_KEY) in .env.'
}
if ($publicKey.StartsWith('sb_secret_')) { throw 'A secret key cannot be used in Flutter.' }
if (!$publicKey.StartsWith('sb_publishable_')) {
  try {
    $segment = $publicKey.Split('.')[1].Replace('-', '+').Replace('_', '/')
    $segment = $segment.PadRight($segment.Length + ((4 - $segment.Length % 4) % 4), '=')
    $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($segment)) | ConvertFrom-Json
    if ($claims.role -ne 'anon') { throw 'Not an anonymous key' }
  } catch { throw 'Use a Supabase publishable key or legacy anonymous key, never a server key.' }
}
# Explicit allow-list: the original .env must never become a Flutter asset or
# --dart-define-from-file input, because it can also contain server secrets.
$config = [ordered]@{
  SUPABASE_URL = $values['SUPABASE_URL']
  SUPABASE_PUBLISHABLE_KEY = $publicKey
}
foreach ($name in @('AUTH_REDIRECT_URL', 'VAPID_PUBLIC_KEY')) {
  if ($values[$name]) { $config[$name] = $values[$name] }
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputFile), ($config | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Output 'Public Flutter configuration generated. Server secrets excluded.'
