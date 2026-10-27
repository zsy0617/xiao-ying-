[CmdletBinding()]
param(
    [switch]$PrepareOnly,
    [string]$DataRoot = '',
    [string]$BundleRoot = ''
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($BundleRoot)) {
    $BundleRoot = Split-Path -Parent $PSScriptRoot
}
$BundleRoot = [IO.Path]::GetFullPath($BundleRoot)
if ([string]::IsNullOrWhiteSpace($DataRoot)) {
    $DataRoot = Join-Path $env:APPDATA 'dsh-pet-standalone-webm-chat'
}
$DataRoot = [IO.Path]::GetFullPath($DataRoot)
$sourceRole = Join-Path $BundleRoot 'character\beret-girl'
$exeIndex = Join-Path $BundleRoot 'app-relative-path.txt'
if (-not (Test-Path -LiteralPath $exeIndex -PathType Leaf)) {
    throw 'The complete package is missing app-relative-path.txt. Extract the entire ZIP first.'
}
$exeRelative = [IO.File]::ReadAllText($exeIndex).Trim()
$exe = [IO.Path]::GetFullPath((Join-Path $BundleRoot $exeRelative))
$bundlePrefix = $BundleRoot.TrimEnd('\') + '\'
if (-not $exe.StartsWith($bundlePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The executable path must stay inside the extracted package.'
}
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw 'The desktop-pet program is missing. Extract the entire ZIP first.'
}
$hashIndex = Join-Path $sourceRole 'SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $hashIndex -PathType Leaf)) {
    throw 'The character files are missing. Extract the entire ZIP first.'
}
$entries = @()
foreach ($line in [IO.File]::ReadAllLines($hashIndex)) {
    if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { throw 'Invalid character checksum list.' }
    $relative = $Matches[2]
    if ([IO.Path]::IsPathRooted($relative) -or (($relative -split '[\\/]') -contains '..')) {
        throw 'Invalid character resource path.'
    }
    $entry = [pscustomobject]@{ Hash = $Matches[1]; Relative = $relative }
    $file = Join-Path $sourceRole $relative
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing character file: $relative" }
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Hash) {
        throw "Character checksum failed: $relative"
    }
    $entries += $entry
}
if ($entries.Count -lt 13) { throw 'The complete set of character resources was not found.' }
if (-not $PrepareOnly) {
    $running = Get-Process -Name 'dsh-pet-standalone-webm-chat' -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host 'Desktop pet is already running. Use its tray menu or exit it before changing the character.'
        return
    }
}
$configPath = Join-Path $DataRoot 'config-slot-0.json'
$hasConfig = Test-Path -LiteralPath $configPath -PathType Leaf
if ($hasConfig) {
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $config -or $config -isnot [pscustomobject]) {
        throw 'Existing desktop-pet settings are invalid. They have not been replaced.'
    }
} else {
    $config = [pscustomobject]@{ version = 4 }
}
$targetRole = Join-Path $DataRoot 'characters\beret-girl'
$roleMatches = Test-Path -LiteralPath $targetRole -PathType Container
if ($roleMatches) {
    foreach ($entry in $entries) {
        $targetFile = Join-Path $targetRole $entry.Relative
        if (-not (Test-Path -LiteralPath $targetFile -PathType Leaf) -or
            (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Hash) {
            $roleMatches = $false
            break
        }
    }
}
$needsConfig = -not ($config.PSObject.Properties.Name -contains 'character') -or $config.character -ne 'beret-girl'
if (-not $roleMatches -or $needsConfig) {
    New-Item -ItemType Directory -Path $DataRoot -Force | Out-Null
    $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
    $backup = Join-Path $DataRoot ("beret-girl-backups\" + $stamp)
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    if ($hasConfig) { Copy-Item -LiteralPath $configPath -Destination (Join-Path $backup 'config-slot-0.json') }
    $characters = Join-Path $DataRoot 'characters'
    New-Item -ItemType Directory -Path $characters -Force | Out-Null
    if (-not $roleMatches) {
        $staging = Join-Path $characters ('.beret-girl-staging-' + [guid]::NewGuid().ToString('N'))
        try {
            Copy-Item -LiteralPath $sourceRole -Destination $staging -Recurse
            if (Test-Path -LiteralPath $targetRole) {
                Move-Item -LiteralPath $targetRole -Destination (Join-Path $backup 'beret-girl')
            }
            Move-Item -LiteralPath $staging -Destination $targetRole
        } finally {
            if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
        }
    }
    if ($needsConfig) {
        $config | Add-Member -NotePropertyName character -NotePropertyValue 'beret-girl' -Force
        $json = $config | ConvertTo-Json -Depth 100
        $tempConfig = Join-Path $DataRoot ('.config-slot-0-' + [guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::WriteAllText($tempConfig, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
        if ($hasConfig) { [IO.File]::Replace($tempConfig, $configPath, $null) }
        else { Move-Item -LiteralPath $tempConfig -Destination $configPath }
    }
    Write-Host 'Beret Girl is ready. Existing model connections and chat settings were left in place.'
}
if ($PrepareOnly) {
    Write-Host 'Preparation complete; desktop-pet executable was not launched.'
    return
}
Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe)
Write-Host 'Desktop pet started. Select Beret Girl from the character menu if needed.'

