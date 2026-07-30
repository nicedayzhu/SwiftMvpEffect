param(
    [string]$ServerRoot = "F:\csgoserver_win\cs2",
    [string]$Cs2Root = (
        "F:\Program Files (x86)\Steam\steamapps\common\Counter-Strike Global Offensive"),
    [string]$AddonName = "swift_mvp_effect",
    [string]$VpkEditCli = (
        "F:\cs2dev\SkinTools\VPKEdit-Windows-Standalone-msvc-Release\vpkeditcli.exe")
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "_deployment_common.ps1")

$projectRoot = Resolve-FullPath (Join-Path $PSScriptRoot "..")
$publishDir = Join-Path $projectRoot "build\publish\SwiftMvpEffect"
$localVpk = Join-Path $Cs2Root "game\csgo\overrides\$AddonName.vpk"
$serverVpk = Join-Path $ServerRoot "game\csgo\overrides\$AddonName.vpk"
$serverPluginDir = Join-Path $ServerRoot (
    "game\csgo\addons\swiftlys2\plugins\SwiftMvpEffect")
$clientGameInfo = Join-Path $Cs2Root "game\csgo\gameinfo.gi"
$serverGameInfo = Join-Path $ServerRoot "game\csgo\gameinfo.gi"
$publishDll = Join-Path $publishDir "SwiftMvpEffect.dll"
$publishConfig = Join-Path $publishDir "mvp_effect.json"
$serverDll = Join-Path $serverPluginDir "SwiftMvpEffect.dll"
$serverConfig = Join-Path $serverPluginDir "mvp_effect.json"

foreach ($required in @(
        $localVpk,
        $serverVpk,
        $publishDll,
        $publishConfig,
        $serverDll,
        $serverConfig,
        $VpkEditCli)) {
    Assert-PathExists -Path $required -Description "Deployment artifact"
}

if (!(Test-GameInfoMount `
        -GameInfoPath $clientGameInfo `
        -AddonName $AddonName)) {
    throw "Client gameinfo.gi does not mount $AddonName."
}
if (!(Test-GameInfoMount `
        -GameInfoPath $serverGameInfo `
        -AddonName $AddonName)) {
    throw "Server gameinfo.gi does not mount $AddonName."
}
if (!(Test-GameInfoSwiftlyS2Priority -GameInfoPath $serverGameInfo)) {
    throw (
        "Server gameinfo.gi must place 'Game csgo/addons/swiftlys2' " +
        "before every override VPK.")
}

Assert-FileHashEqual `
    -ExpectedPath $localVpk `
    -ActualPath $serverVpk `
    -Description "Client/server override VPK"
Assert-FileHashEqual `
    -ExpectedPath $publishDll `
    -ActualPath $serverDll `
    -Description "Published/server plugin DLL"
Assert-FileHashEqual `
    -ExpectedPath $publishConfig `
    -ActualPath $serverConfig `
    -Description "Published/server plugin config"

foreach ($vpk in @($localVpk, $serverVpk)) {
    Assert-Cs2InlineVpkLayout -Path $vpk
    & $VpkEditCli --verify-checksums all $vpk
    if ($LASTEXITCODE -ne 0) {
        throw "VPK checksum verification failed: $vpk"
    }
}

$vpkHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $localVpk).Hash
$dllHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $publishDll).Hash
Write-Host "Deployment verification passed."
Write-Host "Client mount: $clientGameInfo"
Write-Host "Server mount: $serverGameInfo"
Write-Host "VPK SHA-256: $vpkHash"
Write-Host "DLL SHA-256: $dllHash"
