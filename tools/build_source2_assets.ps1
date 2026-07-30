param(
    [string]$Cs2Root = (
        "F:\Program Files (x86)\Steam\steamapps\common\Counter-Strike Global Offensive"),
    [string]$AddonName = "swift_mvp_effect",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($PSVersionTable.PSEdition -ne "Core" -or $PSVersionTable.PSVersion.Major -lt 7) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) {
        throw "PowerShell 7+ (pwsh) is required."
    }

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $PSCommandPath,
        "-Cs2Root", $Cs2Root,
        "-AddonName", $AddonName
    )
    if ($Force.IsPresent) {
        $arguments += "-Force"
    }
    & $pwsh.Source @arguments
    exit $LASTEXITCODE
}

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$resourceCompiler = Join-Path $Cs2Root "game\bin\win64\resourcecompiler.exe"
$gameDir = Join-Path $Cs2Root "game\csgo"
$contentAddonRoot = Join-Path $Cs2Root "content\csgo_addons\$AddonName"
$contentMaterialDir = Join-Path $contentAddonRoot "materials\swift_mvp_effect"
$contentParticleDir = Join-Path $contentAddonRoot "particles\swift_mvp_effect"
$gameAddonRoot = Join-Path $Cs2Root "game\csgo_addons\$AddonName"
$gameMaterialDir = Join-Path $gameAddonRoot "materials\swift_mvp_effect"
$gameParticleDir = Join-Path $gameAddonRoot "particles\swift_mvp_effect"
$sourceMaterialDir = Join-Path $projectRoot "resources_src\materials\swift_mvp_effect"
$sourceParticleDir = Join-Path $projectRoot "resources_src\particles\swift_mvp_effect"

if (!(Test-Path -LiteralPath $resourceCompiler -PathType Leaf)) {
    throw "resourcecompiler.exe not found: $resourceCompiler"
}

& (Join-Path $PSScriptRoot "generate_assets.ps1")

New-Item -ItemType Directory -Force -Path $contentMaterialDir | Out-Null
New-Item -ItemType Directory -Force -Path $contentParticleDir | Out-Null
foreach ($obsolete in @(
        (Join-Path $contentMaterialDir "mvp_animation_stage_1.mks"),
        (Join-Path $contentMaterialDir "mvp_animation_stage_2.mks"),
        (Join-Path $contentMaterialDir "mvp_animation_stage_3.mks"),
        (Join-Path $contentMaterialDir "mvp_animation_stage_4.mks"),
        (Join-Path $contentMaterialDir "mvp_animation_stage_1.vtex"),
        (Join-Path $contentMaterialDir "mvp_animation_stage_2.vtex"),
        (Join-Path $contentMaterialDir "mvp_animation_stage_3.vtex"),
        (Join-Path $contentMaterialDir "mvp_animation_stage_4.vtex"),
        (Join-Path $contentParticleDir "mvp_overlay_stage_1.vpcf"),
        (Join-Path $contentParticleDir "mvp_overlay_stage_2.vpcf"),
        (Join-Path $contentParticleDir "mvp_overlay_stage_3.vpcf"),
        (Join-Path $contentParticleDir "mvp_overlay_stage_4.vpcf"),
        (Join-Path $gameMaterialDir "mvp_animation_stage_1.vtex_c"),
        (Join-Path $gameMaterialDir "mvp_animation_stage_2.vtex_c"),
        (Join-Path $gameMaterialDir "mvp_animation_stage_3.vtex_c"),
        (Join-Path $gameMaterialDir "mvp_animation_stage_4.vtex_c"),
        (Join-Path $gameParticleDir "mvp_overlay_stage_1.vpcf_c"),
        (Join-Path $gameParticleDir "mvp_overlay_stage_2.vpcf_c"),
        (Join-Path $gameParticleDir "mvp_overlay_stage_3.vpcf_c"),
        (Join-Path $gameParticleDir "mvp_overlay_stage_4.vpcf_c"))) {
    if (Test-Path -LiteralPath $obsolete) {
        Remove-Item -LiteralPath $obsolete -Force
    }
}
foreach ($staleFrame in Get-ChildItem `
        -LiteralPath $contentMaterialDir `
        -File `
        -Filter "mvp_frame_*.png") {
    Remove-Item -LiteralPath $staleFrame.FullName -Force
}
Copy-Item -LiteralPath (Join-Path $sourceMaterialDir "mvp_emblem.png") `
    -Destination $contentMaterialDir -Force
Copy-Item -LiteralPath (Join-Path $sourceMaterialDir "mvp_emblem.vtex") `
    -Destination $contentMaterialDir -Force
Copy-Item -LiteralPath (Join-Path $sourceMaterialDir "mvp_animation_60f.mks") `
    -Destination $contentMaterialDir -Force
Copy-Item -LiteralPath (Join-Path $sourceMaterialDir "mvp_animation_60f.vtex") `
    -Destination $contentMaterialDir -Force
foreach ($frame in Get-ChildItem `
        -LiteralPath $sourceMaterialDir `
        -File `
        -Filter "mvp_frame_*.png") {
    Copy-Item -LiteralPath $frame.FullName `
        -Destination $contentMaterialDir `
        -Force
}
Copy-Item -LiteralPath (Join-Path $sourceParticleDir "mvp_overlay.vpcf") `
    -Destination $contentParticleDir -Force
Copy-Item -LiteralPath (Join-Path $sourceParticleDir "mvp_atlas_overlay.vpcf") `
    -Destination $contentParticleDir -Force
$inputs = @(
    (Join-Path $contentMaterialDir "mvp_emblem.vtex"),
    (Join-Path $contentMaterialDir "mvp_animation_60f.vtex"),
    (Join-Path $contentParticleDir "mvp_overlay.vpcf"),
    (Join-Path $contentParticleDir "mvp_atlas_overlay.vpcf")
)
$buildDir = Join-Path $projectRoot "build"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
$fileList = Join-Path $buildDir "source2_compile_inputs.txt"
[System.IO.File]::WriteAllLines(
    $fileList,
    [string[]]$inputs,
    [System.Text.UTF8Encoding]::new($false))

$compilerArguments = @(
    "-game", $gameDir,
    "-filelist", $fileList,
    "-nop4"
)
if ($Force.IsPresent) {
    $compilerArguments += "-f"
}

& $resourceCompiler @compilerArguments
if ($LASTEXITCODE -ne 0) {
    throw "resourcecompiler failed with exit code $LASTEXITCODE."
}

$compiledOutputs = @(
    (Join-Path $gameMaterialDir "mvp_emblem.vtex_c"),
    (Join-Path $gameMaterialDir "mvp_animation_60f.vtex_c"),
    (Join-Path $gameParticleDir "mvp_overlay.vpcf_c"),
    (Join-Path $gameParticleDir "mvp_atlas_overlay.vpcf_c")
)
foreach ($required in $compiledOutputs) {
    if (!(Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Compiled Source 2 output is missing: $required"
    }
}

Write-Host "Compiled MVP Source 2 assets:"
foreach ($compiledOutput in $compiledOutputs) {
    Write-Host "  $compiledOutput"
}
