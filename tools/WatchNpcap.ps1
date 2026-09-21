$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$statusPath=Join-Path $root 'data\collection-status.json'
$stopPath=Join-Path $root 'data\npcap-stop.flag'
$work=Join-Path $root 'data\npcap-live'
$reader=$null
$lock=[Threading.Mutex]::new($false,'Local\LastwarHubNpcapCollector')
if(-not $lock.WaitOne(0)) {throw 'Collector already running.'}
function Publish($state,$detail=''){
    $last=$null;$lastPath=Join-Path $root 'data\last-collection.json'
    if(Test-Path $lastPath){try{$last=Get-Content $lastPath -Raw -Encoding UTF8 | ConvertFrom-Json}catch{}}
    $value=@{state=$state;detail=$detail;mode='npcap';at=(Get-Date).ToString('o');lastUpdate=$last;packets=0;frames=0;interfaces=0;gaps=0}
    if($reader){$value.packets=$reader.Packets;$value.frames=$reader.Frames;$value.interfaces=$reader.InterfaceCount;$value.gaps=$reader.Gaps}
    $value | ConvertTo-Json -Depth 6 | Set-Content ($statusPath+'.tmp') -Encoding UTF8
    Move-Item -LiteralPath ($statusPath+'.tmp') -Destination $statusPath -Force
}
try{
    Set-Content (Join-Path $root 'data\npcap-worker.pid') $PID
    if(Test-Path $stopPath){Remove-Item -LiteralPath $stopPath}
    if(-not (Test-Path "$env:WINDIR\System32\Npcap\wpcap.dll")){throw 'Npcap is not installed.'}
    Add-Type -Path (Join-Path $root 'collector\NpcapReader.cs')
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $refresh=[DateTime]::MinValue;$publish=[DateTime]::MinValue;$connections=@();$activeIdentity='';$batch=[Collections.Generic.List[byte]]::new();$lastBatch=Get-Date
    while(-not (Test-Path $stopPath)){
        if(-not $reader){try{$reader=[LastwarHub.NpcapReader]::new()}catch{Publish 'reconnecting' $_.Exception.Message;Start-Sleep -Seconds 3;continue}}
        if(((Get-Date)-$refresh).TotalSeconds -ge 3){
            $game=Get-Process LastWar -ErrorAction SilentlyContinue
            $connections=@()
            if($game){$connections=@(Get-NetTCPConnection -OwningProcess $game.Id -State Established -ErrorAction SilentlyContinue | Where-Object {$_.RemotePort -ge 10000 -and $_.RemotePort -le 13000 -and $_.RemoteAddress -notmatch ':'})}
            $allowed=[string[]]@($connections | ForEach-Object {"$($_.RemoteAddress):$($_.RemotePort)>$($_.LocalAddress):$($_.LocalPort)"})
            $reader.SetAllowed($allowed);$refresh=Get-Date
            if($connections.Count){
                $serverId=[int]$connections[0].RemotePort-10000
                $mailRoot=Join-Path $env:USERPROFILE 'AppData\LocalLow\FunFly\Last War-Survival Game\FileContents\MailContents'
                $accountDir=Get-ChildItem $mailRoot -Directory -ErrorAction SilentlyContinue | Where-Object {$_.Name -match '^\d+$' -and $_.Name.EndsWith($serverId.ToString('0000'))} | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if($accountDir){
                    $identity=$accountDir.Name+'@'+$serverId
                    @{uid=$accountDir.Name;serverId=$serverId;detectedAt=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $root 'data\connection-account.json.tmp') -Encoding UTF8
                    Move-Item -LiteralPath (Join-Path $root 'data\connection-account.json.tmp') -Destination (Join-Path $root 'data\connection-account.json') -Force
                    if($identity -ne $activeIdentity){
                        $accountState=& (Join-Path $PSScriptRoot 'UpdateAccountContext.ps1') -Uid $accountDir.Name -ServerId $serverId -ServerName ('State#'+$serverId)
                        $activeIdentity=$identity
                        if($accountState -in @('switched','updated')){
                            @{capturedAt=(Get-Date).ToString('o');events=@('account')} | ConvertTo-Json | Set-Content (Join-Path $root 'data\last-collection.json') -Encoding UTF8
                            & (Join-Path $PSScriptRoot 'BuildSeasonSite.ps1') | Out-Null
                        }
                    }
                }
            }
        }
        try{foreach($frame in $reader.Poll()){$batch.AddRange([byte[]]$frame)}}catch{$reader.Dispose();$reader=$null;Publish 'reconnecting';continue}
        if($batch.Count -gt 0 -and (((Get-Date)-$lastBatch).TotalSeconds -ge 0.5 -or $batch.Count -gt 8388608)){
            $file=Join-Path $work 'server-stream.bin'
            [IO.File]::WriteAllBytes($file,$batch.ToArray());$batch.Clear();$lastBatch=Get-Date
            try{& (Join-Path $PSScriptRoot 'CollectAndRefresh.ps1') -FramesFile $file -QuietStatus | Out-Null;Publish 'watching';$publish=Get-Date}catch{Publish 'watching' ('Last batch could not be decoded: '+$_.Exception.Message)}
        }
        if(((Get-Date)-$publish).TotalSeconds -ge 0.5){Publish $(if($connections.Count){'watching'}else{'waiting_game'});$publish=Get-Date}
        Start-Sleep -Milliseconds 50
    }
    Publish 'stopped'
}catch{Publish 'error' $_.Exception.Message}finally{if($reader){$reader.Dispose()};$lock.ReleaseMutex();$lock.Dispose()}
