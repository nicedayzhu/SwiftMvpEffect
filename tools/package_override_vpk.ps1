param(
    [string]$Cs2Root = (
        "F:\Program Files (x86)\Steam\steamapps\common\Counter-Strike Global Offensive"),
    [string]$AddonName = "swift_mvp_effect",
    [string]$VpkEditCli = (
        "F:\cs2dev\SkinTools\VPKEdit-Windows-Standalone-msvc-Release\vpkeditcli.exe"),
    [string]$OutputPath = "",
    [switch]$KeepStaging
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
        "-Cs2Root", $Cs2Root,
        "-AddonName", $AddonName,
        "-VpkEditCli", $VpkEditCli
    )
    if (![string]::IsNullOrWhiteSpace($OutputPath)) {
        $arguments += @("-OutputPath", $OutputPath)
    }
    if ($KeepStaging.IsPresent) {
        $arguments += "-KeepStaging"
    }
    & $pwsh.Source @arguments
    exit $LASTEXITCODE
}

. (Join-Path $PSScriptRoot "_deployment_common.ps1")

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $Cs2Root (
        "game\csgo\overrides\$AddonName.vpk")
}

$projectRoot = Resolve-FullPath (Join-Path $PSScriptRoot "..")
$compiledAddonRoot = Resolve-FullPath (
    Join-Path $Cs2Root "game\csgo_addons\$AddonName")
$outputFullPath = Resolve-FullPath $OutputPath
$outputParent = Split-Path -Parent $outputFullPath
$buildDir = Join-Path $projectRoot "build"
$tempParent = Resolve-FullPath ([System.IO.Path]::GetTempPath())
$stamp = Get-Date -Format "yyyyMMdd_HHmmss_ffff"
$stageLeaf = ".vpk_stage_swift_mvp_effect_$stamp"
$verifyLeaf = ".vpk_verify_swift_mvp_effect_$stamp"
$stageRoot = Join-Path $tempParent $stageLeaf
$verifyRoot = Join-Path $tempParent $verifyLeaf
$tempVpk = Join-Path $buildDir "$AddonName.$stamp.vpk"
$verificationContentRoot = Join-Path $verifyRoot (
    [System.IO.Path]::GetFileNameWithoutExtension($tempVpk))
$expectedEntries = Get-MvpExpectedVpkEntries

Assert-PathExists `
    -Path $compiledAddonRoot `
    -Description "Compiled MVP addon directory"
Assert-PathExists -Path $VpkEditCli -Description "VPKEdit CLI"
Assert-DirectoryMatchesEntries `
    -Root $compiledAddonRoot `
    -ExpectedEntries $expectedEntries `
    -Description "Compiled MVP addon"

try {
    New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $verifyRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

    foreach ($relativeEntry in $expectedEntries) {
        $source = Join-Path $compiledAddonRoot (
            $relativeEntry.Replace(
                '/',
                [System.IO.Path]::DirectorySeparatorChar))
        $destination = Join-Path $stageRoot (
            $relativeEntry.Replace(
                '/',
                [System.IO.Path]::DirectorySeparatorChar))
        $destinationParent = Split-Path -Parent $destination
        New-Item -ItemType Directory -Force -Path $destinationParent |
            Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
    Assert-DirectoryMatchesEntries `
        -Root $stageRoot `
        -ExpectedEntries $expectedEntries `
        -Description "VPK staging directory"

    Write-Host "Packing the eight compiled MVP resources..."
    & $VpkEditCli `
        --no-progress `
        --single-file `
        --gen-md5-entries `
        --output $tempVpk `
        $stageRoot
    if ($LASTEXITCODE -ne 0) {
        throw "VPKEdit pack failed with exit code $LASTEXITCODE."
    }

    & $VpkEditCli --verify-checksums all $tempVpk
    if ($LASTEXITCODE -ne 0) {
        throw "VPK checksum verification failed with exit code $LASTEXITCODE."
    }

    & $VpkEditCli `
        --no-progress `
        --extract "/" `
        --output $verifyRoot `
        $tempVpk
    if ($LASTEXITCODE -ne 0) {
        throw "VPK verification extraction failed with exit code $LASTEXITCODE."
    }
    Assert-PathExists `
        -Path $verificationContentRoot `
        -Description "Extracted VPK content directory"
    Assert-DirectoryMatchesEntries `
        -Root $verificationContentRoot `
        -ExpectedEntries $expectedEntries `
        -Description "Extracted MVP VPK"

    New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
    try {
        Copy-Item -LiteralPath $tempVpk -Destination $outputFullPath -Force
    }
    catch {
        throw (
            "Failed to replace the local override VPK. Stop CS2 if the VPK " +
            "is locked, then rerun. Original error: $($_.Exception.Message)")
    }
    Assert-FileHashEqual `
        -ExpectedPath $tempVpk `
        -ActualPath $outputFullPath `
        -Description "Local override VPK"

    $result = Get-Item -LiteralPath $outputFullPath
    $hash = (
        Get-FileHash -Algorithm SHA256 -LiteralPath $outputFullPath).Hash
    Write-Host "VPK ready: $($result.FullName)"
    Write-Host "Files: $($expectedEntries.Count)"
    Write-Host "Size: $($result.Length) bytes"
    Write-Host "SHA-256: $hash"
}
finally {
    if (!$KeepStaging.IsPresent) {
        foreach ($temporaryDirectory in @($stageRoot, $verifyRoot)) {
            if (Test-Path -LiteralPath $temporaryDirectory) {
                Assert-SafeChildPath `
                    -Path $temporaryDirectory `
                    -Parent $tempParent
                $leaf = Split-Path -Leaf $temporaryDirectory
                if (!$leaf.StartsWith(
                        ".vpk_",
                        [System.StringComparison]::OrdinalIgnoreCase) -or
                    !$leaf.Contains("swift_mvp_effect")) {
                    throw "Refusing to remove unexpected temp path: $temporaryDirectory"
                }
                Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
            }
        }
    }
    if (Test-Path -LiteralPath $tempVpk) {
        Assert-SafeChildPath -Path $tempVpk -Parent $buildDir
        Remove-Item -LiteralPath $tempVpk -Force
    }
}
