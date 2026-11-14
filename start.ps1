# Launch a family watch in the Connect IQ simulator (Windows version of start.sh).
#
#   .\start.ps1 mom                          Mom's watch, local server
#   .\start.ps1 son                          Son's watch, local server
#   .\start.ps1 son http://<laptop-ip>:3000  Use another laptop's server
#
# If Windows blocks the script ("running scripts is disabled"), run it as:
#   powershell -ExecutionPolicy Bypass -File .\start.ps1 son http://<laptop-ip>:3000
#
# The persona and server URL are built into the app, so each watch knows who
# it is and which server it's talking to. It shows the server on screen and
# prints it to the console.
#
# Works in Windows PowerShell 5.1 and PowerShell 7+.

param(
    [Parameter(Position = 0)] [string] $Who,
    [Parameter(Position = 1)] [string] $Server
)

# No 'Stop' preference on purpose: Windows PowerShell 5.1 turns any stderr
# output from native tools (monkeyc prints warnings there) into errors.
$ErrorActionPreference = 'Continue'

$Root = $PSScriptRoot
$Device = if ($env:DEVICE) { $env:DEVICE } else { 'fenix7pro' }

function Show-Usage {
    @'
Usage: .\start.ps1 <mom|son> [server-url]

  mom | son    Which persona this watch takes
  server-url   Server to use (default $env:FAMILY_API, else http://localhost:3000).
               A localhost server is started for you if it isn't running.

Env: DEVELOPER_KEY (defaults to VS Code's monkeyC.developerKeyPath), DEVICE (default fenix7pro)
'@ | Write-Host
}

function Fail([string] $Message) {
    Write-Host "error: $Message" -ForegroundColor Red
    exit 1
}

switch -Regex ($Who) {
    '^(mom|mother)$'      { $Who = 'mom'; break }
    '^son$'               { $Who = 'son'; break }
    '^(-h|--help|help)$'  { Show-Usage; exit 0 }
    '^$'                  { Show-Usage; exit 1 }
    default               { Write-Host "Unknown persona: $Who" -ForegroundColor Red; Show-Usage; exit 1 }
}

if (-not $Server) { $Server = if ($env:FAMILY_API) { $env:FAMILY_API } else { 'http://localhost:3000' } }
$Server = $Server.TrimEnd('/')
if ($Server -notmatch '^https?://') { Fail "server URL must start with http:// or https:// (got '$Server')" }

# ---- Connect IQ SDK + developer key ------------------------------------------
$monkeyc = Get-Command monkeyc.bat -ErrorAction SilentlyContinue
if ($monkeyc) {
    $SdkBin = Split-Path $monkeyc.Source
} else {
    $sdks = Join-Path $env:APPDATA 'Garmin\ConnectIQ\Sdks'
    $sdk = Get-ChildItem $sdks -Directory -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
    if (-not $sdk) { Fail "Connect IQ SDK not found in $sdks. Install it with the Connect IQ SDK Manager." }
    $SdkBin = Join-Path $sdk.FullName 'bin'
}

$Key = $env:DEVELOPER_KEY
$vscodeSettings = Join-Path $env:APPDATA 'Code\User\settings.json'
if (-not $Key -and (Test-Path $vscodeSettings)) {
    # Regex, not ConvertFrom-Json: VS Code settings files often contain comments.
    $m = [regex]::Match((Get-Content $vscodeSettings -Raw), '"monkeyC\.developerKeyPath"\s*:\s*"([^"]*)"')
    if ($m.Success) { $Key = $m.Groups[1].Value -replace '\\\\', '\' }
}
if (-not $Key -or -not (Test-Path $Key)) {
    Fail "developer key not found. Set `$env:DEVELOPER_KEY = 'C:\path\to\developer_key', or run 'Monkey C: Generate a Developer Key' in VS Code."
}

# ---- Server ------------------------------------------------------------------
# True only when our server answers, not just anything on that address.
function Test-Server {
    try {
        $r = Invoke-RestMethod -Uri "$Server/" -TimeoutSec 3 -ErrorAction Stop
        return ($r.service -eq 'family-wellness')
    } catch {
        return $false
    }
}

function Test-Simulator {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $connect = $client.BeginConnect('127.0.0.1', 1234, $null, $null)
        return ($connect.AsyncWaitHandle.WaitOne(300) -and $client.Connected)
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

$serverProcess = $null
try {
    if (Test-Server) {
        Write-Host "Server: $Server"
    } elseif ($Server -match '^http://(localhost|127\.0\.0\.1):(\d+)$') {
        $port = $Matches[2]
        Write-Host "Server: starting $Server (log: bin\server.log; stops when this script exits)"
        New-Item -ItemType Directory -Force (Join-Path $Root 'bin') | Out-Null
        $serverDir = Join-Path $Root 'server'
        if (-not (Test-Path (Join-Path $serverDir 'node_modules'))) {
            Push-Location $serverDir
            & npm install --no-audit --no-fund --silent
            Pop-Location
        }
        $oldPort = $env:PORT
        $env:PORT = $port
        $serverProcess = Start-Process -FilePath 'node' -ArgumentList 'src/index.js' -WorkingDirectory $serverDir `
            -RedirectStandardOutput (Join-Path $Root 'bin\server.log') `
            -RedirectStandardError (Join-Path $Root 'bin\server.err.log') `
            -NoNewWindow -PassThru
        $env:PORT = $oldPort
        for ($i = 0; $i -lt 50 -and -not (Test-Server); $i++) { Start-Sleep -Milliseconds 200 }
        if (-not (Test-Server)) { Fail "server didn't start; see bin\server.log and bin\server.err.log" }
    } else {
        Fail "can't reach the server at $Server. Is it running on that laptop, and are you on the same network?"
    }

    # ---- Build with this persona + server baked in (see Config.launchIdentity) ---
    $launchDir = Join-Path $Root 'bin\launch'
    New-Item -ItemType Directory -Force $launchDir | Out-Null
    @"
// Generated by start.ps1. Do not edit.
import Toybox.Lang;

module Config {
    function launchIdentity() as String? { return "$Who"; }
    function launchServerUrl() as String? { return "$Server"; }
}
"@ | Set-Content -Path (Join-Path $launchDir 'Launch.mc') -Encoding ASCII
    # Paths in this file are relative to bin\.
    "base.sourcePath = ../source;launch`nbase.excludeAnnotations = notLaunched" |
        Set-Content -Path (Join-Path $Root 'bin\launch.jungle') -Encoding ASCII

    $prg = Join-Path $Root "bin\family-$Who.prg"
    Remove-Item $prg -ErrorAction SilentlyContinue
    Write-Host "Building $Who's watch for $Device..."
    Push-Location $Root
    & "$SdkBin\monkeyc.bat" -f 'monkey.jungle;bin/launch.jungle' -d $Device -o $prg -y $Key 2>&1 |
        ForEach-Object { "$_" } |
        Where-Object { $_ -notmatch 'No supported languages|launcher icon|container access' } |
        Write-Host
    Pop-Location
    if (-not (Test-Path $prg)) { Fail "build failed" }

    # ---- Simulator (one per machine) -----------------------------------------------
    if (-not (Test-Simulator)) {
        Write-Host "Starting the Connect IQ simulator..."
        $simExe = Join-Path $SdkBin 'simulator.exe'
        if (Test-Path $simExe) {
            Start-Process -FilePath $simExe | Out-Null
        } else {
            Start-Process -FilePath (Join-Path $SdkBin 'connectiq.bat') -WindowStyle Minimized | Out-Null
        }
        for ($i = 0; $i -lt 60 -and -not (Test-Simulator); $i++) { Start-Sleep -Milliseconds 500 }
        if (-not (Test-Simulator)) { Fail "the simulator didn't start. Open it from the Connect IQ SDK Manager and run this again." }
    }
    if ($Server -like 'http://*') {
        Write-Host 'Note: in the simulator, untick Settings > "Use Device HTTPS Requirements" (otherwise requests fail with -1001).'
    }

    Write-Host ""
    Write-Host "Running as $Who -> $Server. Console output below; Ctrl-C to stop."
    Write-Host ""
    & "$SdkBin\monkeydo.bat" $prg $Device
}
finally {
    if ($serverProcess -and -not $serverProcess.HasExited) {
        Stop-Process -Id $serverProcess.Id -ErrorAction SilentlyContinue
    }
}
