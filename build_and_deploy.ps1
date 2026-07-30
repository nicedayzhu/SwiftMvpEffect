param(
    [string]$ServerRoot = "F:\csgoserver_win\cs2",
    [string]$Cs2Root = (
        "F:\Program Files (x86)\Steam\steamapps\common\Counter-Strike Global Offensive"),
    [string]$AddonName = "swift_mvp_effect",
    [string]$VpkEditCli = (
        "F:\cs2dev\SkinTools\VPKEdit-Windows-Standalone-msvc-Release\vpkeditcli.exe"),
    [switch]$ForceAssetRebuild,
    [switch]$SkipAssetBuild,
    [switch]$SkipClientMount,
    [switch]$SkipServerMount
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($PSVersionTable.PSEdition -ne "Core" -or
    $PSVersionTable.PSVersion.Major -lt 7) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) {
        throw "PowerShell 7+ (pwsh) is required."
    }

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $PSCommandPath,
        "-ServerRoot", $ServerRoot,
        "-Cs2Root", $Cs2Root,
        "-AddonName", $AddonName,
        "-VpkEditCli", $VpkEditCli
    )
    if ($ForceAssetRebuild.IsPresent) {
        $arguments += "-ForceAssetRebuild"
    }
    if ($SkipAssetBuild.IsPresent) {
        $arguments += "-SkipAssetBuild"
    }
    if ($SkipClientMount.IsPresent) {
        $arguments += "-SkipClientMount"
    }
    if ($SkipServerMount.IsPresent) {
        $arguments += "-SkipServerMount"
    }
    & $pwsh.Source @arguments
    exit $LASTEXITCODE
}

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $projectRoot "tools\_deployment_common.ps1")

$pluginName = "SwiftMvpEffect"
$publishDir = Join-Path $projectRoot "build\publish\$pluginName"
$localVpk = Join-Path $Cs2Root "game\csgo\overrides\$AddonName.vpk"
$serverVpk = Join-Path $ServerRoot "game\csgo\overrides\$AddonName.vpk"
$pluginParent = Join-Path $ServerRoot (
    "game\csgo\addons\swiftlys2\plugins")
$serverPluginDir = Join-Path $pluginParent $pluginName
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$stagePluginDir = Join-Path $pluginParent ".$pluginName.deploy.$stamp"
$backupPluginDir = Join-Path $pluginParent ".$pluginName.backup.$stamp"

Assert-PathExists -Path $VpkEditCli -Description "VPKEdit CLI"
Assert-PathExists `
    -Path (Join-Path $Cs2Root "game\csgo\gameinfo.gi") `
    -Description "Client gameinfo.gi"
Assert-PathExists `
    -Path (Join-Path $ServerRoot "game\csgo\gameinfo.gi") `
    -Description "Server gameinfo.gi"
Assert-PathExists -Path $pluginParent -Description "SwiftlyS2 plugin directory"

Push-Location $projectRoot
try {
    dotnet restore ".\SwiftMvpEffect.csproj" --ignore-failed-sources
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet restore failed with exit code $LASTEXITCODE."
    }

    & ".\tools\verify.ps1"

    dotnet publish ".\SwiftMvpEffect.csproj" `
        --no-restore `
        -c Release
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed with exit code $LASTEXITCODE."
    }
    Assert-PathExists -Path $publishDir -Description "Plugin publish output"

    if (!$SkipAssetBuild.IsPresent) {
        $assetArguments = @{
            Cs2Root = $Cs2Root
            AddonName = $AddonName
        }
        if ($ForceAssetRebuild.IsPresent) {
            $assetArguments["Force"] = $true
        }
        & ".\tools\build_source2_assets.ps1" @assetArguments
    }

    & ".\tools\package_override_vpk.ps1" `
        -Cs2Root $Cs2Root `
        -AddonName $AddonName `
        -VpkEditCli $VpkEditCli
    Assert-PathExists -Path $localVpk -Description "Local override VPK"

    $serverVpkParent = Split-Path -Parent $serverVpk
    New-Item -ItemType Directory -Force -Path $serverVpkParent | Out-Null
    try {
        Copy-Item -LiteralPath $localVpk -Destination $serverVpk -Force
    }
    catch {
        throw (
            "Failed to install the server VPK. Stop the dedicated server if " +
            "the VPK is locked, then rerun. Original error: " +
            $_.Exception.Message)
    }
    Assert-FileHashEqual `
        -ExpectedPath $localVpk `
        -ActualPath $serverVpk `
        -Description "Client/server override VPK"

    if (!$SkipClientMount.IsPresent) {
        & ".\tools\install_gameinfo_override.ps1" `
            -Cs2Root $Cs2Root `
            -AddonName $AddonName `
            -Action Install
    }
    if (!$SkipServerMount.IsPresent) {
        & ".\tools\install_gameinfo_override.ps1" `
            -Cs2Root $ServerRoot `
            -AddonName $AddonName `
            -PrioritizeSwiftlyS2 `
            -Action Install
    }

    Assert-SafeChildPath -Path $stagePluginDir -Parent $pluginParent
    Assert-SafeChildPath -Path $backupPluginDir -Parent $pluginParent
    Assert-SafeChildPath `
        -Path $serverPluginDir `
        -Parent $pluginParent `
        -ExpectedLeaf $pluginName

    New-Item -ItemType Directory -Force -Path $stagePluginDir | Out-Null
    Copy-Item -Path (Join-Path $publishDir "*") `
        -Destination $stagePluginDir `
        -Recurse `
        -Force

    $hadPreviousPlugin = Test-Path `
        -LiteralPath $serverPluginDir `
        -PathType Container
    try {
        if ($hadPreviousPlugin) {
            Move-Item `
                -LiteralPath $serverPluginDir `
                -Destination $backupPluginDir
        }
        Move-Item `
            -LiteralPath $stagePluginDir `
            -Destination $serverPluginDir

        Assert-FileHashEqual `
            -ExpectedPath (Join-Path $publishDir "SwiftMvpEffect.dll") `
            -ActualPath (Join-Path $serverPluginDir "SwiftMvpEffect.dll") `
            -Description "Published/server plugin DLL"
        Assert-FileHashEqual `
            -ExpectedPath (Join-Path $publishDir "mvp_effect.json") `
            -ActualPath (Join-Path $serverPluginDir "mvp_effect.json") `
            -Description "Published/server plugin config"
    }
    catch {
        if (Test-Path -LiteralPath $serverPluginDir) {
            Remove-Item -LiteralPath $serverPluginDir -Recurse -Force
        }
        if ($hadPreviousPlugin -and
            (Test-Path -LiteralPath $backupPluginDir)) {
            Move-Item `
                -LiteralPath $backupPluginDir `
                -Destination $serverPluginDir
        }
        throw
    }

    if (Test-Path -LiteralPath $backupPluginDir) {
        Remove-Item -LiteralPath $backupPluginDir -Recurse -Force
    }

    if (!$SkipClientMount.IsPresent -and !$SkipServerMount.IsPresent) {
        & ".\tools\verify_deployment.ps1" `
            -ServerRoot $ServerRoot `
            -Cs2Root $Cs2Root `
            -AddonName $AddonName `
            -VpkEditCli $VpkEditCli
    }

    Write-Host ""
    Write-Host "SwiftMvpEffect test deployment is complete."
    Write-Host "Restart both CS2 client and dedicated server."
    Write-Host "Then run: swift_mvp_test"
}
finally {
    if (Test-Path -LiteralPath $stagePluginDir) {
        Assert-SafeChildPath -Path $stagePluginDir -Parent $pluginParent
        Remove-Item -LiteralPath $stagePluginDir -Recurse -Force
    }
    Pop-Location
}
