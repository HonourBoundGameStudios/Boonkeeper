# Copy Boonkeeper into every installed WoW flavour it ships for, then /reload in the client.
#
# $PSScriptRoot is empty when run via -Command rather than -File (some IDE runners), so fall back to
# the script's resolved path.
$source = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent (Resolve-Path $MyInvocation.MyCommand.Path) }

# Classic Era only for now — see the note in Boonkeeper.toc. Add a root here when a flavour .toc
# exists to go with it, not before: deploying to a client the .toc does not declare shows the addon
# as incompatible and teaches you nothing.
$roots = @(
  "D:\Games\World of Warcraft\_classic_era_"
)

$deployed = $false
foreach ($root in $roots) {
  if (-not (Test-Path $root)) { continue }
  $dest = Join-Path $root "Interface\AddOns\Boonkeeper"
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Path "$source\*.lua" -Destination $dest -Force
  Copy-Item -Path "$source\*.toc" -Destination $dest -Force
  # The studio logo on the About tab. Textures load by path, so the .toc never names them.
  Copy-Item -Path "$source\Media" -Destination $dest -Recurse -Force
  Write-Host "Deployed to $dest"
  $deployed = $true
}

if (-not $deployed) { Write-Warning "No WoW install found under any known root." }
