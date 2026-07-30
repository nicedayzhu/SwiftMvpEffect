param(
    [string]$ServerRoot = "F:\csgoserver_win\cs2",
    [string]$Cs2Root = (
        "F:\Program Files (x86)\Steam\steamapps\common\Counter-Strike Global Offensive"),
    [string]$AddonName = "swift_mvp_effect",
    [switch]$KeepPlugin,
    [switch]$KeepVpkFiles
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "_deployment_common.ps1")

& (Join-Path $PSScriptRoot "install_gameinfo_override.ps1") `
    -Cs2Root $Cs2Root `
    -AddonName $AddonName `
    -Action Remove
& (Join-Path $PSScriptRoot "install_gameinfo_override.ps1") `
    -Cs2Root $ServerRoot `
    -AddonName $AddonName `
    -Action Remove

if (!$KeepVpkFiles.IsPresent) {
    foreach ($vpk in @(
            (Join-Path $Cs2Root "game\csgo\overrides\$AddonName.vpk"),
            (Join-Path $ServerRoot "game\csgo\overrides\$AddonName.vpk"))) {
        $parent = Split-Path -Parent $vpk
        Assert-SafeChildPath `
            -Path $vpk `
            -Parent $parent `
            -ExpectedLeaf "$AddonName.vpk"
        if (Test-Path -LiteralPath $vpk -PathType Leaf) {
            Remove-Item -LiteralPath $vpk -Force
            Write-Host "Removed VPK: $vpk"
        }
    }
}

if (!$KeepPlugin.IsPresent) {
    $pluginParent = Join-Path $ServerRoot (
        "game\csgo\addons\swiftlys2\plugins")
    $pluginDir = Join-Path $pluginParent "SwiftMvpEffect"
    Assert-SafeChildPath `
        -Path $pluginDir `
        -Parent $pluginParent `
        -ExpectedLeaf "SwiftMvpEffect"
    if (Test-Path -LiteralPath $pluginDir -PathType Container) {
        Remove-Item -LiteralPath $pluginDir -Recurse -Force
        Write-Host "Removed server plugin: $pluginDir"
    }
}

Write-Host (
    "SwiftMvpEffect test deployment removed. Restart client and server.")

