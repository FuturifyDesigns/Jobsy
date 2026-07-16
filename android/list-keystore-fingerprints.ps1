# Prints SHA-1 and SHA-256 for a keystore alias (compare to Play Console fingerprint).
#
# Interactive password:
#   .\list-keystore-fingerprints.ps1 -Keystore "C:\path\to\backup.jks" -Alias upload
#
# Non-interactive (avoid leaving password in shell history — prefer interactive):
#   .\list-keystore-fingerprints.ps1 -Keystore "..." -Alias upload -StorePass "YOUR_PASS"

param(
    [Parameter(Mandatory = $true)]
    [string] $Keystore,
    [Parameter(Mandatory = $true)]
    [string] $Alias,
    [string] $StorePass = ''
)

$ErrorActionPreference = 'Stop'

function Get-KeytoolPath {
    $cmd = Get-Command keytool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($candidate in @(
        "${env:ProgramFiles}\Android\Android Studio\jbr\bin\keytool.exe",
        "${env:LOCALAPPDATA}\Programs\Android Studio\jbr\bin\keytool.exe"
    )) {
        if (Test-Path $candidate) { return $candidate }
    }
    throw 'keytool.exe not found. Install Android Studio or JDK.'
}

$keytool = Get-KeytoolPath
if (-not (Test-Path -LiteralPath $Keystore)) { throw "Keystore not found: $Keystore" }

if (-not $StorePass) {
    $Secure = Read-Host -AsSecureString -Prompt 'Keystore password'
    $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        $StorePass = [Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        $Secure.Dispose()
    }
}

$keytoolArgs = @(
    '-list', '-v',
    '-keystore', $Keystore,
    '-alias', $Alias,
    '-storepass', $StorePass
)

Write-Host "--- $Alias @ $Keystore ---"
$output = & $keytool @keytoolArgs 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw ($output + "`nkeytool exited $LASTEXITCODE") }
$output -split "`n" | Where-Object { $_ -match '^(Alias name:|Valid from:|until:|SHA1:|SHA256:)' }

Write-Host "`nCompare SHA-1 and SHA-256 above to the fingerprint shown under Key details in Play Console."

