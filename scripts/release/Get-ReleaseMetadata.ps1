[CmdletBinding()]
param(
    [string]$VersionFile = (Join-Path $PSScriptRoot "..\..\VERSION"),
    [string]$ChangelogFile = (Join-Path $PSScriptRoot "..\..\CHANGELOG.md"),
    [ValidateSet("Object", "Json", "GitHub")]
    [string]$OutputFormat = "Object",
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
        throw "$Label file does not exist: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Write-GitHubOutputValue {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Name,
        [AllowEmptyString()]
        [string]$Value
    )

    $delimiter = "EXAMINE_INTERACTION_$([Guid]::NewGuid().ToString('N'))"
    $lines = @(
        "$Name<<$delimiter"
        $Value
        $delimiter
    )
    Add-Content -LiteralPath $Path -Value $lines -Encoding utf8
}

$resolvedVersionFile = Resolve-RequiredFile -Path $VersionFile -Label "Version"
$resolvedChangelogFile = Resolve-RequiredFile -Path $ChangelogFile -Label "Changelog"

$version = (Get-Content -LiteralPath $resolvedVersionFile -Raw).Trim()
$semanticVersionPattern = '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
if ($version -notmatch $semanticVersionPattern) {
    throw "VERSION must contain exactly one semantic version in MAJOR.MINOR.PATCH form. Found: '$version'"
}

$changelog = (Get-Content -LiteralPath $resolvedChangelogFile -Raw) -replace "`r`n", "`n"
$escapedVersion = [Regex]::Escape($version)
$headingPattern = "(?m)^## \[$escapedVersion\] - (?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})[ `t]*$"
$headingMatches = [Regex]::Matches($changelog, $headingPattern)
if ($headingMatches.Count -ne 1) {
    throw "CHANGELOG.md must contain exactly one heading in this form: ## [$version] - YYYY-MM-DD"
}

$headingMatch = $headingMatches[0]
$releaseDateText = $headingMatch.Groups["date"].Value
$releaseDate = [DateTime]::MinValue
$validDate = [DateTime]::TryParseExact(
    $releaseDateText,
    "yyyy-MM-dd",
    [Globalization.CultureInfo]::InvariantCulture,
    [Globalization.DateTimeStyles]::None,
    [ref]$releaseDate
)
if (-not $validDate -or $releaseDate.ToString("yyyy-MM-dd") -ne $releaseDateText) {
    throw "The changelog date is not a valid YYYY-MM-DD date: $releaseDateText"
}

$bodyStart = $headingMatch.Index + $headingMatch.Length
$remainingChangelog = $changelog.Substring($bodyStart)
$nextHeading = [Regex]::Match($remainingChangelog, '(?m)^## ')
if ($nextHeading.Success) {
    $remainingChangelog = $remainingChangelog.Substring(0, $nextHeading.Index)
}

$releaseNotes = $remainingChangelog.Trim()
if ([string]::IsNullOrWhiteSpace($releaseNotes)) {
    throw "The changelog section for $version is empty."
}
if ($releaseNotes -notmatch '(?m)^### (Added|Changed|Deprecated|Removed|Fixed|Security)$') {
    throw "The changelog section for $version needs at least one Keep a Changelog category heading."
}

$metadata = [pscustomobject][ordered]@{
    version = $version
    tag = "v$version"
    releaseName = "Examine Interaction $version"
    releaseDate = $releaseDateText
    changelog = $releaseNotes
}

switch ($OutputFormat) {
    "Json" {
        $metadata | ConvertTo-Json -Depth 3
    }
    "GitHub" {
        if ([string]::IsNullOrWhiteSpace($GitHubOutputFile)) {
            throw "GitHub output format requires -GitHubOutputFile or the GITHUB_OUTPUT environment variable."
        }

        Write-GitHubOutputValue -Path $GitHubOutputFile -Name "version" -Value $metadata.version
        Write-GitHubOutputValue -Path $GitHubOutputFile -Name "tag" -Value $metadata.tag
        Write-GitHubOutputValue -Path $GitHubOutputFile -Name "release_name" -Value $metadata.releaseName
        Write-GitHubOutputValue -Path $GitHubOutputFile -Name "release_date" -Value $metadata.releaseDate
        Write-GitHubOutputValue -Path $GitHubOutputFile -Name "changelog" -Value $metadata.changelog
    }
    default {
        $metadata
    }
}
