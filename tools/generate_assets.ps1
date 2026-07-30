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
