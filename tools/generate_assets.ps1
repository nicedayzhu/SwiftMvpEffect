param(
    [string]$SourceImage = (
        Join-Path $PSScriptRoot "..\assets\generated\mvp_emblem_transparent.png"),
    [int]$CanvasSize = 1024
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($PSVersionTable.PSEdition -ne "Core" -or $PSVersionTable.PSVersion.Major -lt 7) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) {
        throw "PowerShell 7+ (pwsh) is required."
    }

    & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath `
        -SourceImage $SourceImage -CanvasSize $CanvasSize
    exit $LASTEXITCODE
}

Add-Type -AssemblyName System.Drawing

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$sourceImagePath = [System.IO.Path]::GetFullPath($SourceImage)
$materialDir = Join-Path $projectRoot "resources_src\materials\swift_mvp_effect"
$particleDir = Join-Path $projectRoot "resources_src\particles\swift_mvp_effect"
$templateDir = Join-Path $PSScriptRoot "templates"

if (!(Test-Path -LiteralPath $sourceImagePath -PathType Leaf)) {
    throw "Transparent MVP source image not found: $sourceImagePath"
}
if ($CanvasSize -lt 256 -or $CanvasSize -gt 1024) {
    throw "CanvasSize must be between 256 and 1024."
}

New-Item -ItemType Directory -Force -Path $materialDir | Out-Null
New-Item -ItemType Directory -Force -Path $particleDir | Out-Null

function Save-BytesIfChanged {
    param(
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        $existing = [System.IO.File]::ReadAllBytes($Path)
        $same = $existing.Length -eq $Bytes.Length
        for ($index = 0; $same -and $index -lt $Bytes.Length; $index++) {
            if ($existing[$index] -ne $Bytes[$index]) {
                $same = $false
            }
        }
        if ($same) {
            return
        }
    }
    [System.IO.File]::WriteAllBytes($Path, $Bytes)
}

function Save-TextIfChanged {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Path
    )

    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($normalized)
    Save-BytesIfChanged -Bytes $bytes -Path $Path
}

$source = [System.Drawing.Bitmap]::new($sourceImagePath)
try {
    $sourceWidth = $source.Width
    $sourceHeight = $source.Height
    $minX = $sourceWidth
    $minY = $sourceHeight
    $maxX = -1
    $maxY = -1
    for ($y = 0; $y -lt $sourceHeight; $y += 4) {
        for ($x = 0; $x -lt $sourceWidth; $x += 4) {
            if ($source.GetPixel($x, $y).A -gt 16) {
                $minX = [Math]::Min($minX, $x)
                $minY = [Math]::Min($minY, $y)
                $maxX = [Math]::Max($maxX, $x)
                $maxY = [Math]::Max($maxY, $y)
            }
        }
    }
    if ($maxX -lt $minX -or $maxY -lt $minY) {
        throw "Transparent MVP source image does not contain visible pixels."
    }

    $padding = 12
    $minX = [Math]::Max(0, $minX - $padding)
    $minY = [Math]::Max(0, $minY - $padding)
    $maxX = [Math]::Min($sourceWidth - 1, $maxX + $padding)
    $maxY = [Math]::Min($sourceHeight - 1, $maxY + $padding)
    $cropWidth = $maxX - $minX + 1
    $cropHeight = $maxY - $minY + 1
    $scale = [Math]::Min(
        ($CanvasSize * 0.90) / $cropWidth,
        ($CanvasSize * 0.46) / $cropHeight)
    $targetWidth = [Math]::Max(1, [int][Math]::Round($cropWidth * $scale))
    $targetHeight = [Math]::Max(1, [int][Math]::Round($cropHeight * $scale))
    $targetX = [int][Math]::Floor(($CanvasSize - $targetWidth) / 2.0)
    $targetY = [int][Math]::Floor(($CanvasSize - $targetHeight) / 2.0)

    $carrier = [System.Drawing.Bitmap]::new(
        $CanvasSize,
        $CanvasSize,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($carrier)
        try {
            $graphics.Clear([System.Drawing.Color]::Transparent)
            $graphics.CompositingMode =
                [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.CompositingQuality =
                [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode =
                [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode =
                [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.DrawImage(
                $source,
                [System.Drawing.Rectangle]::new($targetX, $targetY, $targetWidth, $targetHeight),
                $minX,
                $minY,
                $cropWidth,
                $cropHeight,
                [System.Drawing.GraphicsUnit]::Pixel)
        }
        finally {
            $graphics.Dispose()
        }

        $memory = [System.IO.MemoryStream]::new()
        try {
            $carrier.Save($memory, [System.Drawing.Imaging.ImageFormat]::Png)
            Save-BytesIfChanged `
                -Bytes $memory.ToArray() `
                -Path (Join-Path $materialDir "mvp_emblem.png")
        }
        finally {
            $memory.Dispose()
        }
    }
    finally {
        $carrier.Dispose()
    }
}
finally {
    $source.Dispose()
}

$vtexTemplate = Get-Content -Raw -LiteralPath (
    Join-Path $templateDir "mvp_emblem.vtex.tmpl")
$vpcfTemplate = Get-Content -Raw -LiteralPath (
    Join-Path $templateDir "mvp_overlay.vpcf.tmpl")

$motionSegments = @(
    [pscustomobject]@{
        Name = "enter-fast"
        Start = 0.000
        End = 0.094
        OffsetFrom = -1.120
        OffsetTo = -0.441
        ScaleFrom = 0.720
        ScaleTo = 0.890
    },
    [pscustomobject]@{
        Name = "enter-ease"
        Start = 0.094
        End = 0.187
        OffsetFrom = -0.441
        OffsetTo = -0.067
        ScaleFrom = 0.890
        ScaleTo = 0.983
    },
    [pscustomobject]@{
        Name = "enter-overshoot"
        Start = 0.187
        End = 0.286
        OffsetFrom = -0.067
        OffsetTo = 0.067
        ScaleFrom = 0.983
        ScaleTo = 1.017
    },
    [pscustomobject]@{
        Name = "enter-overshoot-peak"
        Start = 0.286
        End = 0.321
        OffsetFrom = 0.067
        OffsetTo = 0.074
        ScaleFrom = 1.017
        ScaleTo = 1.019
    },
    [pscustomobject]@{
        Name = "enter-rebound"
        Start = 0.321
        End = 0.406
        OffsetFrom = 0.074
        OffsetTo = 0.045
        ScaleFrom = 1.019
        ScaleTo = 1.011
    },
    [pscustomobject]@{
        Name = "enter-settle"
        Start = 0.406
        End = 0.520
        OffsetFrom = 0.045
        OffsetTo = 0.000
        ScaleFrom = 1.011
        ScaleTo = 1.000
    },
    [pscustomobject]@{
        Name = "center-hold"
        Start = 0.520
        End = 1.620
        OffsetFrom = 0.000
        OffsetTo = 0.000
        ScaleFrom = 1.000
        ScaleTo = 1.000
    },
    [pscustomobject]@{
        Name = "exit-start"
        Start = 1.620
        End = 1.744
        OffsetFrom = 0.000
        OffsetTo = 0.009
        ScaleFrom = 1.000
        ScaleTo = 0.999
    },
    [pscustomobject]@{
        Name = "exit-accelerate-1"
        Start = 1.744
        End = 1.868
        OffsetFrom = 0.009
        OffsetTo = 0.072
        ScaleFrom = 0.999
        ScaleTo = 0.991
    },
    [pscustomobject]@{
        Name = "exit-accelerate-2"
        Start = 1.868
        End = 1.992
        OffsetFrom = 0.072
        OffsetTo = 0.242
        ScaleFrom = 0.991
        ScaleTo = 0.970
    },
    [pscustomobject]@{
        Name = "exit-fast-1"
        Start = 1.992
        End = 2.116
        OffsetFrom = 0.242
        OffsetTo = 0.573
        ScaleFrom = 0.970
        ScaleTo = 0.928
    },
    [pscustomobject]@{
        Name = "exit-fast-2"
        Start = 2.116
        End = 2.240
        OffsetFrom = 0.573
        OffsetTo = 1.120
        ScaleFrom = 0.928
        ScaleTo = 0.860
    },
    [pscustomobject]@{
        Name = "offscreen-fade-tail"
        Start = 2.240
        End = 2.400
        OffsetFrom = 1.120
        OffsetTo = 1.120
        ScaleFrom = 0.860
        ScaleTo = 0.860
    }
)

for ($index = 0; $index -lt $motionSegments.Count; $index++) {
    $segment = $motionSegments[$index]
    if ($segment.End -le $segment.Start) {
        throw "Motion segment '$($segment.Name)' must have a positive duration."
    }
    if ($index -gt 0) {
        $previous = $motionSegments[$index - 1]
        if ([Math]::Abs($previous.End - $segment.Start) -gt 0.000001) {
            throw "Motion segments '$($previous.Name)' and '$($segment.Name)' are not contiguous."
        }
        if ([Math]::Abs($previous.OffsetTo - $segment.OffsetFrom) -gt 0.000001) {
            throw "Motion offsets are discontinuous at '$($segment.Name)'."
        }
        if ([Math]::Abs($previous.ScaleTo - $segment.ScaleFrom) -gt 0.000001) {
            throw "Motion scales are discontinuous at '$($segment.Name)'."
        }
    }
}
if ([Math]::Abs($motionSegments[0].Start) -gt 0.000001 -or
    [Math]::Abs($motionSegments[-1].End - 2.400) -gt 0.000001) {
    throw "Motion segments must cover the complete 2.4 second VPCF lifetime."
}

$invariant = [System.Globalization.CultureInfo]::InvariantCulture
$motionRendererBlocks = @()
for ($index = 0; $index -lt $motionSegments.Count; $index++) {
    $segment = $motionSegments[$index]
    $gateEnd = if ($index -lt $motionSegments.Count - 1) {
        $segment.End - 0.0001
    }
    else {
        $segment.End
    }
    $startText = $segment.Start.ToString("0.000000", $invariant)
    $endText = $segment.End.ToString("0.000000", $invariant)
    $gateEndText = $gateEnd.ToString("0.000000", $invariant)
    $offsetFromText = $segment.OffsetFrom.ToString("0.000000", $invariant)
    $offsetToText = $segment.OffsetTo.ToString("0.000000", $invariant)
    $scaleFromText = $segment.ScaleFrom.ToString("0.000000", $invariant)
    $scaleToText = $segment.ScaleTo.ToString("0.000000", $invariant)
    $motionRendererBlocks += @"
		{
			_class = "C_OP_RenderSprites"
			m_vecTexturesInput =
			[
				{
					m_hTexture = resource:"materials/swift_mvp_effect/mvp_emblem.vtex"
				},
			]
			m_flSelfIllumAmount =
			{
				m_nType = "PF_TYPE_LITERAL"
				m_flLiteralValue = 1.000000
			}
			m_flAlphaScale =
			{
				m_nType = "PF_TYPE_COLLECTION_AGE"
				m_nMapType = "PF_MAP_TYPE_NOTCHED"
				m_flNotchedRangeMin = $startText
				m_flNotchedRangeMax = $gateEndText
				m_flNotchedOutputOutside = 0.000000
				m_flNotchedOutputInside = 1.000000
			}
			m_flRadiusScale =
			{
				m_nType = "PF_TYPE_COLLECTION_AGE"
				m_nMapType = "PF_MAP_TYPE_REMAP"
				m_nInputMode = "PF_INPUT_MODE_CLAMPED"
				m_flInput0 = $startText
				m_flInput1 = $endText
				m_flOutput0 = $scaleFromText
				m_flOutput1 = $scaleToText
			}
			m_bOnlyRenderInEffecsGameOverlay = true
			m_flMinSize =
			{
				m_nType = "PF_TYPE_CONTROL_POINT_COMPONENT"
				m_nControlPoint = 34
				m_nVectorComponent = 0
			}
			m_flMaxSize =
			{
				m_nType = "PF_TYPE_CONTROL_POINT_COMPONENT"
				m_nControlPoint = 34
				m_nVectorComponent = 0
			}
			m_nFogType = "PARTICLE_FOG_DISABLED"
			m_bDisableZBuffering = true
			m_nAnimationType = "ANIMATION_TYPE_MANUAL_FRAMES"
			m_flCenterXOffset =
			{
				m_nType = "PF_TYPE_COLLECTION_AGE"
				m_nMapType = "PF_MAP_TYPE_REMAP"
				m_nInputMode = "PF_INPUT_MODE_CLAMPED"
				m_flInput0 = $startText
				m_flInput1 = $endText
				m_flOutput0 = $offsetFromText
				m_flOutput1 = $offsetToText
			}
			m_flCenterYOffset =
			{
				m_nType = "PF_TYPE_CONTROL_POINT_COMPONENT"
				m_nMapType = "PF_MAP_TYPE_REMAP"
				m_nControlPoint = 34
				m_nVectorComponent = 2
				m_flInput0 = -1.000000
				m_flInput1 = 1.000000
				m_flOutput0 = -1.000000
				m_flOutput1 = 1.000000
			}
			m_flDepthBias =
			{
				m_nType = "PF_TYPE_LITERAL"
				m_flLiteralValue = 0.000000
			}
		},
"@
}
$vpcfTemplate = $vpcfTemplate.Replace(
    "{{MOTION_RENDERERS}}",
    $motionRendererBlocks -join "")
if ($vpcfTemplate.Contains("{{MOTION_RENDERERS}}")) {
    throw "Failed to expand the VPCF motion renderer template."
}

Save-TextIfChanged `
    -Text $vtexTemplate `
    -Path (Join-Path $materialDir "mvp_emblem.vtex")
Save-TextIfChanged `
    -Text $vpcfTemplate `
    -Path (Join-Path $particleDir "mvp_overlay.vpcf")

foreach ($obsolete in @(
        (Join-Path $materialDir "mvp_animation_stage_1.mks"),
        (Join-Path $materialDir "mvp_animation_stage_2.mks"),
        (Join-Path $materialDir "mvp_animation_stage_3.mks"),
        (Join-Path $materialDir "mvp_animation_stage_4.mks"),
        (Join-Path $materialDir "mvp_animation_stage_1.vtex"),
        (Join-Path $materialDir "mvp_animation_stage_2.vtex"),
        (Join-Path $materialDir "mvp_animation_stage_3.vtex"),
        (Join-Path $materialDir "mvp_animation_stage_4.vtex"),
        (Join-Path $materialDir "mvp_animation_60f.mks"),
        (Join-Path $materialDir "mvp_animation_60f.vtex"),
        (Join-Path $particleDir "mvp_overlay_stage_1.vpcf"),
        (Join-Path $particleDir "mvp_overlay_stage_2.vpcf"),
        (Join-Path $particleDir "mvp_overlay_stage_3.vpcf"),
        (Join-Path $particleDir "mvp_overlay_stage_4.vpcf"))) {
    if (Test-Path -LiteralPath $obsolete) {
        Remove-Item -LiteralPath $obsolete -Force
    }
}
foreach ($staleFrame in Get-ChildItem -LiteralPath $materialDir -File -Filter "mvp_frame_*.png") {
    Remove-Item -LiteralPath $staleFrame.FullName -Force
}

$manifest = [ordered]@{
    schemaVersion = 1
    sourceImage = [System.IO.Path]::GetFileName($sourceImagePath)
    sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceImagePath).Hash.ToLowerInvariant()
    sourceFrameWidth = $sourceWidth
    sourceFrameHeight = $sourceHeight
    frameCount = 1
    framesPerSecond = 0
    durationSeconds = 2.4
    rootCount = 1
    framesPerRoot = 1
    rootLifetimeSeconds = 2.4
    motionClock = "PF_TYPE_COLLECTION_AGE"
    motionSegmentCount = $motionSegments.Count
    enterEndSeconds = 0.52
    centerHoldEndSeconds = 1.62
    offscreenRightSeconds = 2.24
    carrierWidth = $CanvasSize
    carrierHeight = $CanvasSize
    visibleContentHeight = [int][Math]::Round(
        $CanvasSize * ($sourceHeight / [double]$sourceWidth))
    particles = @("particles/swift_mvp_effect/mvp_overlay.vpcf")
    textures = @("materials/swift_mvp_effect/mvp_emblem.vtex")
}
Save-TextIfChanged `
    -Text (($manifest | ConvertTo-Json -Depth 4) + "`n") `
    -Path (Join-Path $projectRoot "resources_src\asset_manifest.json")

Write-Host (
    "Generated one transparent MVP emblem carrier (${CanvasSize}x${CanvasSize}) and one client-animated Source 2 root.")
