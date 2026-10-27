$ErrorActionPreference = "Stop"

function Set-Range3DConsoleIcon {
  $IconPath = Join-Path $PSScriptRoot "Range3D.ico"
  if (-not (Test-Path -LiteralPath $IconPath -PathType Leaf)) {
    Write-Warning "Range3D.ico was not found beside the launcher; using the default console icon."
    return
  }

  try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop

    if (-not ("Range3DConsoleIconNative" -as [type])) {
      $NativeCode = @"
using System;
using System.Runtime.InteropServices;

public static class Range3DConsoleIconNative
{
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll", EntryPoint = "SendMessageW", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessage(
        IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);
}
"@
      Add-Type -TypeDefinition $NativeCode -ErrorAction Stop | Out-Null
    }

    $ConsoleWindow = [Range3DConsoleIconNative]::GetConsoleWindow()
    if ($ConsoleWindow -eq [IntPtr]::Zero) {
      Write-Warning "Could not find the Range3D console window; using the default icon."
      return
    }

    # Keep both Icon objects alive for the full collection session so Windows
    # retains valid native icon handles for the taskbar and title bar.
    $script:Range3DSmallIcon = [System.Drawing.Icon]::new($IconPath, 16, 16)
    $script:Range3DBigIcon = [System.Drawing.Icon]::new($IconPath, 32, 32)

    $WM_SETICON = [uint32]0x0080
    $ICON_SMALL = [IntPtr]::Zero
    $ICON_BIG = [IntPtr]1
    [void][Range3DConsoleIconNative]::SendMessage(
      $ConsoleWindow, $WM_SETICON, $ICON_SMALL, $script:Range3DSmallIcon.Handle)
    [void][Range3DConsoleIconNative]::SendMessage(
      $ConsoleWindow, $WM_SETICON, $ICON_BIG, $script:Range3DBigIcon.Handle)
  } catch {
    Write-Warning "Could not set the Range3D console icon: $($_.Exception.Message)"
  }
}

Set-Range3DConsoleIcon

$ConfigPath = Join-Path $PSScriptRoot "range3d-config.json"
$Collector = Join-Path $PSScriptRoot "range3d_collect.py"

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
  Write-Host ""
  Write-Host "ERROR: Range3D configuration was not found next to this launcher." -ForegroundColor Red
  Write-Host "You may have started the source copy from the visualizer repository's 'windows\launchers' folder."
  Write-Host "Run the installed launcher from the Dump1090 folder:"
  Write-Host "  range3d-tools\Start-Range3D.cmd"
  Write-Host "The installer places range3d-config.json and range3d_collect.py beside that installed launcher."
  Write-Host "If the installed launcher is missing, run windows\3dRange-Install-Win.ps1 from the visualizer repository with -Dump1090Root <path-to-Dump1090>."
  exit 2
}
if (-not (Test-Path -LiteralPath $Collector -PathType Leaf)) {
  Write-Host ""
  Write-Host "ERROR: range3d_collect.py is missing next to this launcher." -ForegroundColor Red
  Write-Host "Run range3d-tools\Start-Range3D.cmd from the Dump1090 folder. If the installed files are missing, rerun the visualizer installer."
  exit 2
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
