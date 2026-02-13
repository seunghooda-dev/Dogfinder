param(
  [int]$Port = 8080,
  [string[]]$DartDefine = @(),
  [string]$DartDefineString = "",
  [switch]$KillExisting
)

& "$PSScriptRoot\run-device.ps1" -Device "chrome" -Port $Port -DartDefine $DartDefine -DartDefineString $DartDefineString -KillExisting:$KillExisting
