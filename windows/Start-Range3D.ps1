$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "range3d-config.json"
$Collector = Join-Path $PSScriptRoot "range3d_collect.py"

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
  throw "Missing $ConfigPath. Run windows\Install-Windows.ps1 from the visualizer repository first."
}
if (-not (Test-Path -LiteralPath $Collector -PathType Leaf)) {
  throw "Missing collector: $Collector"
}
$Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

$Py = Get-Command py.exe -ErrorAction SilentlyContinue
if ($Py) {
  $PythonCommand = $Py.Source
  $PythonPrefix = @("-3")
} else {
  $Py = Get-Command python.exe -ErrorAction SilentlyContinue
  if (-not $Py) { $Py = Get-Command python -ErrorAction SilentlyContinue }
  if (-not $Py) { throw "Python 3 was not found. Install Python 3 and add it to PATH." }
  $PythonCommand = $Py.Source
  $PythonPrefix = @()
}

$CollectorArgs = @(
  "--base-url", [string]$Config.baseUrl,
  "--state", [string]$Config.stateFile
)
if ($null -ne $Config.rxAltFt -and [double]$Config.rxAltFt -ge 0) {
  $CollectorArgs += @("--rx-alt-ft", [string]$Config.rxAltFt)
}
$CollectorArgs += @("collect", "--interval", "1.0", "--save-every", "60")

Write-Host "Range3D collector"
Write-Host "Dump1090: $($Config.baseUrl)"
Write-Host "State:    $($Config.stateFile)"
Write-Host "Stop with Ctrl+C. Keep this window open while collecting."
Write-Host ""

& $PythonCommand @PythonPrefix $Collector @CollectorArgs
if ($LASTEXITCODE -ne 0) {
  throw "Range3D collector exited with code $LASTEXITCODE"
}
