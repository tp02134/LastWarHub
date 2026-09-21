$ErrorActionPreference='SilentlyContinue'
$root=Split-Path $PSScriptRoot -Parent
Set-Content (Join-Path $root 'data\npcap-stop.flag') 'stop' -Encoding ASCII

$serverPidFile=Join-Path $root 'data\local-server.pid'
if(Test-Path $serverPidFile){
    $serverPid=[int](Get-Content $serverPidFile -Raw)
    $server=Get-Process -Id $serverPid -ErrorAction SilentlyContinue
    if($server -and $server.ProcessName -eq 'powershell'){Stop-Process -Id $serverPid -Force}
}
Write-Output 'LastwarHub stopped.'
