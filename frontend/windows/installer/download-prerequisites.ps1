$ErrorActionPreference = 'Stop'

# Download on the build PC; the resulting HRMS installer works offline.
$prerequisiteDirectory = Join-Path $PSScriptRoot 'prerequisites'
$downloadPath = Join-Path $prerequisiteDirectory 'vc_redist.x64.download.exe'
$destinationPath = Join-Path $prerequisiteDirectory 'vc_redist.x64.exe'
New-Item -ItemType Directory -Path $prerequisiteDirectory -Force | Out-Null
try {
    Invoke-WebRequest -Uri 'https://aka.ms/vc14/vc_redist.x64.exe' -OutFile $downloadPath
    $signature = Get-AuthenticodeSignature -LiteralPath $downloadPath
    if ($signature.Status -ne 'Valid' -or
        $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(?:,|$)') {
        throw 'The runtime download does not have a valid Microsoft signature.'
    }
    Move-Item -LiteralPath $downloadPath -Destination $destinationPath -Force
    $version = (Get-Item -LiteralPath $destinationPath).VersionInfo.FileVersion
    Write-Host "Verified Microsoft Visual C++ x64 Runtime $version"
    Write-Host "Saved to $destinationPath"
} finally {
    if (Test-Path -LiteralPath $downloadPath) {
        Remove-Item -LiteralPath $downloadPath -Force
    }
}
