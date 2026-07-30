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
    $entries = [System.Collections.Generic.List[string]]::new()
    for ($stage = 1; $stage -le 4; $stage++) {
        $entries.Add(
            "materials/swift_mvp_effect/mvp_animation_stage_$stage.vtex_c")
    }
    for ($stage = 1; $stage -le 4; $stage++) {
        $entries.Add(
            "particles/swift_mvp_effect/mvp_overlay_stage_$stage.vpcf_c")
    }
    return [string[]]$entries
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
            "$Description does not match the eight-file MVP contract:`n" +
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
