# CrowdCalmLab deploy helper — copies or junction-links the addon into a
# WoW installation the owner points at. There are NO personal paths here:
# -WowRoot is mandatory on purpose (owner brief: never bake in a real install).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1 -WowRoot "D:\Games\World of Warcraft"
#   ... -Clients _retail_            (only one client)
#   ... -Copy                        (copy files instead of a junction)
#   ... -DryRun                      (print what would happen; touch nothing)
#
# Junctions are preferred (instant, no duplicate disk use) and fall back to
# a recursive copy if New-Item -ItemType Junction fails on this filesystem.

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$WowRoot,

  [string[]]$Clients = @("_retail_", "_classic_beta_"),

  [switch]$Copy,

  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $WowRoot)) {
  throw "WowRoot does not exist: $WowRoot"
}

$src = Join-Path $PSScriptRoot "..\CrowdCalmLab\CrowdCalmLab"
$src = (Resolve-Path -LiteralPath $src).Path

foreach ($client in $Clients) {
  $targetDir = Join-Path $WowRoot (Join-Path $client "Interface\AddOns")
  if (-not (Test-Path -LiteralPath $targetDir)) {
    Write-Warning "skipping $client (no Interface\AddOns under $WowRoot)"
    continue
  }
  $dest = Join-Path $targetDir "CrowdCalmLab"

  if ($DryRun) {
    Write-Host "DRYRUN would deploy: $src -> $dest (mode=$(if ($Copy) { 'copy' } else { 'junction' }))"
    continue
  }

  if (Test-Path -LiteralPath $dest) {
    Write-Host "removing previous deployment: $dest"
    Remove-Item -LiteralPath $dest -Recurse -Force
  }

  if (-not $Copy) {
    try {
      New-Item -ItemType Junction -Path $dest -Target $src | Out-Null
      Write-Host "junctioned: $dest -> $src"
      continue
    } catch {
      Write-Warning "junction failed ($($_.Exception.Message)); falling back to copy"
    }
  }

  Copy-Item -LiteralPath $src -Destination $dest -Recurse
  Write-Host "copied: $src -> $dest"
}

Write-Host "done."
