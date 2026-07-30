function Resolve-FullPath {
    param([Parameter(Mandatory)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-PathExists {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Description
    )

    if (!(Test-Path -LiteralPath $Path)) {
        throw "$Description not found: $Path"
    }
}

function Assert-SafeChildPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Parent,
        [string]$ExpectedLeaf = ""
    )

    $fullPath = Resolve-FullPath $Path
    $fullParent = Resolve-FullPath $Parent
    $parentPrefix = $fullParent.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar) +
        [System.IO.Path]::DirectorySeparatorChar

    if (!$fullPath.StartsWith(
            $parentPrefix,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe path outside expected parent: $fullPath"
    }
    if (![string]::IsNullOrWhiteSpace($ExpectedLeaf) -and
        !(Split-Path -Leaf $fullPath).Equals(
            $ExpectedLeaf,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe path with unexpected leaf: $fullPath"
    }
}

function Get-MvpExpectedVpkEntries {
    return [string[]]@(
        "materials/swift_mvp_effect/mvp_emblem.vtex_c",
        "particles/swift_mvp_effect/mvp_overlay.vpcf_c"
    )
}

function Get-RelativeFileList {
    param([Parameter(Mandatory)][string]$Root)

    $fullRoot = Resolve-FullPath $Root
    return [string[]]@(
        Get-ChildItem -LiteralPath $fullRoot -Recurse -File |
            ForEach-Object {
                [System.IO.Path]::GetRelativePath(
                    $fullRoot,
                    $_.FullName).Replace(
                        [System.IO.Path]::DirectorySeparatorChar,
                        '/')
            } |
            Sort-Object
    )
}

function Assert-DirectoryMatchesEntries {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$ExpectedEntries,
        [Parameter(Mandatory)][string]$Description
    )

    Assert-PathExists -Path $Root -Description $Description
    $expected = [string[]]@($ExpectedEntries | Sort-Object)
    $actual = Get-RelativeFileList -Root $Root
    $difference = @(
        Compare-Object -ReferenceObject $expected -DifferenceObject $actual
    )
    if ($difference.Count -gt 0) {
        $details = $difference |
            ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }
        throw (
            "$Description does not match the MVP asset contract:`n" +
            ($details -join [System.Environment]::NewLine))
    }
}

function Assert-FileHashEqual {
    param(
        [Parameter(Mandatory)][string]$ExpectedPath,
        [Parameter(Mandatory)][string]$ActualPath,
        [Parameter(Mandatory)][string]$Description
    )

    Assert-PathExists -Path $ExpectedPath -Description "$Description source"
    Assert-PathExists -Path $ActualPath -Description "$Description destination"
    $expectedHash = (
        Get-FileHash -Algorithm SHA256 -LiteralPath $ExpectedPath).Hash
    $actualHash = (
        Get-FileHash -Algorithm SHA256 -LiteralPath $ActualPath).Hash
    if ($expectedHash -ne $actualHash) {
        throw "$Description SHA-256 mismatch: $ExpectedPath <> $ActualPath"
    }
}

function Get-VpkV2Header {
    param([Parameter(Mandatory)][string]$Path)

    Assert-PathExists -Path $Path -Description "VPK"
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $reader = [System.IO.BinaryReader]::new($stream)
        if ($stream.Length -lt 28) {
            throw "VPK is too short to contain a v2 header: $Path"
        }
        $header = [pscustomobject]@{
            Magic = $reader.ReadUInt32()
            Version = $reader.ReadUInt32()
            TreeSize = $reader.ReadUInt32()
            FileDataSectionSize = $reader.ReadUInt32()
            ArchiveMd5SectionSize = $reader.ReadUInt32()
            OtherMd5SectionSize = $reader.ReadUInt32()
            SignatureSectionSize = $reader.ReadUInt32()
        }
    }
    finally {
        $stream.Dispose()
    }
    return $header
}

function Assert-Cs2InlineVpkLayout {
    param([Parameter(Mandatory)][string]$Path)

    $header = Get-VpkV2Header -Path $Path
    if ($header.Magic -ne [uint32]0x55AA1234) {
        throw "Unexpected VPK signature: $Path"
    }
    if ($header.Version -ne 2) {
        throw "CS2 override VPK must use VPK v2: $Path"
    }
    if ($header.FileDataSectionSize -eq 0) {
        throw "CS2 override VPK must store its files inline: $Path"
    }
    if ($header.ArchiveMd5SectionSize -ne 0) {
        throw (
            "CS2 override VPK must not contain an archive-MD5 chunk section: " +
            "$Path")
    }
}

function Test-GameInfoMount {
    param(
        [Parameter(Mandatory)][string]$GameInfoPath,
        [Parameter(Mandatory)][string]$AddonName
    )

    if (!(Test-Path -LiteralPath $GameInfoPath -PathType Leaf)) {
        return $false
    }
    $escapedAddon = [regex]::Escape($AddonName)
    $pattern = (
        '^\s*Game\s+csgo/overrides/' +
        $escapedAddon +
        '\.vpk\s*(?://.*)?$')
    return [bool](
        Get-Content -LiteralPath $GameInfoPath |
            Where-Object { $_ -match $pattern } |
            Select-Object -First 1)
}

function Test-GameInfoSwiftlyS2Priority {
    param([Parameter(Mandatory)][string]$GameInfoPath)

    if (!(Test-Path -LiteralPath $GameInfoPath -PathType Leaf)) {
        return $false
    }

    $lines = @(Get-Content -LiteralPath $GameInfoPath)
    $swiftlyIndexes = @(
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match
                '^\s*Game\s+csgo/addons/swiftlys2\s*(?://.*)?$') {
                $index
            }
        })
    if ($swiftlyIndexes.Count -ne 1) {
        return $false
    }

    $overrideIndexes = @(
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match
                '^\s*Game\s+csgo/overrides/[^\s]+\.vpk\s*(?://.*)?$') {
                $index
            }
        })
    if ($overrideIndexes.Count -eq 0) {
        return $true
    }

    return $swiftlyIndexes[0] -lt ($overrideIndexes | Measure-Object -Minimum).Minimum
}
