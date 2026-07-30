param(
    [switch]$SkipDotnet
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
        "-File", $PSCommandPath
    )
    if ($SkipDotnet.IsPresent) {
        $arguments += "-SkipDotnet"
    }
    & $pwsh.Source @arguments
    exit $LASTEXITCODE
}

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$materialDir = Join-Path $projectRoot "resources_src\materials\swift_mvp_effect"
$particleDir = Join-Path $projectRoot "resources_src\particles\swift_mvp_effect"

$scriptFiles = @(
    Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Filter "*.ps1")
foreach ($scriptFile in $scriptFiles) {
    $parseTokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptFile.FullName,
        [ref]$parseTokens,
        [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count -gt 0) {
        $messages = $parseErrors.Message -join "; "
        throw "PowerShell parse failed for $($scriptFile.FullName): $messages"
    }
}

& (Join-Path $PSScriptRoot "generate_assets.ps1")

$emblemPath = Join-Path $materialDir "mvp_emblem.png"
$emblemVtexPath = Join-Path $materialDir "mvp_emblem.vtex"
$emblemVpcfPath = Join-Path $particleDir "mvp_overlay.vpcf"
$atlasMksPath = Join-Path $materialDir "mvp_animation_60f.mks"
$atlasVtexPath = Join-Path $materialDir "mvp_animation_60f.vtex"
$atlasVpcfPath = Join-Path $particleDir "mvp_atlas_overlay.vpcf"
foreach ($required in @(
        $emblemPath,
        $emblemVtexPath,
        $emblemVpcfPath,
        $atlasMksPath,
        $atlasVtexPath,
        $atlasVpcfPath)) {
    if (!(Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing MVP resource: $required"
    }
}

$frames = @(
    Get-ChildItem `
        -LiteralPath $materialDir `
        -File `
        -Filter "mvp_frame_*.png" |
        Sort-Object Name)
if ($frames.Count -ne 60) {
    throw "Expected 60 generated atlas frame PNGs, found $($frames.Count)."
}

Add-Type -AssemblyName System.Drawing
$emblem = [System.Drawing.Bitmap]::new($emblemPath)
try {
    if ($emblem.Width -ne 1024 -or $emblem.Height -ne 1024) {
        throw "Expected a 1024x1024 transparent emblem carrier, got $($emblem.Width)x$($emblem.Height)."
    }
    if ($emblem.GetPixel(0, 0).A -ne 0 -or
        $emblem.GetPixel($emblem.Width - 1, $emblem.Height - 1).A -ne 0) {
        throw "MVP emblem carrier corners must be transparent."
    }
}
finally {
    $emblem.Dispose()
}

foreach ($frame in $frames) {
    $atlasFrame = [System.Drawing.Bitmap]::new($frame.FullName)
    try {
        if ($atlasFrame.Width -ne 512 -or $atlasFrame.Height -ne 512) {
            throw (
                "Expected a 512x512 atlas carrier, got " +
                "$($atlasFrame.Width)x$($atlasFrame.Height): $($frame.Name)")
        }
        if ($atlasFrame.GetPixel(0, 0).A -ne 0 -or
            $atlasFrame.GetPixel(
                $atlasFrame.Width - 1,
                $atlasFrame.Height - 1).A -ne 0) {
            throw "Atlas carrier corners must be transparent: $($frame.Name)"
        }
    }
    finally {
        $atlasFrame.Dispose()
    }
}

$atlasMks = Get-Content -Raw -LiteralPath $atlasMksPath
$mksMatches = [regex]::Matches(
    $atlasMks,
    '(?m)^frame (mvp_frame_[0-9]{3}\.png) 1$')
$mksFrameNames = @(
    $mksMatches | ForEach-Object { $_.Groups[1].Value })
if ($mksMatches.Count -ne 60 -or
    @($mksFrameNames | Sort-Object -Unique).Count -ne 60) {
    throw "The atlas MKS must reference all 60 frames exactly once."
}

$emblemVtex = Get-Content -Raw -LiteralPath $emblemVtexPath
$emblemVpcf = Get-Content -Raw -LiteralPath $emblemVpcfPath
$atlasVtex = Get-Content -Raw -LiteralPath $atlasVtexPath
$atlasVpcf = Get-Content -Raw -LiteralPath $atlasVpcfPath
$assetManifest = Get-Content -Raw -LiteralPath (
    Join-Path $projectRoot "resources_src\asset_manifest.json") |
    ConvertFrom-Json
$emblemRendererCount = [regex]::Matches(
    $emblemVpcf,
    '_class = "C_OP_RenderSprites"').Count
$emblemCollectionAgeCount = [regex]::Matches(
    $emblemVpcf,
    'm_nType = "PF_TYPE_COLLECTION_AGE"').Count
$atlasRendererCount = [regex]::Matches(
    $atlasVpcf,
    '_class = "C_OP_RenderSprites"').Count
$atlasCollectionAgeCount = [regex]::Matches(
    $atlasVpcf,
    'm_nType = "PF_TYPE_COLLECTION_AGE"').Count
$pluginSource = Get-Content -Raw -LiteralPath (
    Join-Path $projectRoot "src\SwiftMvpEffectPlugin.cs")
$checks = [ordered]@{
    "Emblem VTEX references the transparent source" =
        $emblemVtex.Contains("materials/swift_mvp_effect/mvp_emblem.png")
    "Emblem VTEX is lossless 1024 RGBA with LOD disabled" =
        ($emblemVtex.Contains('"m_outputFormat" "string" "RGBA8888"') -and
        $emblemVtex.Contains('"m_nOutputMinDimension" "int" "1024"') -and
        $emblemVtex.Contains('"m_nOutputMaxDimension" "int" "1024"') -and
        $emblemVtex.Contains('"m_bNoLod" "bool" "1"'))
    "Atlas VTEX references the 60-frame MKS" =
        $atlasVtex.Contains(
            "materials/swift_mvp_effect/mvp_animation_60f.mks")
    "Atlas VTEX is lossless 4096 RGBA with LOD disabled" =
        ($atlasVtex.Contains('"m_outputFormat" "string" "RGBA8888"') -and
        $atlasVtex.Contains('"m_nOutputMinDimension" "int" "4096"') -and
        $atlasVtex.Contains('"m_nOutputMaxDimension" "int" "4096"') -and
        $atlasVtex.Contains('"m_bNoLod" "bool" "1"'))
    "Both VPCFs use overlay rendering without Z buffer" =
        ($emblemVpcf.Contains("m_bOnlyRenderInEffecsGameOverlay = true") -and
        $atlasVpcf.Contains("m_bOnlyRenderInEffecsGameOverlay = true") -and
        $emblemVpcf.Contains("m_bDisableZBuffering = true") -and
        $atlasVpcf.Contains("m_bDisableZBuffering = true"))
    "Both VPCFs have explicit depth sort and 2.4 second lifetime" =
        ($emblemVpcf.Contains("m_flDepthSortBias = 0.000000") -and
        $atlasVpcf.Contains("m_flDepthSortBias = 0.000000") -and
        $emblemVpcf.Contains("m_flLiteralValue = 2.400000") -and
        $atlasVpcf.Contains("m_flLiteralValue = 2.400000"))
    "Emblem VPCF uses manual static frames" =
        $emblemVpcf.Contains(
            'm_nAnimationType = "ANIMATION_TYPE_MANUAL_FRAMES"')
    "Atlas VPCF fits the 60-frame sequence to lifetime at 25 FPS" =
        ($atlasVpcf.Contains(
            'm_nAnimationType = "ANIMATION_TYPE_FIT_LIFETIME"') -and
        $atlasVpcf.Contains("m_flAnimationRate = 25.000000") -and
        $atlasVpcf.Contains("m_bAnimateInFPS = true"))
    "Both VPCFs use thirteen contiguous client motion segments" =
        ($emblemRendererCount -eq 13 -and
        $atlasRendererCount -eq 13 -and
        $assetManifest.motionSegmentCount -eq 13)
    "Both VPCFs use collection age for every motion field" =
        ($emblemCollectionAgeCount -eq ($emblemRendererCount * 3) -and
        $atlasCollectionAgeCount -eq ($atlasRendererCount * 3) -and
        $assetManifest.motionClock -eq "PF_TYPE_COLLECTION_AGE")
    "Neither VPCF feeds particle age to collection renderer fields" =
        (!$emblemVpcf.Contains("PF_TYPE_PARTICLE_AGE") -and
        !$atlasVpcf.Contains("PF_TYPE_PARTICLE_AGE"))
    "Both VPCFs enter left, overshoot, hold, and exit right" =
        ($emblemVpcf.Contains("m_flOutput0 = -1.120000") -and
        $atlasVpcf.Contains("m_flOutput0 = -1.120000") -and
        $emblemVpcf.Contains("m_flOutput1 = 1.120000") -and
        $atlasVpcf.Contains("m_flOutput1 = 1.120000") -and
        $emblemVpcf.Contains("m_flOutput1 = 0.074000") -and
        $atlasVpcf.Contains("m_flOutput1 = 0.074000") -and
        $emblemVpcf.Contains("m_flInput0 = 0.520000") -and
        $atlasVpcf.Contains("m_flInput0 = 0.520000") -and
        $emblemVpcf.Contains("m_flInput1 = 1.620000") -and
        $atlasVpcf.Contains("m_flInput1 = 1.620000") -and
        $assetManifest.enterEndSeconds -eq 0.52 -and
        $assetManifest.centerHoldEndSeconds -eq 1.62)
    "Both VPCFs fade locally" =
        ($emblemVpcf.Contains('"C_OP_FadeInSimple"') -and
        $emblemVpcf.Contains('"C_OP_FadeOutSimple"') -and
        $atlasVpcf.Contains('"C_OP_FadeInSimple"') -and
        $atlasVpcf.Contains('"C_OP_FadeOutSimple"'))
    "Both VPCFs use CP34 only for fixed layout" =
        (([regex]::Matches(
            $emblemVpcf,
            "m_nControlPoint = 34").Count -eq
            ($emblemRendererCount * 3)) -and
        ([regex]::Matches(
            $atlasVpcf,
            "m_nControlPoint = 34").Count -eq
            ($atlasRendererCount * 3)))
    "Both VPCFs have no runtime sequence or alpha CP" =
        (([regex]::Matches(
            $emblemVpcf,
            "m_nControlPoint = 17").Count -eq 0) -and
        ([regex]::Matches(
            $atlasVpcf,
            "m_nControlPoint = 17").Count -eq 0))
    "Generated resources have no unresolved template token" =
        ![regex]::IsMatch(
            $emblemVpcf + $atlasVpcf + $emblemVtex + $atlasVtex,
            '\{\{[A-Z0-9_]+\}\}')
    "Manifest preserves both runtime variants" =
        ($assetManifest.atlasFrameCount -eq 60 -and
        $assetManifest.atlasFramesPerSecond -eq 25 -and
        @($assetManifest.particles).Count -eq 2 -and
        @($assetManifest.textures).Count -eq 2)
    "Plugin exposes and precaches the atlas test effect" =
        ($pluginSource.Contains('"swift_mvp_test_atlas"') -and
        $pluginSource.Contains(
            '"particles/swift_mvp_effect/mvp_atlas_overlay.vpcf"') -and
        $pluginSource.Contains("@event.AddItem(AtlasEffectParticle)"))
}
foreach ($entry in $checks.GetEnumerator()) {
    if (!$entry.Value) {
        throw "Verification failed: $($entry.Key)"
    }
}

$auditScript = Join-Path $PSScriptRoot "audit_overlay_vpcf.py"
if (Test-Path -LiteralPath $auditScript -PathType Leaf) {
    python $auditScript $particleDir `
        --root-pattern "mvp_overlay.vpcf" `
        --root-pattern "mvp_atlas_overlay.vpcf" `
        --strict
    if ($LASTEXITCODE -ne 0) {
        throw "Overlay VPCF audit failed with exit code $LASTEXITCODE."
    }
}

if (!$SkipDotnet.IsPresent) {
    dotnet build (Join-Path $projectRoot "SwiftMvpEffect.csproj") `
        --no-restore `
        -c Release
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed with exit code $LASTEXITCODE."
    }
}

Write-Host "SwiftMvpEffect verification passed."
