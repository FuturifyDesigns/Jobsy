# WARNING: Deletes android/upload-keystore.jks and android/key.properties, then creates new ones.
# Do not rerun if this keystore is already registered in Play Console for Jobsy.

$ErrorActionPreference = 'Stop'
$androidDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Get-KeytoolPath {
    $cmd = Get-Command keytool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    foreach ($candidate in @(
        "${env:ProgramFiles}\Android\Android Studio\jbr\bin\keytool.exe",
        "${env:LOCALAPPDATA}\Programs\Android Studio\jbr\bin\keytool.exe"
    )) {
        if (Test-Path $candidate) { return $candidate }
    }

    throw "Could not find keytool.exe. Install Android Studio or add JDK bin to PATH."
}

$Keytool = Get-KeytoolPath

$keystorePath = Join-Path $androidDir 'upload-keystore.jks'
$keyPropsPath = Join-Path $androidDir 'key.properties'

if (Test-Path $keystorePath) { Remove-Item $keystorePath -Force }
if (Test-Path $keyPropsPath) { Remove-Item $keyPropsPath -Force }

$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$bytes = New-Object byte[] 16
$rng.GetBytes($bytes)
$pass = -join ($bytes | ForEach-Object { $_.ToString('x2') })

$keytoolArgs = @(
    '-genkeypair', '-v',
    '-keystore', $keystorePath,
    '-alias', 'jobsy',
    '-keyalg', 'RSA', '-keysize', '2048',
    '-validity', '10000',
    '-storetype', 'JKS',
    '-storepass', $pass,
    '-keypass', $pass,
    '-dname', 'CN=com.futurify.jobsy, OU=Mobile, O=Futurify, L=Unknown, ST=Unknown, C=US'
)
& $Keytool @keytoolArgs
if ($LASTEXITCODE -ne 0) { throw 'keytool failed' }

$lines = @(
    "storePassword=$pass"
    "keyPassword=$pass"
    'keyAlias=jobsy'
    'storeFile=upload-keystore.jks'
)
[System.IO.File]::WriteAllLines($keyPropsPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host 'Created upload-keystore.jks and key.properties'
