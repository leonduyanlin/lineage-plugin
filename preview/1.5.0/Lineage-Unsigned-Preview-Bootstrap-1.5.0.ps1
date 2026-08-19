[CmdletBinding()]
param(
    [ValidateSet('Install', 'Uninstall')][string]$Action = 'Install',
    [string]$ZipPath,
    [string]$ChecksumsPath,
    [switch]$AcceptUnsignedPreviewRisk,
    [switch]$SkipLaunch
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Get-LineagePreviewChecksumEntries {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "The unsigned preview checksum file is missing: $resolved"
    }
    $entries = [Collections.Generic.Dictionary[string,string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($line in Get-Content -LiteralPath $resolved) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$') {
            throw "The unsigned preview checksum file contains an invalid entry: $line"
        }
        $name = $Matches[2].Replace('\', '/')
        if ($entries.ContainsKey($name)) {
            throw "The unsigned preview checksum file contains a duplicate entry: $name"
        }
        $entries.Add($name, $Matches[1].ToUpperInvariant())
    }
    $entries
}

function Assert-LineagePreviewArchiveEntries {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Entries,
        [int]$MaxFileCount = 32,
        [long]$MaxEntryUncompressedBytes = 67108864L,
        [long]$MaxTotalUncompressedBytes = 134217728L
    )

    $entryArray = @($Entries)
    if ($MaxFileCount -le 0 -or $MaxEntryUncompressedBytes -le 0 -or
        $MaxTotalUncompressedBytes -le 0) {
        throw 'The unsigned preview archive limits are invalid.'
    }
    if ($entryArray.Count -gt $MaxFileCount) {
        throw "The unsigned preview archive exceeds the file-count limit of $MaxFileCount."
    }
    $names = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $invalidNameCharacters = [IO.Path]::GetInvalidFileNameChars()
    [long]$total = 0
    foreach ($entry in $entryArray) {
        if ($null -eq $entry) {
            throw 'The unsigned preview archive contains an invalid null entry.'
        }
        $name = [string]$entry.Name
        $fullName = [string]$entry.FullName
        if ([string]::IsNullOrWhiteSpace($name) -or
            $fullName -cne $name -or
            $name -in @('.', '..') -or
            $name.IndexOfAny([char[]]@('\', '/')) -ge 0 -or
            $name.IndexOfAny($invalidNameCharacters) -ge 0 -or
            $name.EndsWith('.', [StringComparison]::Ordinal) -or
            $name.EndsWith(' ', [StringComparison]::Ordinal) -or
            $name -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)' -or
            [IO.Path]::GetFileName($name) -cne $name -or
            -not $names.Add($name)) {
            throw "The unsigned preview archive contains an unsafe name or is not a flat, unique file set: $fullName"
        }
        [long]$length = $entry.Length
        if ($length -lt 0 -or $length -gt $MaxEntryUncompressedBytes) {
            throw "The unsigned preview archive entry size limit was exceeded: $name Length=$length Limit=$MaxEntryUncompressedBytes"
        }
        if ($total -gt $MaxTotalUncompressedBytes - $length) {
            throw "The unsigned preview archive total size limit was exceeded. Limit=$MaxTotalUncompressedBytes"
        }
        $total += $length
    }
    [pscustomobject]@{
        FileCount = $entryArray.Count
        TotalUncompressedBytes = $total
    }
}

function Expand-LineagePreviewArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][IO.Stream]$ArchiveStream,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [int]$MaxFileCount = 32,
        [long]$MaxEntryUncompressedBytes = 67108864L,
        [long]$MaxTotalUncompressedBytes = 134217728L
    )

    if (-not $ArchiveStream.CanRead -or -not $ArchiveStream.CanSeek) {
        throw 'The unsigned preview archive snapshot must be a readable, seekable stream.'
    }
    $destinationRoot = [IO.Path]::GetFullPath($DestinationPath)
    if (-not (Test-Path -LiteralPath $destinationRoot -PathType Container)) {
        throw "The unsigned preview extraction directory is missing: $destinationRoot"
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $ArchiveStream.Position = 0
    $archive = [IO.Compression.ZipArchive]::new(
        $ArchiveStream,
        [IO.Compression.ZipArchiveMode]::Read,
        $true)
    $entryCount = 0
    [long]$totalExtracted = 0
    try {
        [void](Assert-LineagePreviewArchiveEntries `
            -Entries @($archive.Entries) `
            -MaxFileCount $MaxFileCount `
            -MaxEntryUncompressedBytes $MaxEntryUncompressedBytes `
            -MaxTotalUncompressedBytes $MaxTotalUncompressedBytes)
        $entryCount = @($archive.Entries).Count
        foreach ($entry in $archive.Entries) {
            $outputPath = [IO.Path]::GetFullPath((Join-Path $destinationRoot $entry.Name))
            if ((Split-Path $outputPath -Parent) -cne $destinationRoot) {
                throw "The unsigned preview archive entry escaped its extraction directory: $($entry.FullName)"
            }
            $input = $entry.Open()
            try {
                $output = [IO.FileStream]::new(
                    $outputPath,
                    [IO.FileMode]::CreateNew,
                    [IO.FileAccess]::Write,
                    [IO.FileShare]::None)
                try {
                    $entryExtracted = Copy-LineagePreviewEntryBounded `
                        -InputStream $input `
                        -OutputStream $output `
                        -EntryName $entry.Name `
                        -DeclaredLength ([long]$entry.Length) `
                        -CurrentTotalBytes $totalExtracted `
                        -MaxEntryUncompressedBytes $MaxEntryUncompressedBytes `
                        -MaxTotalUncompressedBytes $MaxTotalUncompressedBytes
                    $totalExtracted += $entryExtracted
                }
                finally { $output.Dispose() }
            }
            finally { $input.Dispose() }
        }
    }
    finally {
        $archive.Dispose()
    }
    [pscustomobject]@{
        FileCount = $entryCount
        TotalUncompressedBytes = $totalExtracted
    }
}

function Copy-LineagePreviewEntryBounded {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][IO.Stream]$InputStream,
        [Parameter(Mandatory = $true)][IO.Stream]$OutputStream,
        [Parameter(Mandatory = $true)][string]$EntryName,
        [Parameter(Mandatory = $true)][long]$DeclaredLength,
        [Parameter(Mandatory = $true)][long]$CurrentTotalBytes,
        [Parameter(Mandatory = $true)][long]$MaxEntryUncompressedBytes,
        [Parameter(Mandatory = $true)][long]$MaxTotalUncompressedBytes
    )

    if ($DeclaredLength -lt 0 -or $DeclaredLength -gt $MaxEntryUncompressedBytes) {
        throw "The unsigned preview archive entry size limit was exceeded: $EntryName"
    }
    [long]$entryExtracted = 0
    $buffer = [byte[]]::new(81920)
    while (($count = $InputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        if ($entryExtracted -gt $MaxEntryUncompressedBytes - $count) {
            throw "The unsigned preview archive entry size limit was exceeded while extracting $EntryName."
        }
        if ($CurrentTotalBytes + $entryExtracted -gt
            $MaxTotalUncompressedBytes - $count) {
            throw 'The unsigned preview archive total size limit was exceeded while extracting.'
        }
        if ($entryExtracted -gt $DeclaredLength - $count) {
            throw "The unsigned preview archive declared size does not match extracted bytes for $EntryName."
        }
        $OutputStream.Write($buffer, 0, $count)
        $entryExtracted += $count
    }
    if ($entryExtracted -ne $DeclaredLength) {
        throw "The unsigned preview archive declared size does not match extracted bytes for $EntryName."
    }
    $entryExtracted
}

function Invoke-LineagePreviewBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BootstrapPath,
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$ChecksumsPath,
        [Parameter(Mandatory = $true)][ValidateSet('Install', 'Uninstall')][string]$Action,
        [switch]$AcceptUnsignedPreviewRisk,
        [switch]$SkipLaunch,
        [scriptblock]$ProcessLauncher = {
            param([string]$FilePath, [string[]]$ArgumentList)
            $startInfo = [Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $FilePath
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            foreach ($argument in @($ArgumentList)) {
                [void]$startInfo.ArgumentList.Add($argument)
            }
            $child = [Diagnostics.Process]::new()
            try {
                $child.StartInfo = $startInfo
                if (-not $child.Start()) {
                    throw "Failed to start child process: $FilePath"
                }
                $child.WaitForExit()
                [pscustomobject]@{ ExitCode = $child.ExitCode }
            }
            finally {
                $child.Dispose()
            }
        },
        [scriptblock]$Unblocker = {
            param([string]$Path)
            Unblock-File -LiteralPath $Path -ErrorAction Stop
        },
        [scriptblock]$ArchiveSnapshotProvider = {
            param([string]$SourcePath, [string]$SnapshotPath)
            $source = [IO.FileStream]::new(
                $SourcePath,
                [IO.FileMode]::Open,
                [IO.FileAccess]::Read,
                [IO.FileShare]::Read)
            try {
                $destination = [IO.FileStream]::new(
                    $SnapshotPath,
                    [IO.FileMode]::CreateNew,
                    [IO.FileAccess]::ReadWrite,
                    [IO.FileShare]::Read)
                try {
                    $source.CopyTo($destination)
                    $destination.Flush($true)
                    $destination.Position = 0
                }
                catch {
                    $destination.Dispose()
                    throw
                }
            }
            finally { $source.Dispose() }
            $destination
        },
        [string]$PowerShellPath
    )

    if (-not $AcceptUnsignedPreviewRisk) {
        throw 'Unsigned preview installation requires -AcceptUnsignedPreviewRisk. This native Excel add-in is not code-signed.'
    }
    $resolvedBootstrap = [IO.Path]::GetFullPath($BootstrapPath)
    $resolvedZip = [IO.Path]::GetFullPath($ZipPath)
    if (-not (Test-Path -LiteralPath $resolvedBootstrap -PathType Leaf)) {
        throw "The unsigned preview bootstrap is missing: $resolvedBootstrap"
    }
    if (-not (Test-Path -LiteralPath $resolvedZip -PathType Leaf)) {
        throw "The unsigned preview archive is missing: $resolvedZip"
    }
    $checksums = Get-LineagePreviewChecksumEntries -Path $ChecksumsPath
    $zipName = [IO.Path]::GetFileName($resolvedZip)
    if (-not $checksums.ContainsKey($zipName)) {
        throw "The checksum file does not identify the unsigned preview archive: $zipName"
    }
    $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) (
        'LineageUnsignedPreview-' + [Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $temporaryRoot)
    $snapshotStream = $null
    try {
        $expectedSnapshotPath = [IO.Path]::GetFullPath((
            Join-Path $temporaryRoot 'verified-package.zip'))
        $snapshotStream = & $ArchiveSnapshotProvider $resolvedZip $expectedSnapshotPath
        if ($snapshotStream -isnot [IO.FileStream] -or
            -not $snapshotStream.CanRead -or -not $snapshotStream.CanSeek -or
            [IO.Path]::GetFullPath($snapshotStream.Name) -cne $expectedSnapshotPath) {
            throw 'The unsigned preview archive snapshot provider returned an invalid open stream.'
        }
        $snapshotStream.Position = 0
        $sha256 = [Security.Cryptography.SHA256]::Create()
        try {
            $zipHash = ([BitConverter]::ToString(
                $sha256.ComputeHash($snapshotStream))).Replace('-', '')
        }
        finally { $sha256.Dispose() }
        if ($zipHash -cne $checksums[$zipName]) {
            throw "The unsigned preview archive hash does not match SHA256SUMS.txt: $zipName"
        }
        $extractionPath = Join-Path $temporaryRoot 'package'
        [void](New-Item -ItemType Directory -Path $extractionPath)
        [void](Expand-LineagePreviewArchive `
            -ArchiveStream $snapshotStream `
            -DestinationPath $extractionPath)
        $packageRoot = $extractionPath
        $transactionScript = Join-Path $packageRoot 'Installer.Transaction.ps1'
        if (-not (Test-Path -LiteralPath $transactionScript -PathType Leaf)) {
            throw 'The unsigned preview archive is missing Installer.Transaction.ps1.'
        }
        . $transactionScript
        $manifestPath = Join-Path $packageRoot 'manifest.sha256'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw 'The unsigned preview archive is missing manifest.sha256.'
        }
        $manifestEntries = Get-LineageManifestEntries `
            -Lines @(Get-Content -LiteralPath $manifestPath)
        Assert-LineagePackagePayloadIntegrity `
            -PackageDirectory $packageRoot `
            -ManifestEntries $manifestEntries
        $channelPath = Join-Path $packageRoot 'distribution-channel.txt'
        if (-not $manifestEntries.ContainsKey('distribution-channel.txt')) {
            throw 'The unsigned preview manifest does not bind distribution-channel.txt.'
        }
        $channelSnapshot = Get-LineageVerifiedUtf8TextSnapshot `
            -Path $channelPath `
            -ExpectedHash $manifestEntries['distribution-channel.txt']
        $channel = Resolve-LineagePackageDistributionChannel -Value $channelSnapshot.Text
        if ($channel -cne 'UnsignedPreview') {
            throw 'The unsigned preview bootstrap refuses a signed-production package.'
        }

        foreach ($file in Get-ChildItem -LiteralPath $packageRoot -File) {
            & $Unblocker $file.FullName
        }
        if ([string]::IsNullOrWhiteSpace($PowerShellPath)) {
            $command = Get-Command pwsh -ErrorAction SilentlyContinue
            if ($null -eq $command) {
                throw 'PowerShell 7 is required to install the unsigned preview.'
            }
            $PowerShellPath = [string]$command.Source
        }
        $entryName = if ($Action -eq 'Install') {
            'Install-Lineage.ps1'
        }
        else {
            'Uninstall-Lineage.ps1'
        }
        $arguments = [Collections.Generic.List[string]]::new()
        foreach ($argument in @(
            '-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File',
            (Join-Path $packageRoot $entryName))) {
            $arguments.Add($argument)
        }
        if ($Action -eq 'Install') {
            $arguments.Add('-PackageDirectory')
            $arguments.Add($packageRoot)
            if ($SkipLaunch) { $arguments.Add('-SkipLaunch') }
        }
        $process = & $ProcessLauncher $PowerShellPath $arguments.ToArray()
        if ($null -eq $process -or [int]$process.ExitCode -ne 0) {
            $exitCode = if ($null -eq $process) { 'NoResult' } else { [string]$process.ExitCode }
            throw "The unsigned preview $Action action failed. ExitCode=$exitCode"
        }
        [pscustomobject]@{
            Action = $Action
            Channel = $channel
            ArchiveSha256 = $zipHash
        }
    }
    finally {
        if ($null -ne $snapshotStream) { $snapshotStream.Dispose() }
        if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    if ([string]::IsNullOrWhiteSpace($ZipPath) -or
        [string]::IsNullOrWhiteSpace($ChecksumsPath)) {
        throw 'ZipPath and ChecksumsPath are required.'
    }
    [void](Invoke-LineagePreviewBootstrap `
        -BootstrapPath $PSCommandPath `
        -ZipPath $ZipPath `
        -ChecksumsPath $ChecksumsPath `
        -Action $Action `
        -AcceptUnsignedPreviewRisk:$AcceptUnsignedPreviewRisk `
        -SkipLaunch:$SkipLaunch)
}
