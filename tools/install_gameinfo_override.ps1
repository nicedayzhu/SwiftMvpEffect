param(
    [string]$Cs2Root = (
        "F:\Program Files (x86)\Steam\steamapps\common\Counter-Strike Global Offensive"),
    [string]$AddonName = "swift_mvp_effect",
    [switch]$PrioritizeSwiftlyS2,
    [ValidateSet("Install", "Remove", "Status")]
    [string]$Action = "Install"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "_deployment_common.ps1")

$gameInfoPath = Join-Path $Cs2Root "game\csgo\gameinfo.gi"
Assert-PathExists -Path $gameInfoPath -Description "gameinfo.gi"

$lines = [System.Collections.Generic.List[string]]::new()
$lines.AddRange([string[]](Get-Content -LiteralPath $gameInfoPath))
$escapedAddon = [regex]::Escape($AddonName)
$mountPattern = (
    '^\s*Game\s+csgo/overrides/' +
    $escapedAddon +
    '\.vpk\s*(?://.*)?$')
$swiftlyPattern = '^\s*Game\s+csgo/addons/swiftlys2\s*(?://.*)?$'

$isMounted = Test-GameInfoMount `
    -GameInfoPath $gameInfoPath `
    -AddonName $AddonName
$swiftlyPriorityValid = !$PrioritizeSwiftlyS2.IsPresent -or (
    Test-GameInfoSwiftlyS2Priority -GameInfoPath $gameInfoPath)
if ($Action -eq "Status") {
    Write-Host (
        "Mount status for $AddonName at ${gameInfoPath}: " +
        $(if ($isMounted) { "mounted" } else { "not mounted" }))
    if ($PrioritizeSwiftlyS2.IsPresent) {
        Write-Host (
            "SwiftlyS2 SearchPath precedence: " +
            $(if ($swiftlyPriorityValid) { "valid" } else { "invalid" }))
    }
    return
}
if ($Action -eq "Install" -and $isMounted -and $swiftlyPriorityValid) {
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

if ($Action -eq "Install") {
    if ($PrioritizeSwiftlyS2.IsPresent -and !$swiftlyPriorityValid) {
        $swiftlyIndexes = @(
            for ($index = 0; $index -lt $lines.Count; $index++) {
                if ($lines[$index] -match $swiftlyPattern) {
                    $index
                }
            })
        if ($swiftlyIndexes.Count -ne 1) {
            throw (
                "Expected exactly one 'Game csgo/addons/swiftlys2' SearchPath " +
                "in server gameinfo.gi; found $($swiftlyIndexes.Count).")
        }

        $swiftlyLine = $lines[$swiftlyIndexes[0]]
        $lines.RemoveAt($swiftlyIndexes[0])
        $lowViolenceIndex = -1
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match
                '^\s*Game_LowViolence\s+csgo_lv\s*(?://.*)?$') {
                $lowViolenceIndex = $index
                break
            }
        }
        $insertIndex = if ($lowViolenceIndex -ge 0) {
            $lowViolenceIndex + 1
        }
        else {
            0
        }
        $lines.Insert($insertIndex, $swiftlyLine)
    }

    if (!$isMounted) {
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
if ($Action -eq "Install" -and $PrioritizeSwiftlyS2.IsPresent -and
    !(Test-GameInfoSwiftlyS2Priority -GameInfoPath $gameInfoPath)) {
    throw "SwiftlyS2 SearchPath must precede every override VPK on the server."
}

Write-Host "$Action completed for $AddonName in $gameInfoPath"
Write-Host "Backup: $backupPath"
