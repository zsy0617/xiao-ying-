param([Parameter(Mandatory=$true)][string]$BundleRoot)
$ErrorActionPreference = 'Stop'
$oldAppData = $env:APPDATA
$oldPlatform = $env:QT_QPA_PLATFORM
$work = Join-Path $env:RUNNER_TEMP ('beret-runtime-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $env:APPDATA = Join-Path $work 'AppData'
    $env:QT_QPA_PLATFORM = 'offscreen'
    $dataRoot = Join-Path $env:APPDATA 'dsh-pet-standalone-webm-chat'
    & (Join-Path $BundleRoot 'scripts\Install-And-Run.ps1') -PrepareOnly -BundleRoot $BundleRoot -DataRoot $dataRoot
    $relative = [IO.File]::ReadAllText((Join-Path $BundleRoot 'app-relative-path.txt')).Trim()
    $exe = Join-Path $BundleRoot $relative
    $process = Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) -PassThru -RedirectStandardOutput (Join-Path $work 'stdout.txt') -RedirectStandardError (Join-Path $work 'stderr.txt')
    $loaded = $false
    for ($i = 0; $i -lt 45; $i++) {
        Start-Sleep -Seconds 1
        foreach ($log in @(Get-ChildItem -LiteralPath $dataRoot -Filter 'pet-*.log' -ErrorAction SilentlyContinue)) {
            $text = Get-Content -LiteralPath $log.FullName -Raw -Encoding UTF8
            if ($text -match 'beret-girl 12') { $loaded = $true; break }
        }
        if ($loaded) { break }
        $process.Refresh()
        if ($process.HasExited -and $process.ExitCode -ne 0) { break }
    }
    if (-not $loaded) {
        Get-Content (Join-Path $work 'stderr.txt') -ErrorAction SilentlyContinue
        foreach ($log in @(Get-ChildItem -LiteralPath $dataRoot -Filter 'pet-*.log' -ErrorAction SilentlyContinue)) {
            Get-Content -LiteralPath $log.FullName -Tail 60 -Encoding UTF8
        }
        throw 'The packaged Windows application did not confirm all 12 Beret Girl clips.'
    }
    $cfg = Get-Content (Join-Path $dataRoot 'config-slot-0.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($cfg.character -ne 'beret-girl') { throw 'First startup did not keep the selected character.' }
    Write-Host 'PASS: official Windows runtime started offscreen with a fresh profile and loaded beret-girl, 12 clips.'
} finally {
    Get-Process -Name 'dsh-pet-standalone-webm-chat' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $env:APPDATA = $oldAppData
    $env:QT_QPA_PLATFORM = $oldPlatform
}

