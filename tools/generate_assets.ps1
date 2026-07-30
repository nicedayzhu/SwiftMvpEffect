param(
    [string]$SourceImage = (
        Join-Path $PSScriptRoot "..\assets\generated\mvp_emblem_transparent.png"),
    [int]$CanvasSize = 1024,
    [string]$SourceArchive = (
        Join-Path $PSScriptRoot "..\assets\source\clean_gold_operator_mvp_animation_pack_60f.zip"),
    [int]$AtlasCanvasSize = 512
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($PSVersionTable.PSEdition -ne "Core" -or $PSVersionTable.PSVersion.Major -lt 7) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) {
        throw "PowerShell 7+ (pwsh) is required."
    }

    & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath `
        -SourceImage $SourceImage `
        -CanvasSize $CanvasSize `
        -SourceArchive $SourceArchive `
        -AtlasCanvasSize $AtlasCanvasSize
    exit $LASTEXITCODE
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$sourceImagePath = [System.IO.Path]::GetFullPath($SourceImage)
$archivePath = [System.IO.Path]::GetFullPath($SourceArchive)
$materialDir = Join-Path $projectRoot "resources_src\materials\swift_mvp_effect"
$particleDir = Join-Path $projectRoot "resources_src\particles\swift_mvp_effect"
$templateDir = Join-Path $PSScriptRoot "templates"

if (!(Test-Path -LiteralPath $sourceImagePath -PathType Leaf)) {
    throw "Transparent MVP source image not found: $sourceImagePath"
}
if (!(Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw "MVP sequence source archive not found: $archivePath"
}
if ($CanvasSize -lt 256 -or $CanvasSize -gt 1024) {
    throw "CanvasSize must be between 256 and 1024."
}
if ($AtlasCanvasSize -lt 256 -or $AtlasCanvasSize -gt 1024) {
    throw "AtlasCanvasSize must be between 256 and 1024."
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

$archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    $entries = @(
        $archive.Entries |
            Where-Object {
                $_.FullName -match
                    '^clean_gold_operator_mvp_60_frames/clean_gold_operator_mvp_frame_[0-9]{3}\.png$'
            } |
            Sort-Object FullName
    )
    if ($entries.Count -ne 60) {
        throw "Expected exactly 60 sequence PNG frames, found $($entries.Count)."
    }

    $expectedFrameNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    $atlasSourceWidth = 0
    $atlasSourceHeight = 0

    for ($index = 0; $index -lt $entries.Count; $index++) {
        $entry = $entries[$index]
        $entryStream = $entry.Open()
        try {
            $frameSource = [System.Drawing.Image]::FromStream($entryStream)
            try {
                if ($index -eq 0) {
                    $atlasSourceWidth = $frameSource.Width
                    $atlasSourceHeight = $frameSource.Height
                }
                elseif ($frameSource.Width -ne $atlasSourceWidth -or
                    $frameSource.Height -ne $atlasSourceHeight) {
                    throw "Sequence frame dimensions are inconsistent at $($entry.FullName)."
                }

                if ($atlasSourceWidth -ne 1280 -or $atlasSourceHeight -ne 512) {
                    throw (
                        "Expected 1280x512 sequence frames, got " +
                        "${atlasSourceWidth}x${atlasSourceHeight}.")
                }

                $atlasTargetWidth = $AtlasCanvasSize
                $atlasTargetHeight = [Math]::Max(
                    1,
                    [int][Math]::Round(
                        $AtlasCanvasSize *
                        ($atlasSourceHeight / [double]$atlasSourceWidth)))
                $atlasTargetX = 0
                $atlasTargetY = [int][Math]::Floor(
                    ($AtlasCanvasSize - $atlasTargetHeight) / 2.0)

                $atlasCarrier = [System.Drawing.Bitmap]::new(
                    $AtlasCanvasSize,
                    $AtlasCanvasSize,
                    [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
                try {
                    $graphics = [System.Drawing.Graphics]::FromImage($atlasCarrier)
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
                            $frameSource,
                            [System.Drawing.Rectangle]::new(
                                $atlasTargetX,
                                $atlasTargetY,
                                $atlasTargetWidth,
                                $atlasTargetHeight),
                            0,
                            0,
                            $atlasSourceWidth,
                            $atlasSourceHeight,
                            [System.Drawing.GraphicsUnit]::Pixel)
                    }
                    finally {
                        $graphics.Dispose()
                    }

                    $frameName = "mvp_frame_{0:D3}.png" -f ($index + 1)
                    [void]$expectedFrameNames.Add($frameName)
                    $memory = [System.IO.MemoryStream]::new()
                    try {
                        $atlasCarrier.Save(
                            $memory,
                            [System.Drawing.Imaging.ImageFormat]::Png)
                        Save-BytesIfChanged `
                            -Bytes $memory.ToArray() `
                            -Path (Join-Path $materialDir $frameName)
                    }
                    finally {
                        $memory.Dispose()
                    }
                }
                finally {
                    $atlasCarrier.Dispose()
                }
            }
            finally {
                $frameSource.Dispose()
            }
        }
        finally {
            $entryStream.Dispose()
        }
    }

    foreach ($staleFrame in Get-ChildItem `
            -LiteralPath $materialDir `
            -File `
            -Filter "mvp_frame_*.png") {
        if (!$expectedFrameNames.Contains($staleFrame.Name)) {
            Remove-Item -LiteralPath $staleFrame.FullName -Force
        }
    }
}
finally {
    $archive.Dispose()
}

$mksLines = [System.Collections.Generic.List[string]]::new()
$mksLines.Add("sequence 0")
$mksLines.Add("")
for ($frame = 1; $frame -le 60; $frame++) {
    $mksLines.Add(("frame mvp_frame_{0:D3}.png 1" -f $frame))
}
$mksLines.Add("")
Save-TextIfChanged `
    -Text ($mksLines -join "`n") `
    -Path (Join-Path $materialDir "mvp_animation_60f.mks")

$vtexTemplate = Get-Content -Raw -LiteralPath (
    Join-Path $templateDir "mvp_emblem.vtex.tmpl")
$atlasVtexTemplate = Get-Content -Raw -LiteralPath (
    Join-Path $templateDir "mvp_animation_60f.vtex.tmpl")
$vpcfBaseTemplate = Get-Content -Raw -LiteralPath (
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
$emblemVpcf = $vpcfBaseTemplate.Replace(
    "{{MOTION_RENDERERS}}",
    $motionRendererBlocks -join "")
$atlasMotionRendererBlocks = @(
    foreach ($rendererBlock in $motionRendererBlocks) {
        $atlasRendererBlock = $rendererBlock.Replace(
            'resource:"materials/swift_mvp_effect/mvp_emblem.vtex"',
            'resource:"materials/swift_mvp_effect/mvp_animation_60f.vtex"')
        $atlasRendererBlock = $atlasRendererBlock.Replace(
            'm_nAnimationType = "ANIMATION_TYPE_MANUAL_FRAMES"',
            (
                'm_nAnimationType = "ANIMATION_TYPE_FIT_LIFETIME"' +
                "`n`t`t`tm_flAnimationRate = 25.000000" +
                "`n`t`t`tm_bAnimateInFPS = true"))
        $atlasRendererBlock
    }
)
$atlasVpcf = $vpcfBaseTemplate.Replace(
    "{{MOTION_RENDERERS}}",
    $atlasMotionRendererBlocks -join "")
if ($emblemVpcf.Contains("{{MOTION_RENDERERS}}") -or
    $atlasVpcf.Contains("{{MOTION_RENDERERS}}")) {
    throw "Failed to expand one or more VPCF motion renderer templates."
}

Save-TextIfChanged `
    -Text $vtexTemplate `
    -Path (Join-Path $materialDir "mvp_emblem.vtex")
Save-TextIfChanged `
    -Text $atlasVtexTemplate `
    -Path (Join-Path $materialDir "mvp_animation_60f.vtex")
Save-TextIfChanged `
    -Text $emblemVpcf `
    -Path (Join-Path $particleDir "mvp_overlay.vpcf")
Save-TextIfChanged `
    -Text $atlasVpcf `
    -Path (Join-Path $particleDir "mvp_atlas_overlay.vpcf")

foreach ($obsolete in @(
        (Join-Path $materialDir "mvp_animation_stage_1.mks"),
        (Join-Path $materialDir "mvp_animation_stage_2.mks"),
        (Join-Path $materialDir "mvp_animation_stage_3.mks"),
        (Join-Path $materialDir "mvp_animation_stage_4.mks"),
        (Join-Path $materialDir "mvp_animation_stage_1.vtex"),
        (Join-Path $materialDir "mvp_animation_stage_2.vtex"),
        (Join-Path $materialDir "mvp_animation_stage_3.vtex"),
        (Join-Path $materialDir "mvp_animation_stage_4.vtex"),
        (Join-Path $particleDir "mvp_overlay_stage_1.vpcf"),
        (Join-Path $particleDir "mvp_overlay_stage_2.vpcf"),
        (Join-Path $particleDir "mvp_overlay_stage_3.vpcf"),
        (Join-Path $particleDir "mvp_overlay_stage_4.vpcf"))) {
    if (Test-Path -LiteralPath $obsolete) {
        Remove-Item -LiteralPath $obsolete -Force
    }
}

$manifest = [ordered]@{
    schemaVersion = 1
    sourceImage = [System.IO.Path]::GetFileName($sourceImagePath)
    sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceImagePath).Hash.ToLowerInvariant()
    sourceFrameWidth = $sourceWidth
    sourceFrameHeight = $sourceHeight
    frameCount = 1
    framesPerSecond = 0
    atlasSourceArchive = [System.IO.Path]::GetFileName($archivePath)
    atlasSourceSha256 = (
        Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath
    ).Hash.ToLowerInvariant()
    atlasSourceFrameWidth = $atlasSourceWidth
    atlasSourceFrameHeight = $atlasSourceHeight
    atlasFrameCount = 60
    atlasFramesPerSecond = 25
    atlasCarrierWidth = $AtlasCanvasSize
    atlasCarrierHeight = $AtlasCanvasSize
    atlasVisibleContentHeight = $atlasTargetHeight
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
    particles = @(
        "particles/swift_mvp_effect/mvp_overlay.vpcf",
        "particles/swift_mvp_effect/mvp_atlas_overlay.vpcf"
    )
    textures = @(
        "materials/swift_mvp_effect/mvp_emblem.vtex",
        "materials/swift_mvp_effect/mvp_animation_60f.vtex"
    )
}
Save-TextIfChanged `
    -Text (($manifest | ConvertTo-Json -Depth 4) + "`n") `
    -Path (Join-Path $projectRoot "resources_src\asset_manifest.json")

Write-Host (
    "Generated the transparent emblem plus a preserved 60-frame " +
    "sequence atlas and two client-animated Source 2 roots.")
