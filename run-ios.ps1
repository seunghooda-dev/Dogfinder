param(
  [string[]]$DartDefine = @(),
  [string]$DartDefineString = "",
  [switch]$KillExisting,
  [switch]$Release
)

& "$PSScriptRoot\run-device.ps1" -Device "ios" -DartDefine $DartDefine -DartDefineString $DartDefineString -KillExisting:$KillExisting -Release:$Release
