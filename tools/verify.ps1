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

$frames = @(Get-ChildItem -LiteralPath $materialDir -File -Filter "mvp_frame_*.png")
if ($frames.Count -ne 60) {
    throw "Expected 60 generated frame PNGs, found $($frames.Count)."
}

$mksPath = Join-Path $materialDir "mvp_animation_60f.mks"
$vtexPath = Join-Path $materialDir "mvp_animation_60f.vtex"
$vpcfPath = Join-Path $particleDir "mvp_overlay.vpcf"
foreach ($required in @($mksPath, $vtexPath, $vpcfPath)) {
    if (!(Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing 60-frame animation resource: $required"
    }
}

$mks = Get-Content -Raw -LiteralPath $mksPath
$mksMatches = [regex]::Matches(
    $mks,
    '(?m)^frame (mvp_frame_[0-9]{3}\.png) 1$')
$mksFrameNames = @($mksMatches | ForEach-Object { $_.Groups[1].Value })
if ($mksMatches.Count -ne 60 -or
    @($mksFrameNames | Sort-Object -Unique).Count -ne 60) {
    throw "The single MKS must reference all 60 frames exactly once."
}

$vtex = Get-Content -Raw -LiteralPath $vtexPath
$vpcf = Get-Content -Raw -LiteralPath $vpcfPath
$checks = [ordered]@{
    "VTEX references the 60-frame MKS" =
        $vtex.Contains("materials/swift_mvp_effect/mvp_animation_60f.mks")
    "VTEX preserves alpha without block compression" =
        $vtex.Contains('"m_outputFormat" "string" "RGBA8888"')
    "VTEX forces a 4096 atlas" =
        ($vtex.Contains('"m_nOutputMinDimension" "int" "4096"') -and
        $vtex.Contains('"m_nOutputMaxDimension" "int" "4096"'))
    "VTEX disables LOD" =
        $vtex.Contains('"m_bNoLod" "bool" "1"')
    "VPCF has overlay renderer" =
        $vpcf.Contains("m_bOnlyRenderInEffecsGameOverlay = true")
    "VPCF disables Z buffer" =
        $vpcf.Contains("m_bDisableZBuffering = true")
    "VPCF has explicit depth sort" =
        $vpcf.Contains("m_flDepthSortBias = 0.000000")
    "VPCF fits animation to lifetime" =
        $vpcf.Contains('m_nAnimationType = "ANIMATION_TYPE_FIT_LIFETIME"')
    "VPCF explicitly plays at 25 FPS" =
        $vpcf.Contains("m_flAnimationRate = 25.000000")
    "VPCF lifetime is 2.4 seconds" =
        $vpcf.Contains("m_flLiteralValue = 2.400000")
    "VPCF uses CP34 transform" =
        ([regex]::Matches($vpcf, "m_nControlPoint = 34").Count -eq 3)
    "VPCF uses CP17 alpha" =
        (([regex]::Matches($vpcf, "m_nControlPoint = 17").Count -eq 1) -and
        $vpcf.Contains("m_nOutputField = 7"))
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
