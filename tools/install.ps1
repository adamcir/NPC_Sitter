param([Parameter(Position=0)][string]$GarrysModPath)
$ErrorActionPreference = "Stop"
$source = Join-Path (Split-Path -Parent $PSScriptRoot) "addon/npc_sitter"
if (-not (Test-Path -LiteralPath (Join-Path $source "lua") -PathType Container)) { throw "Addon source not found: $source" }
if ([string]::IsNullOrWhiteSpace($GarrysModPath)) {
    $GarrysModPath = Join-Path ([Environment]::GetEnvironmentVariable("ProgramFiles(x86)")) "Steam/steamapps/common/GarrysMod/garrysmod"
}
if (-not (Test-Path -LiteralPath (Join-Path $GarrysModPath "addons") -PathType Container)) { throw "Invalid Garrys Mod folder: $GarrysModPath" }
$gmod = (Resolve-Path -LiteralPath $GarrysModPath).ProviderPath
if ((Split-Path -Leaf $gmod) -ine "garrysmod") { throw "Expected the garrysmod directory" }
$source = (Resolve-Path -LiteralPath $source).ProviderPath
$dest = Join-Path $gmod "addons/npc_sitter"
if ($source.TrimEnd('\','/') -ieq $dest.TrimEnd('\','/')) { throw "Source and destination must be different" }
if (Test-Path -LiteralPath $dest) {
    Write-Host "Removing old NPC Sitter..."
    Remove-Item -LiteralPath $dest -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -Path (Join-Path $source "*") -Destination $dest -Recurse -Force
Write-Host "NPC Sitter installed to: $dest"
