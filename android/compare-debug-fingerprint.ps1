# Compare Play Console "fingerprint" to your local debug cert (hex, case-insensitive, colons optional).
# Run from PowerShell: powershell -File android\compare-debug-fingerprint.ps1 -ExpectedFingerPrint "paste-from-play-console"
param([Parameter(Mandatory = $true)][string]$ExpectedFingerPrint)

$keytool = if (Get-Command keytool -EA SilentlyContinue) { 'keytool' } elseif (Test-Path "${env:ProgramFiles}\Android\Android Studio\jbr\bin\keytool.exe") { "${env:ProgramFiles}\Android\Android Studio\jbr\bin\keytool.exe" } else { throw 'keytool not found' }

$dbg = Join-Path $env:USERPROFILE '.android\debug.keystore'
if (-not (Test-Path $dbg)) { throw "Missing $dbg" }

$expected = ($ExpectedFingerPrint -replace ':' -replace '\s', '').ToUpperInvariant()
$out = & $keytool @('-list', '-v', '-keystore', $dbg, '-alias', 'androiddebugkey', '-storepass', 'android') 2>&1 | Out-String
if (($null -eq $out) -or ($out -notmatch 'SHA256:\s*((?:[0-9A-F]{2}:)+[0-9A-F]{2})')) { throw $out }

$mine = (($Matches[1] -replace ':').ToUpperInvariant())
Write-Host "Local ~/.android/debug.keystore SHA256 (no colons): $mine"
Write-Host "Expected from Play argument (normalized):               $expected"
if ($mine -eq $expected) {
    Write-Host "MATCH - build with jobsy.playVerify=true in android/local.properties, then flutter build apk --release." -ForegroundColor Green
}
else {
    Write-Host "NO MATCH - this PC debug.keystore is NOT what Play expects. Restore an older debug.keystore backup, build on the original PC, or ask Play Console support to reset verification / upload key." -ForegroundColor Yellow
}
