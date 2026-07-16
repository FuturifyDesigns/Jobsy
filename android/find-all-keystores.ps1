$ErrorActionPreference = 'Continue'
$userRoot = Join-Path $env:USERPROFILE ''
$exclude = '\\node_modules\\|\\\.gradle\\caches|\\AppData\\Local\\Packages\\|\\AppData\\Local\\pnpm\\|\\AppData\\Local\\Discord\\|\\AppData\\Local\\Temp\\|\\AppData\\Local\\Google\\Chrome\\User Data\\|\\AppData\\Roaming\\Code\\Cache\\|\\AppData\\Roaming\\Cursor\\Cache\\|\\AppData\\Local\\Microsoft\\'

$hits = [System.Collections.Generic.HashSet[string]]::new()

function Add-Matches ([string]$Filter) {
    Get-ChildItem -LiteralPath $userRoot -Filter $Filter -File -Recurse -Depth 10 -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            $p = $_.FullName
            if ($p -notmatch $exclude) {
                [void]$hits.Add($p)
            }
        }
}

Add-Matches '*.jks'
Add-Matches '*.keystore'

$hits | Sort-Object | ForEach-Object { $_ }
