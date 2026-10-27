[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Dump1090Root,
  [string]$WebRoot,
  [ValidateRange(1,65535)][int]$Port = 8080,
  [double]$AntennaAltitudeFt = -1,
  [switch]$SkipBasemap
)
$ErrorActionPreference = "Stop"

function Resolve-Python {
  $p = Get-Command py.exe -ErrorAction SilentlyContinue
  if ($p) { return @{ Command = $p.Source; Prefix = @("-3") } }
  $p = Get-Command python.exe -ErrorAction SilentlyContinue
  if ($p) { return @{ Command = $p.Source; Prefix = @() } }
  $p = Get-Command python -ErrorAction SilentlyContinue
  if ($p) { return @{ Command = $p.Source; Prefix = @() } }
  throw "Python 3 is required. Install Python 3 and add py -3 or python to PATH."
}

$Dump1090Root = (Resolve-Path -LiteralPath $Dump1090Root).Path
$SourceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$SourceViewer = Join-Path $SourceRoot "viewer"
$SourceCollector = Join-Path $SourceRoot "collector\range3d_collect.py"
$SourceBasemapTool = Join-Path $SourceRoot "tools\fetch-basemap.py"
$SourceLauncherIcon = Join-Path $PSScriptRoot "launchers\Range3D.ico"
if (-not (Test-Path -LiteralPath $SourceViewer -PathType Container)) { throw "Viewer directory missing: $SourceViewer" }
if (-not (Test-Path -LiteralPath $SourceCollector -PathType Leaf)) { throw "Collector missing: $SourceCollector" }
if (-not (Test-Path -LiteralPath $SourceLauncherIcon -PathType Leaf)) { throw "Range3D launcher icon missing: $SourceLauncherIcon" }
if ([string]::IsNullOrWhiteSpace($WebRoot)) {
  $WebRoot = Join-Path $Dump1090Root "web_root-Tar1090"
} elseif (-not [System.IO.Path]::IsPathRooted($WebRoot)) {
  $WebRoot = Join-Path $Dump1090Root $WebRoot
}
if (-not (Test-Path -LiteralPath $WebRoot -PathType Container)) { throw "Web root missing: $WebRoot. Supply -WebRoot if needed." }
if (-not (Test-Path -LiteralPath (Join-Path $WebRoot "index.html") -PathType Leaf)) { throw "No index.html in $WebRoot. Use -WebRoot to point at the active filesystem web root; packed web-pages.dll roots cannot serve this add-on." }
$WebRoot = (Resolve-Path -LiteralPath $WebRoot).Path

$Python = Resolve-Python
$ViewerDest = Join-Path $WebRoot "range3d"
$StateDir = Join-Path $ViewerDest "state"
$ToolsDir = Join-Path $Dump1090Root "range3d-tools"
$StateFile = Join-Path $StateDir "envelope.json"
$BaseUrl = "http://localhost:$Port"
New-Item -ItemType Directory -Force -Path $ViewerDest, $StateDir, $ToolsDir | Out-Null

# Launcher templates live in windows\launchers; installed copies go beside config and collector in range3d-tools.
# Only the separate range3d folder is installed; Dump1090 source, config and root page are not changed.
Copy-Item -Path (Join-Path $SourceViewer "*") -Destination $ViewerDest -Recurse -Force
Copy-Item -LiteralPath $SourceCollector -Destination (Join-Path $ToolsDir "range3d_collect.py") -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "launchers\Start-Range3D.ps1") -Destination (Join-Path $ToolsDir "Start-Range3D.ps1") -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "launchers\Start-Range3D.cmd") -Destination (Join-Path $ToolsDir "Start-Range3D.cmd") -Force
Copy-Item -LiteralPath $SourceLauncherIcon -Destination (Join-Path $ToolsDir "Range3D.ico") -Force

# Flag this installed copy so the browser uses Dump1090's /data routes, not tar1090 routes.
$IndexFile = Join-Path $ViewerDest "index.html"
$Index = [System.IO.File]::ReadAllText($IndexFile)
$ModuleTag = '<script type="module" src="main.js"></script>'
$Bootstrap = '<script>if (!new URLSearchParams(location.search).has("dump1090")) { const u = new URL(location.href); u.searchParams.set("dump1090", "1"); history.replaceState(null, "", u); }</script>'
if ($Index.Contains($ModuleTag) -and -not $Index.Contains('searchParams.set("dump1090"')) {
  $Index = $Index.Replace($ModuleTag, $Bootstrap + [Environment]::NewLine + $ModuleTag)
  [System.IO.File]::WriteAllText($IndexFile, $Index, [System.Text.UTF8Encoding]::new($false))
}

$Config = [ordered]@{
  baseUrl = $BaseUrl
  stateFile = $StateFile
  webRoot = $WebRoot
  dump1090Root = $Dump1090Root
  rxAltFt = $(if ($AntennaAltitudeFt -ge 0) { $AntennaAltitudeFt } else { $null })
}
$Config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $ToolsDir "range3d-config.json") -Encoding UTF8

Write-Host ""
Write-Host "Installed viewer: $ViewerDest"
Write-Host "State file:       $StateFile"
Write-Host "Dump1090 URL:     $BaseUrl"

if (-not $SkipBasemap -and (Test-Path -LiteralPath $SourceBasemapTool)) {
  try {
    $Receiver = Invoke-RestMethod -Uri "$BaseUrl/data/receiver.json" -TimeoutSec 5
    $Lat = [double]$Receiver.lat
    $Lon = [double]$Receiver.lon
    if (($Lat -ne 0 -or $Lon -ne 0) -and $Lat -ge -90 -and $Lat -le 90 -and $Lon -ge -180 -and $Lon -le 180) {
      Write-Host "Caching local OpenStreetMap tiles (one time; about 70 tiles at zoom 8)..."
      $BasemapArgs = @($SourceBasemapTool, "--out-dir", (Join-Path $ViewerDest "basemap"),
        "--lat", [string]$Lat, "--lon", [string]$Lon, "--radius-nm", "250", "--zoom", "8")
      $InvokeArgs = @($Python.Prefix) + $BasemapArgs
      & $Python.Command @InvokeArgs
      if ($LASTEXITCODE -ne 0) { Write-Warning "Basemap download failed; the viewer will still work without map tiles." }
    } else {
      Write-Warning "receiver.json has no configured position. Set homepos, then re-run the installer to cache map tiles."
    }
  } catch {
    Write-Warning "Could not fetch receiver.json or cache map tiles. Start Dump1090 first and re-run, or use -SkipBasemap."
    Write-Warning $_.Exception.Message
  }
} elseif ($SkipBasemap) {
  Write-Host "Skipping basemap as requested."
}
Write-Host ""
Write-Host "Next:"
Write-Host "  1. Keep Dump1090 running with its HTTP server enabled (usually --interactive --net)."
Write-Host "  2. Confirm homepos in the active dump1090.cfg is your receiver's actual latitude/longitude."
Write-Host "  3. From the Dump1090 folder, run: range3d-tools\Start-Range3D.cmd"
Write-Host "  4. Open: $BaseUrl/range3d/index.html"
Write-Host "The collector runs separately; leave its console open while recording. Ctrl+C saves state and stops collection."
Write-Host "Reinstalling preserves envelope.json."
