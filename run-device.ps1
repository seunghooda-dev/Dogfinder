param(
  [Parameter(Mandatory = $true)]
  [string]$Device,
  [int]$Port = 8080,
  [string[]]$DartDefine = @(),
  [string]$DartDefineString = "",
  [switch]$NoKill,
  [switch]$KillExisting,
  [switch]$Release,
  [string]$Target = "lib/main.dart",
  [string]$Flavor = ""
)

$ErrorActionPreference = "Stop"

function Stop-FlutterProcesses {
  param([string]$ProjectRoot)

  $resolvedRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
  $names = @("dart", "flutter", "flutter_tester")
  foreach ($name in $names) {
    $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
    if (-not $procs) {
      continue
    }

    Write-Host "Stopping matching $name process(es) for project root: $resolvedRoot" -ForegroundColor Yellow
    foreach ($p in $procs) {
      try {
        $cmd = $null
        try {
          $cmd = (Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction SilentlyContinue).CommandLine
        } catch {
          $cmd = $p.Path
        }

        if ([string]::IsNullOrWhiteSpace($cmd)) {
          continue
        }

        $normalizedCmd = $cmd.ToLowerInvariant()
        if (($normalizedCmd -notlike "*$($resolvedRoot.ToLowerInvariant())*") -and
            ($normalizedCmd -notlike "*lib/main.dart*")) {
          continue
        }
        Stop-Process -Id $p.Id -Force -ErrorAction Stop
        Write-Host "  - stopped pid $($p.Id)"
      } catch {
        Write-Host "  - failed to stop pid $($p.Id): $($_.Exception.Message)" -ForegroundColor Red
      }
    }
  }
}

if ([string]::IsNullOrWhiteSpace($DartDefineString) -eq $false) {
  $extra = $DartDefineString -split "[,;]" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
  if ($extra.Count -gt 0) {
    $DartDefine = @($DartDefine) + $extra
  }
}

$shouldKillExisting = $false
if ($NoKill) {
  $shouldKillExisting = $false
} elseif ($KillExisting) {
  $shouldKillExisting = $true
}

if ($shouldKillExisting) {
  Stop-FlutterProcesses -ProjectRoot $PSScriptRoot
}

$args = @("run", "-d", $Device)

if ($Release) {
  $args += "--release"
}

if ($Flavor) {
  $args += "--flavor=$Flavor"
}

if ($Target) {
  $args += "--target=$Target"
}

if ($Device.ToLower() -eq "chrome") {
  $args += "--web-port"
  $args += $Port.ToString()
}

foreach ($define in $DartDefine) {
  if ([string]::IsNullOrWhiteSpace($define)) {
    continue
  }
  if ($define -like "--dart-define*") {
    $args += $define
  } else {
    $args += "--dart-define=$define"
  }
}

Write-Host "Start command:"
Write-Host "flutter $($args -join ' ')" -ForegroundColor Cyan

& flutter @args
