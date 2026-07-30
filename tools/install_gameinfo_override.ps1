param(
    [string]$Cs2Root = (
        "F:\Program Files (x86)\Steam\steamapps\common\Counter-Strike Global Offensive"),
    [string]$AddonName = "swift_mvp_effect",
    [ValidateSet("Install", "Remove", "Status")]
    [string]$Action = "Install"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "_deployment_common.ps1")

$gameInfoPath = Join-Path $Cs2Root "game\csgo\gameinfo.gi"
Assert-PathExists -Path $gameInfoPath -Description "gameinfo.gi"

$isMounted = Test-GameInfoMount `
    -GameInfoPath $gameInfoPath `
    -AddonName $AddonName
if ($Action -eq "Status") {
    Write-Host (
        "Mount status for $AddonName at ${gameInfoPath}: " +
        $(if ($isMounted) { "mounted" } else { "not mounted" }))
    return
}
if ($Action -eq "Install" -and $isMounted) {
    Write-Host "gameinfo.gi already mounts $AddonName."
    return
}
if ($Action -eq "Remove" -and !$isMounted) {
    Write-Host "gameinfo.gi does not mount $AddonName; nothing to remove."
    return
}

$backupPath = (
    "$gameInfoPath.bak.$AddonName.$(Get-Date -Format 'yyyyMMdd_HHmmss')")
Copy-Item -LiteralPath $gameInfoPath -Destination $backupPath -Force

$lines = [System.Collections.Generic.List[string]]::new()
$lines.AddRange([string[]](Get-Content -LiteralPath $gameInfoPath))
$escapedAddon = [regex]::Escape($AddonName)
$mountPattern = (
    '^\s*Game\s+csgo/overrides/' +
    $escapedAddon +
    '\.vpk\s*(?://.*)?$')

if ($Action -eq "Install") {
    $anchorIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\s*Game\s+csgo\s*(?://.*)?$') {
            $anchorIndex = $index
            break
        }
    }
    if ($anchorIndex -lt 0) {
        throw "Could not find the active 'Game csgo' SearchPaths anchor."
    }

    $lines.Insert(
        $anchorIndex,
        "`t`t`tGame`tcsgo/overrides/$AddonName.vpk")
}
else {
    for ($index = $lines.Count - 1; $index -ge 0; $index--) {
        if ($lines[$index] -match $mountPattern) {
            $lines.RemoveAt($index)
        }
    }
}

[System.IO.File]::WriteAllLines(
    $gameInfoPath,
    [string[]]$lines,
    [System.Text.UTF8Encoding]::new($false))

$mountedAfter = Test-GameInfoMount `
    -GameInfoPath $gameInfoPath `
    -AddonName $AddonName
if ($Action -eq "Install" -and !$mountedAfter) {
    throw "Mount line verification failed after editing $gameInfoPath."
}
if ($Action -eq "Remove" -and $mountedAfter) {
    throw "Mount line removal verification failed for $gameInfoPath."
}

Write-Host "$Action completed for $AddonName in $gameInfoPath"
Write-Host "Backup: $backupPath"
