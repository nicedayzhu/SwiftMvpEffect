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
$vtexPath = Join-Path $materialDir "mvp_emblem.vtex"
$vpcfPath = Join-Path $particleDir "mvp_overlay.vpcf"
foreach ($required in @($emblemPath, $vtexPath, $vpcfPath)) {
    if (!(Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing transparent MVP emblem resource: $required"
    }
}

if (@(Get-ChildItem -LiteralPath $materialDir -File -Filter "mvp_frame_*.png").Count -ne 0) {
    throw "Legacy MVP frame sequences must not remain in the lightweight asset pack."
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

$vtex = Get-Content -Raw -LiteralPath $vtexPath
$vpcf = Get-Content -Raw -LiteralPath $vpcfPath
$assetManifest = Get-Content -Raw -LiteralPath (
    Join-Path $projectRoot "resources_src\asset_manifest.json") |
    ConvertFrom-Json
$rendererCount = [regex]::Matches(
    $vpcf,
    '_class = "C_OP_RenderSprites"').Count
$collectionAgeCount = [regex]::Matches(
    $vpcf,
    'm_nType = "PF_TYPE_COLLECTION_AGE"').Count
$checks = [ordered]@{
    "VTEX references the transparent emblem" =
        $vtex.Contains("materials/swift_mvp_effect/mvp_emblem.png")
    "VTEX preserves alpha without block compression" =
        $vtex.Contains('"m_outputFormat" "string" "RGBA8888"')
    "VTEX is a lightweight 1024 texture" =
        ($vtex.Contains('"m_nOutputMinDimension" "int" "1024"') -and
        $vtex.Contains('"m_nOutputMaxDimension" "int" "1024"'))
    "VTEX disables LOD" =
        $vtex.Contains('"m_bNoLod" "bool" "1"')
    "VPCF has overlay renderer" =
        $vpcf.Contains("m_bOnlyRenderInEffecsGameOverlay = true")
    "VPCF disables Z buffer" =
        $vpcf.Contains("m_bDisableZBuffering = true")
    "VPCF has explicit depth sort" =
        $vpcf.Contains("m_flDepthSortBias = 0.000000")
    "VPCF lifetime is 2.4 seconds" =
        $vpcf.Contains("m_flLiteralValue = 2.400000")
    "VPCF is a static sprite" =
        $vpcf.Contains('m_nAnimationType = "ANIMATION_TYPE_MANUAL_FRAMES"')
    "VPCF uses thirteen contiguous client motion segments" =
        ($rendererCount -eq 13 -and
        $assetManifest.motionSegmentCount -eq 13)
    "VPCF uses collection age for every motion field" =
        ($collectionAgeCount -eq ($rendererCount * 3) -and
        $assetManifest.motionClock -eq "PF_TYPE_COLLECTION_AGE")
    "VPCF never feeds particle age to collection renderer fields" =
        !$vpcf.Contains("PF_TYPE_PARTICLE_AGE")
    "VPCF enters from the left and exits to the right" =
        ($vpcf.Contains("m_flOutput0 = -1.120000") -and
        $vpcf.Contains("m_flOutput1 = 1.120000"))
    "VPCF has a positional overshoot and rebound" =
        ($vpcf.Contains("m_flOutput1 = 0.074000") -and
        $vpcf.Contains("m_flOutput0 = 0.074000") -and
        $vpcf.Contains("m_flOutput1 = 0.045000"))
    "VPCF locally scales the entry bounce and exit shrink" =
        ($vpcf.Contains("m_flOutput0 = 0.720000") -and
        $vpcf.Contains("m_flOutput1 = 1.019000") -and
        $vpcf.Contains("m_flOutput1 = 0.860000"))
    "VPCF holds at center from 0.52 to 1.62 seconds" =
        ($vpcf.Contains("m_flInput0 = 0.520000") -and
        $vpcf.Contains("m_flInput1 = 1.620000") -and
        $assetManifest.enterEndSeconds -eq 0.52 -and
        $assetManifest.centerHoldEndSeconds -eq 1.62)
    "VPCF fades locally" =
        ($vpcf.Contains('"C_OP_FadeInSimple"') -and
        $vpcf.Contains('"C_OP_FadeOutSimple"'))
    "VPCF uses CP34 only for fixed layout" =
        ([regex]::Matches($vpcf, "m_nControlPoint = 34").Count -eq
        ($rendererCount * 3))
    "VPCF has no runtime alpha control point" =
        ([regex]::Matches($vpcf, "m_nControlPoint = 17").Count -eq 0)
    "VPCF has no unresolved template token" =
        ![regex]::IsMatch($vpcf + $vtex, '\{\{[A-Z0-9_]+\}\}')
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
