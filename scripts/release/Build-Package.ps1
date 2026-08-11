[CmdletBinding()]
param(
    [ValidateSet("Release", "RelWithDebInfo")]
    [string]$Configuration = "Release",
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\..\dist"),
    [string]$BuildDirectory = (Join-Path $PSScriptRoot "..\..\native\ExamineInteractionNative\build"),
    [string]$Red4extSdkRoot = "",
    [switch]$SkipNativeBuild,
    [switch]$SkipToolRestore,
    [string]$GitHubOutputFile = $env:GITHUB_OUTPUT
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RequiredFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label does not exist: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Resolve-RequiredDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label does not exist: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE`: $Command $($Arguments -join ' ')"
    }
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory)]
        [string]$Source,
        [Parameter(Mandatory)]
        [string]$Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

function Write-GitHubOutputValue {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$Value
    )

    $delimiter = "EXAMINE_ANYTHING_$([Guid]::NewGuid().ToString('N'))"
    Add-Content -LiteralPath $Path -Value @("$Name<<$delimiter", $Value, $delimiter) -Encoding utf8
}

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$nativeSource = Resolve-RequiredDirectory -Path (Join-Path $repositoryRoot "native\ExamineInteractionNative") -Label "Native source directory"
$archiveSource = Resolve-RequiredDirectory -Path (Join-Path $repositoryRoot "source\archive") -Label "Archive source directory"
$resourceSource = Resolve-RequiredDirectory -Path (Join-Path $repositoryRoot "source\resources") -Label "Resource source directory"
$pluginScriptSource = Resolve-RequiredDirectory -Path (Join-Path $nativeSource "scripts") -Label "Native plugin script directory"
$thirdPartyNotices = Resolve-RequiredFile -Path (Join-Path $nativeSource "THIRD_PARTY_NOTICES.txt") -Label "Third-party notices file"
$metadataScript = Resolve-RequiredFile -Path (Join-Path $PSScriptRoot "Get-ReleaseMetadata.ps1") -Label "Release metadata script"
$archiveXlFile = Resolve-RequiredFile -Path (Join-Path $resourceSource "examine_interaction.xl") -Label "ArchiveXL manifest"
$r6Source = Resolve-RequiredDirectory -Path (Join-Path $resourceSource "r6") -Label "R6 resource directory"

$metadata = & $metadataScript -OutputFormat Json | ConvertFrom-Json
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$nativeBuildRoot = [IO.Path]::GetFullPath($BuildDirectory)
$packageFileName = "$($metadata.packageBaseName).zip"
$packagePath = Join-Path $outputRoot $packageFileName
$checksumPath = "$packagePath.sha256"
$workRoot = Join-Path $outputRoot (".work-" + [Guid]::NewGuid().ToString("N"))
$packageRoot = Join-Path $workRoot "package"
$archiveInput = Join-Path $workRoot "archive-source\examine_interaction"
$archiveOutput = Join-Path $packageRoot "archive\pc\mod"
$nativePluginOutput = Join-Path $packageRoot "red4ext\plugins\ExamineInteractionNative"

$outputPrefix = $outputRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $workRoot.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Temporary package directory escaped the output directory: $workRoot"
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

Push-Location $repositoryRoot
try {
    if (-not $SkipNativeBuild) {
        $configureArguments = @("-S", $nativeSource, "-B", $nativeBuildRoot, "-A", "x64")
        if (-not [string]::IsNullOrWhiteSpace($Red4extSdkRoot)) {
            $configureArguments += "-DRED4EXT_SDK_ROOT=$([IO.Path]::GetFullPath($Red4extSdkRoot))"
        }

        Invoke-ExternalCommand -Command "cmake" -Arguments $configureArguments
        Invoke-ExternalCommand -Command "cmake" -Arguments @(
            "--build", $nativeBuildRoot,
            "--config", $Configuration,
            "--target", "ExamineInteractionNative",
            "--parallel"
        )
    }

    $nativeDll = Resolve-RequiredFile -Path (Join-Path $nativeBuildRoot "bin\$Configuration\ExamineInteractionNative.dll") -Label "Native plugin DLL"

    if (-not $SkipToolRestore) {
        Invoke-ExternalCommand -Command "dotnet" -Arguments @("tool", "restore")
    }

    Copy-DirectoryContents -Source $archiveSource -Destination $archiveInput
    New-Item -ItemType Directory -Path $archiveOutput -Force | Out-Null
    Invoke-ExternalCommand -Command "dotnet" -Arguments @(
        "tool", "run", "cp77tools", "--",
        "pack", $archiveInput,
        "--outpath", $archiveOutput,
        "--verbosity", "Minimal"
    )

    $archiveFile = Resolve-RequiredFile -Path (Join-Path $archiveOutput "examine_interaction.archive") -Label "Packed WolvenKit archive"
    if ((Get-Item -LiteralPath $archiveFile).Length -eq 0) {
        throw "Packed WolvenKit archive is empty: $archiveFile"
    }

    Copy-Item -LiteralPath $archiveXlFile -Destination $archiveOutput -Force
    Copy-Item -LiteralPath $r6Source -Destination $packageRoot -Recurse -Force
    New-Item -ItemType Directory -Path $nativePluginOutput -Force | Out-Null
    Copy-Item -LiteralPath $nativeDll -Destination $nativePluginOutput -Force
    Copy-Item -LiteralPath $thirdPartyNotices -Destination $nativePluginOutput -Force
    Copy-Item -LiteralPath $pluginScriptSource -Destination $nativePluginOutput -Recurse -Force

    $requiredStagedFiles = @(
        "archive\pc\mod\examine_interaction.archive",
        "archive\pc\mod\examine_interaction.xl",
        "r6\scripts\examine_interaction\main.reds",
        "r6\tweaks\examine_interaction_interactions.yaml",
        "red4ext\plugins\ExamineInteractionNative\ExamineInteractionNative.dll",
        "red4ext\plugins\ExamineInteractionNative\THIRD_PARTY_NOTICES.txt",
        "red4ext\plugins\ExamineInteractionNative\scripts\ExamineInteractionNative.reds"
    )
    foreach ($relativePath in $requiredStagedFiles) {
        Resolve-RequiredFile -Path (Join-Path $packageRoot $relativePath) -Label "Required staged file" | Out-Null
    }

    $forbiddenStagedFiles = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File | Where-Object {
        $_.Extension -in @(".pdb", ".lib", ".exp")
    })
    if ($forbiddenStagedFiles.Count -gt 0) {
        throw "Debug or linker artifacts entered the package: $($forbiddenStagedFiles.FullName -join ', ')"
    }

    Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $packagePath -CompressionLevel Optimal -Force

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($packagePath)
    try {
        $zipEntries = @($zip.Entries | ForEach-Object { $_.FullName.Replace("/", "\") })
        foreach ($relativePath in $requiredStagedFiles) {
            if ($relativePath -notin $zipEntries) {
                throw "Required file is missing from the ZIP: $relativePath"
            }
        }
        if ($zipEntries | Where-Object { $_ -match '\.(pdb|lib|exp)$' }) {
            throw "The ZIP contains debug or linker artifacts."
        }
    }
    finally {
        $zip.Dispose()
    }

    $sha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText(
        $checksumPath,
        "$sha256  $packageFileName`n",
        [Text.UTF8Encoding]::new($false)
    )

    $result = [pscustomobject][ordered]@{
        version = $metadata.version
        packagePath = $packagePath
        packageFileName = $packageFileName
        checksumPath = $checksumPath
        sha256 = $sha256
    }

    if (-not [string]::IsNullOrWhiteSpace($GitHubOutputFile)) {
        Write-GitHubOutputValue -Path $GitHubOutputFile -Name "version" -Value $result.version
        Write-GitHubOutputValue -Path $GitHubOutputFile -Name "package_path" -Value $result.packagePath
        Write-GitHubOutputValue -Path $GitHubOutputFile -Name "package_file_name" -Value $result.packageFileName
        Write-GitHubOutputValue -Path $GitHubOutputFile -Name "checksum_path" -Value $result.checksumPath
        Write-GitHubOutputValue -Path $GitHubOutputFile -Name "sha256" -Value $result.sha256
    }

    $result
}
finally {
    Pop-Location
    if (Test-Path -LiteralPath $workRoot -PathType Container) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
}
