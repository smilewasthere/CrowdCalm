param(
    [Parameter(Mandatory = $true)]
    [string]$WowRoot,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$addonName = "CrowdCalm"
$repoRoot = $PSScriptRoot
$runtimeFiles = @(
    "CrowdCalm.toc",
    "Crowd.lua",
    "Profiles.lua",
    "Restore.lua",
    "Switch.lua",
    "Stutter.lua",
    "Monitor.lua",
    "Panel.lua",
    "Dev.lua",
    "DevWindow.lua",
    "Core.lua"
)

function Resolve-RetailRoot {
    param([string]$Path)

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (Test-Path -LiteralPath (Join-Path $resolved "_retail_")) {
        $resolved = Join-Path $resolved "_retail_"
    }

    $interface = Join-Path $resolved "Interface"
    $leaf = Split-Path -Leaf $resolved
    $looksLikeWow =
        (Test-Path -LiteralPath (Join-Path $resolved "Wow.exe")) -or
        (Test-Path -LiteralPath $interface) -or
        ($leaf -eq "_retail_")

    if (-not $looksLikeWow) {
        throw "'$resolved' does not look like a World of Warcraft _retail_ folder (no Wow.exe and no Interface directory)."
    }
    return $resolved
}

$retailRoot = Resolve-RetailRoot -Path $WowRoot
$destination = Join-Path (Join-Path (Join-Path $retailRoot "Interface") "AddOns") $addonName

if ($DryRun) {
    Write-Host "Dry run: would deploy to $destination"
    foreach ($file in $runtimeFiles) {
        $source = Join-Path $repoRoot $file
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Missing runtime file: $source"
        }
        Write-Host "  copy $file"
    }
    exit 0
}

New-Item -ItemType Directory -Path $destination -Force | Out-Null

foreach ($file in $runtimeFiles) {
    $source = Join-Path $repoRoot $file
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Missing runtime file: $source"
    }
    Copy-Item -LiteralPath $source -Destination $destination -Force
    Write-Host "copied $file"
}

Write-Host "CrowdCalm deployed to $destination"
Write-Host "Restart the game (or /reload) to load the addon."
