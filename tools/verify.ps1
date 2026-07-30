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

$depthBiases = @("0.000000", "-1.000000", "-2.000000", "-3.000000")
$allMksFrameNames = [System.Collections.Generic.List[string]]::new()
for ($stage = 1; $stage -le 4; $stage++) {
    $mksPath = Join-Path $materialDir (
        "mvp_animation_stage_{0}.mks" -f $stage)
    $vtexPath = Join-Path $materialDir (
        "mvp_animation_stage_{0}.vtex" -f $stage)
    $vpcfPath = Join-Path $particleDir (
        "mvp_overlay_stage_{0}.vpcf" -f $stage)
    foreach ($required in @($mksPath, $vtexPath, $vpcfPath)) {
        if (!(Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Missing stage resource: $required"
        }
    }

    $mks = Get-Content -Raw -LiteralPath $mksPath
    $mksMatches = [regex]::Matches(
        $mks,
        '(?m)^frame (mvp_frame_[0-9]{3}\.png) ([12])$')
    if ($mksMatches.Count -ne 15) {
        throw "Stage $stage MKS must contain exactly 15 frame lines."
    }
    foreach ($match in $mksMatches) {
        $allMksFrameNames.Add($match.Groups[1].Value)
    }
    if ($mksMatches[14].Groups[2].Value -ne "2") {
        throw "Stage $stage must hold its final frame for one overlap tick."
    }

    $vtex = Get-Content -Raw -LiteralPath $vtexPath
    $vpcf = Get-Content -Raw -LiteralPath $vpcfPath
    $checks = [ordered]@{
        "Stage $stage VTEX references its MKS" =
            $vtex.Contains(
                "materials/swift_mvp_effect/mvp_animation_stage_$stage.mks")
        "Stage $stage VTEX preserves alpha" =
            $vtex.Contains('"m_outputFormat" "string" "DXT5"')
        "Stage $stage VTEX disables LOD" =
            $vtex.Contains('"m_bNoLod" "bool" "1"')
        "Stage $stage VPCF has overlay renderer" =
            $vpcf.Contains("m_bOnlyRenderInEffecsGameOverlay = true")
        "Stage $stage VPCF disables Z buffer" =
            $vpcf.Contains("m_bDisableZBuffering = true")
        "Stage $stage VPCF depth sort is explicit" =
            $vpcf.Contains(
                "m_flDepthSortBias = $($depthBiases[$stage - 1])")
        "Stage $stage VPCF fits animation to lifetime" =
            $vpcf.Contains(
                'm_nAnimationType = "ANIMATION_TYPE_FIT_LIFETIME"')
        "Stage $stage VPCF lifetime is 0.64 seconds" =
            $vpcf.Contains("m_flLiteralValue = 0.640000")
        "Stage $stage VPCF uses CP34 only" =
            ([regex]::Matches($vpcf, "m_nControlPoint = 34").Count -eq 3)
        "Stage $stage has no unresolved template token" =
            ![regex]::IsMatch(
                $vpcf + $vtex,
                '\{\{[A-Z0-9_]+\}\}')
    }
    foreach ($entry in $checks.GetEnumerator()) {
        if (!$entry.Value) {
            throw "Verification failed: $($entry.Key)"
        }
    }
}
if (($allMksFrameNames | Sort-Object -Unique).Count -ne 60) {
    throw "The four staged MKS files must reference all 60 frames exactly once."
}

$auditScript = Join-Path $PSScriptRoot "audit_overlay_vpcf.py"
if (Test-Path -LiteralPath $auditScript -PathType Leaf) {
    python $auditScript $particleDir `
        --root-pattern "mvp_overlay_stage_*.vpcf" `
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
