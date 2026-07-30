param(
    [string]$SourceArchive = (
        Join-Path $PSScriptRoot "..\assets\source\clean_gold_operator_mvp_animation_pack_60f.zip"),
    [int]$CanvasSize = 512
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($PSVersionTable.PSEdition -ne "Core" -or $PSVersionTable.PSVersion.Major -lt 7) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) {
        throw "PowerShell 7+ (pwsh) is required."
    }

    & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath `
        -SourceArchive $SourceArchive -CanvasSize $CanvasSize
    exit $LASTEXITCODE
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$archivePath = [System.IO.Path]::GetFullPath($SourceArchive)
$materialDir = Join-Path $projectRoot "resources_src\materials\swift_mvp_effect"
$particleDir = Join-Path $projectRoot "resources_src\particles\swift_mvp_effect"
$templateDir = Join-Path $PSScriptRoot "templates"

if (!(Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw "MVP source archive not found: $archivePath"
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
        throw "Expected exactly 60 PNG frames, found $($entries.Count)."
    }

    $expectedNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    $sourceWidth = 0
    $sourceHeight = 0

    for ($index = 0; $index -lt $entries.Count; $index++) {
        $entry = $entries[$index]
        $entryStream = $entry.Open()
        try {
            $source = [System.Drawing.Image]::FromStream($entryStream)
            try {
                if ($index -eq 0) {
                    $sourceWidth = $source.Width
                    $sourceHeight = $source.Height
                }
                elseif ($source.Width -ne $sourceWidth -or $source.Height -ne $sourceHeight) {
                    throw "Frame dimensions are inconsistent at $($entry.FullName)."
                }

                if ($sourceWidth -ne 1280 -or $sourceHeight -ne 512) {
                    throw "Expected 1280x512 source frames, got ${sourceWidth}x${sourceHeight}."
                }

                $targetWidth = $CanvasSize
                $targetHeight = [Math]::Max(
                    1,
                    [int][Math]::Round(
                        $CanvasSize * ($sourceHeight / [double]$sourceWidth)))
                $targetX = 0
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
                            [System.Drawing.Rectangle]::new(
                                $targetX,
                                $targetY,
                                $targetWidth,
                                $targetHeight),
                            0,
                            0,
                            $sourceWidth,
                            $sourceHeight,
                            [System.Drawing.GraphicsUnit]::Pixel)
                    }
                    finally {
                        $graphics.Dispose()
                    }

                    $frameName = "mvp_frame_{0:D3}.png" -f ($index + 1)
                    [void]$expectedNames.Add($frameName)
                    $outputPath = Join-Path $materialDir $frameName
                    $memory = [System.IO.MemoryStream]::new()
                    try {
                        $carrier.Save(
                            $memory,
                            [System.Drawing.Imaging.ImageFormat]::Png)
                        Save-BytesIfChanged -Bytes $memory.ToArray() -Path $outputPath
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
        }
        finally {
            $entryStream.Dispose()
        }
    }

    foreach ($stale in Get-ChildItem -LiteralPath $materialDir -File -Filter "mvp_frame_*.png") {
        if (!$expectedNames.Contains($stale.Name)) {
            Remove-Item -LiteralPath $stale.FullName -Force
        }
    }
}
finally {
    $archive.Dispose()
}

$vtexTemplate = Get-Content -Raw -LiteralPath (
    Join-Path $templateDir "mvp_animation_stage.vtex.tmpl")
$vpcfTemplate = Get-Content -Raw -LiteralPath (
    Join-Path $templateDir "mvp_overlay.vpcf.tmpl")
$stageDepthBiases = @(
    "0.000000",
    "-1.000000",
    "-2.000000",
    "-3.000000"
)
for ($stage = 1; $stage -le 4; $stage++) {
    $firstFrame = (($stage - 1) * 15) + 1
    $lastFrame = $stage * 15
    $mksLines = [System.Collections.Generic.List[string]]::new()
    $mksLines.Add("sequence 0")
    $mksLines.Add("")
    for ($frame = $firstFrame; $frame -le $lastFrame; $frame++) {
        $durationWeight = if ($frame -eq $lastFrame) { 2 } else { 1 }
        $mksLines.Add(
            ("frame mvp_frame_{0:D3}.png {1}" -f $frame, $durationWeight))
    }
    $mksLines.Add("")
    Save-TextIfChanged `
        -Text ($mksLines -join "`n") `
        -Path (Join-Path $materialDir (
            "mvp_animation_stage_{0}.mks" -f $stage))

    $stageVtex = $vtexTemplate.Replace(
        "{{STAGE}}",
        [string]$stage,
        [System.StringComparison]::Ordinal)
    $stageVpcf = $vpcfTemplate.Replace(
        "{{STAGE}}",
        [string]$stage,
        [System.StringComparison]::Ordinal)
    $stageVpcf = $stageVpcf.Replace(
        "{{DEPTH_SORT_BIAS}}",
        $stageDepthBiases[$stage - 1],
        [System.StringComparison]::Ordinal)

    Save-TextIfChanged `
        -Text $stageVtex `
        -Path (Join-Path $materialDir (
            "mvp_animation_stage_{0}.vtex" -f $stage))
    Save-TextIfChanged `
        -Text $stageVpcf `
        -Path (Join-Path $particleDir (
            "mvp_overlay_stage_{0}.vpcf" -f $stage))
}

foreach ($obsolete in @(
        (Join-Path $materialDir "mvp_animation_60f.mks"),
        (Join-Path $materialDir "mvp_animation_60f.vtex"),
        (Join-Path $particleDir "mvp_overlay.vpcf"))) {
    if (Test-Path -LiteralPath $obsolete) {
        Remove-Item -LiteralPath $obsolete -Force
    }
}

$manifest = [ordered]@{
    schemaVersion = 1
    sourceArchive = [System.IO.Path]::GetFileName($archivePath)
    sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash.ToLowerInvariant()
    sourceFrameWidth = $sourceWidth
    sourceFrameHeight = $sourceHeight
    frameCount = 60
    framesPerSecond = 25
    durationSeconds = 2.4
    stageCount = 4
    framesPerStage = 15
    stageIntervalSeconds = 0.6
    stageLifetimeSeconds = 0.64
    carrierWidth = $CanvasSize
    carrierHeight = $CanvasSize
    visibleContentHeight = [int][Math]::Round(
        $CanvasSize * ($sourceHeight / [double]$sourceWidth))
    particles = @(
        1..4 | ForEach-Object {
            "particles/swift_mvp_effect/mvp_overlay_stage_$_.vpcf"
        }
    )
    textures = @(
        1..4 | ForEach-Object {
            "materials/swift_mvp_effect/mvp_animation_stage_$_.vtex"
        }
    )
}
Save-TextIfChanged `
    -Text (($manifest | ConvertTo-Json -Depth 4) + "`n") `
    -Path (Join-Path $projectRoot "resources_src\asset_manifest.json")

Write-Host (
    "Generated 60 MVP carrier frames (${CanvasSize}x${CanvasSize}) and four 15-frame Source 2 stages.")
