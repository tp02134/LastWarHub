param([switch]$NoBrowser,[switch]$NoCollector)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent

function Get-LivePowerShell([string]$PidFile){
    if(-not (Test-Path $PidFile)){return $null}
    try{
        $processId=[int](Get-Content $PidFile -Raw -ErrorAction Stop)
        $process=Get-Process -Id $processId -ErrorAction Stop
        if($process.ProcessName -eq 'powershell'){return $process}
    }catch{}
    return $null
}
function Test-LocalPort([int]$Port){
    $client=[Net.Sockets.TcpClient]::new()
    try{
        $pending=$client.BeginConnect([Net.IPAddress]::Loopback,$Port,$null,$null)
        if(-not $pending.AsyncWaitHandle.WaitOne(300)){return $false}
        $client.EndConnect($pending)
        return $client.Connected
    }catch{return $false}finally{$client.Dispose()}
}

$serverPidFile=Join-Path $root 'data\local-server.pid'
$serverRunning=Test-LocalPort 8080
if(-not $serverRunning){
    $sessionPath=Join-Path $root 'data\ui-session.json'
    $previousUid=''
    $contextPath=Join-Path $root 'data\account-context.json'
    if(Test-Path $contextPath){try{$previousUid=[string](Get-Content $contextPath -Raw -Encoding UTF8 | ConvertFrom-Json).uid}catch{}}
    @{startedAt=(Get-Date).ToString('o');previousUid=$previousUid;accountVerified=$false;reuseStored=$false} | ConvertTo-Json | Set-Content ($sessionPath+'.tmp') -Encoding UTF8
    Move-Item -LiteralPath ($sessionPath+'.tmp') -Destination $sessionPath -Force
}

# Keep stored data on disk, but only publish data collected during this run.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'BuildSeasonSite.ps1') | Out-Null

if(-not $serverRunning){
    $serverScript=Join-Path $PSScriptRoot 'StartLocalServer.ps1'
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$serverScript+'"') | Out-Null
}

if(-not $NoCollector){
    $collectorPidFile=Join-Path $root 'data\npcap-worker.pid'
    if(-not (Get-LivePowerShell $collectorPidFile)){
        $stopFile=Join-Path $root 'data\npcap-stop.flag'
        if(Test-Path $stopFile){Remove-Item -LiteralPath $stopFile -Force}
        $collectorScript=Join-Path $PSScriptRoot 'WatchNpcap.ps1'
        try{
            Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$collectorScript+'"') | Out-Null
        }catch{
            Write-Warning 'Collector launch was cancelled. The saved dashboard can still be opened.'
        }
    }
}

$url='http://localhost:8080/'
$ready=$false
for($i=0;$i -lt 30;$i++){
    if(Test-LocalPort 8080){$ready=$true;break}
    Start-Sleep -Milliseconds 250
}
if(-not $ready){throw 'The local server did not start. Check data\local-server-error.log.'}
if(-not $NoBrowser){Start-Process $url}
Write-Output $url
