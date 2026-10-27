$ErrorActionPreference = 'Stop'
$installer = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Install-And-Run.ps1'
$work = Join-Path ([IO.Path]::GetTempPath()) ('beret girl test ' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
function Assert($condition, $message) {
    if (-not $condition) { throw $message }
}
function WriteUtf8($path, $content) {
    [IO.File]::WriteAllText($path, $content, (New-Object Text.UTF8Encoding($false)))
}
function UpdateHashes($role) {
    $lines = @(Get-ChildItem -LiteralPath $role -File -Recurse |
        Where-Object { $_.Name -ne 'SHA256SUMS.txt' } |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($role.Length + 1).Replace('\','/')
            (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $relative
        })
    WriteUtf8 (Join-Path $role 'SHA256SUMS.txt') (($lines -join [Environment]::NewLine) + [Environment]::NewLine)
}
try {
    $bundle = Join-Path $work 'bundle'
    $role = Join-Path $bundle 'character\beret-girl'
    $videos = Join-Path $role 'videos\random'
    $app = Join-Path $bundle 'app'
    New-Item -ItemType Directory -Path $videos,$app -Force | Out-Null
    WriteUtf8 (Join-Path $role 'manifest.json') '{"name":"Beret Girl"}'
    1..12 | ForEach-Object { WriteUtf8 (Join-Path $videos ("clip-" + $_ + ".webm")) ("fixture " + $_) }
    WriteUtf8 (Join-Path $app 'dsh-pet-standalone-webm-chat.exe') 'not executed in tests'
    WriteUtf8 (Join-Path $bundle 'app-relative-path.txt') 'app/dsh-pet-standalone-webm-chat.exe'
    UpdateHashes $role
    $existing = Join-Path $work 'existing profile'
    New-Item -ItemType Directory -Path $existing | Out-Null
    WriteUtf8 (Join-Path $existing 'config-slot-0.json') '{"version":4,"character":"shenshen","scale":1.25,"custom":{"keep":true}}'
    WriteUtf8 (Join-Path $existing 'config.json') '{"chat":{"provider":"untouched","placeholder":"not a credential"}}'
    $globalBefore = (Get-FileHash (Join-Path $existing 'config.json')).Hash
    & $installer -PrepareOnly -BundleRoot $bundle -DataRoot $existing
    $cfg = Get-Content (Join-Path $existing 'config-slot-0.json') -Raw | ConvertFrom-Json
    Assert ($cfg.character -eq 'beret-girl') 'Character was not selected.'
    Assert ($cfg.scale -eq 1.25 -and $cfg.custom.keep) 'Unrelated per-pet settings changed.'
    Assert ((Get-FileHash (Join-Path $existing 'config.json')).Hash -eq $globalBefore) 'Global chat settings changed.'
    Assert (@(Get-ChildItem (Join-Path $existing 'beret-girl-backups') -Directory).Count -eq 1) 'Settings backup is missing.'
    & $installer -PrepareOnly -BundleRoot $bundle -DataRoot $existing
    Assert (@(Get-ChildItem (Join-Path $existing 'beret-girl-backups') -Directory).Count -eq 1) 'Idempotent launch made another backup.'
    WriteUtf8 (Join-Path $videos 'clip-1.webm') 'updated fixture'
    UpdateHashes $role
    & $installer -PrepareOnly -BundleRoot $bundle -DataRoot $existing
    Assert (@(Get-ChildItem (Join-Path $existing 'beret-girl-backups') -Directory).Count -eq 2) 'Updating an existing role did not back up the old role.'
    $fresh = Join-Path $work 'fresh profile'
    & $installer -PrepareOnly -BundleRoot $bundle -DataRoot $fresh
    $freshCfg = Get-Content (Join-Path $fresh 'config-slot-0.json') -Raw | ConvertFrom-Json
    Assert ($freshCfg.version -eq 4 -and $freshCfg.character -eq 'beret-girl') 'Fresh setup failed.'
    $invalid = Join-Path $work 'invalid profile'
    New-Item -ItemType Directory -Path $invalid | Out-Null
    WriteUtf8 (Join-Path $invalid 'config-slot-0.json') '{invalid json'
    $caught = $false
    try { & $installer -PrepareOnly -BundleRoot $bundle -DataRoot $invalid } catch { $caught = $true }
    Assert $caught 'Invalid existing settings were silently replaced.'
    Assert ((Get-Content (Join-Path $invalid 'config-slot-0.json') -Raw) -eq '{invalid json') 'Invalid original settings changed.'
    Assert (-not (Test-Path (Join-Path $invalid 'characters'))) 'Character directory was changed before invalid settings were rejected.'
    Write-Host 'PASS: fresh install, preservation, backups, idempotence, update, invalid-JSON protection.'
} finally {
    if (Test-Path $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}

