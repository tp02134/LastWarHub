param([string]$CaptureDirectory,[string]$FramesFile,[switch]$QuietStatus)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$status=Join-Path $root 'data\collection-status.json'
function State($s,$detail=''){ if(-not $QuietStatus){@{state=$s;detail=$detail;at=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content $status -Encoding UTF8} }
try {
    State 'starting'
    $dest=if($FramesFile){Split-Path (Resolve-Path $FramesFile)}elseif($CaptureDirectory){(Resolve-Path -LiteralPath $CaptureDirectory).Path}else{Join-Path $root ('data\capture-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))}
    if(-not $CaptureDirectory -and -not $FramesFile){ & (Join-Path $PSScriptRoot 'CaptureSeason.ps1') -Seconds 60 -Destination $dest -ReportStatus }
    State 'processing'
    if(-not $FramesFile){ & (Join-Path $PSScriptRoot 'SummarizeCapture.ps1') -Path (Join-Path $dest 'season.pcapng') | Out-Null }
    $inputFrames=if($FramesFile){$FramesFile}else{Join-Path $dest 'server-stream.bin'}
    & (Join-Path $PSScriptRoot 'DecodeSeasonStream.ps1') -Path $inputFrames | Out-Null
    $messages=Get-Content (Join-Path $dest 'decoded.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    # Publish packet arrival before imports and HTML generation finish so the UI
    # can turn its receipt lights on as soon as the requested response is decoded.
    $detected=@()
    if($messages | Where-Object {$_.p.c -eq 'dragon.assign.player.info'} | Select-Object -First 1){$detected+='heroPower'}
    if($messages | Where-Object {$_.p.c -eq 'al.battle.rank.info' -and [string]$_.p.p.type -eq '1'} | Select-Object -First 1){$detected+='weeklyScore'}
    if($detected.Count){
        $signalPath=Join-Path $root 'data\packet-signal.json'
        $eventTimes=[ordered]@{}
        if(Test-Path $signalPath){
            try{
                $previousSignal=Get-Content $signalPath -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach($property in $previousSignal.eventTimes.PSObject.Properties){$eventTimes[$property.Name]=[string]$property.Value}
            }catch{}
        }
        $detectedAt=(Get-Date).ToString('o')
        foreach($eventName in $detected){$eventTimes[$eventName]=$detectedAt}
        @{detectedAt=$detectedAt;events=$detected;eventTimes=$eventTimes} | ConvertTo-Json -Depth 4 | Set-Content ($signalPath+'.tmp') -Encoding UTF8
        Move-Item -LiteralPath ($signalPath+'.tmp') -Destination $signalPath -Force
    }
    # Resolve the signed-in account before caching any account-scoped responses.
    # Otherwise a newly signed-in account can accidentally reuse the previous
    # account's chat vote cache.
    $accountState=& (Join-Path $PSScriptRoot 'UpdateAccountContext.ps1') -Path (Join-Path $dest 'decoded.json')
    $voteDir=$null
    $accountContextPath=Join-Path $root 'data\account-context.json'
    if(Test-Path $accountContextPath){
        $accountContext=Get-Content $accountContextPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if($accountContext.uid){
            $profileKey=([string]$accountContext.uid+'-'+[string]$accountContext.allianceId) -replace '[^A-Za-z0-9_.-]','_'
            $voteDir=Join-Path $root ('data\profiles\'+$profileKey+'\observed-votes')
        }
    }
    $observed=Join-Path $root 'data\observed-ranks'
    $votePayloadUpdated=$false
    foreach($message in $messages){
        # Retain candidate power responses for verifying additional game screens.
        $candidateJson=$message | ConvertTo-Json -Depth 90
        # Retain alliance chat poll/vote responses for later parsing. Command names vary
        # between client versions, so inspect both the command and payload field names.
        $voteSignal=([string]$message.p.c+' '+$candidateJson)
        $voteCommand=[string]$message.p.c -match '(?i)^(?:alliance\.notice\.list\.info|vote\.list)$'
        $votePayload=$voteSignal -match '(?i)DS\s*[-_ ]?battlefield|CS\s*[-_ ]?battlefield|alliance.{0,40}(?:vote|poll)|(?:vote|poll|ballot).{0,40}(?:option|result|member|user)|"(?:vote|poll)(?:Id|Type|Options?|Result|Users?)?"'
        if($voteDir -and ($voteCommand -or $votePayload)){
            New-Item -ItemType Directory -Path $voteDir -Force | Out-Null
            $voteKey=([string]$message.p.c) -replace '[^A-Za-z0-9_.-]','_'
            if(-not $voteKey){$voteKey='unknown'}
            $stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
            $candidateJson | Set-Content (Join-Path $voteDir ($stamp+'-'+$voteKey+'.json')) -Encoding UTF8
            $candidateJson | Set-Content (Join-Path $voteDir ('latest-'+$voteKey+'.json')) -Encoding UTF8
            $votePayloadUpdated=$true
        }
        if($message.p.c -notmatch '(?i)login|auth|token' -and ($message.p.c -match '(?i)desert|battlefield' -or $candidateJson -match '"(?:heroPower|totalHeroPower|hero_power)"\s*:')){
            $candidateDir=Join-Path $root 'data\observed-power'
            New-Item -ItemType Directory -Path $candidateDir -Force | Out-Null
            $candidateKey=([string]$message.p.c) -replace '[^A-Za-z0-9_.-]','_'
            $candidateJson | Set-Content (Join-Path $candidateDir ($candidateKey+'.json')) -Encoding UTF8
        }
        if($message.p.c -match 'rank'){
            New-Item -ItemType Directory -Path $observed -Force | Out-Null
            $key=([string]$message.p.c+'-'+[string]$message.p.p.rankName+'-'+[string]$message.p.p.rank_type+'-'+[string]$message.p.p.type+'-'+[string]$message.p.p.event_id) -replace '[^A-Za-z0-9_.-]','_'
            $message | ConvertTo-Json -Depth 90 | Set-Content (Join-Path $observed ($key+'.json')) -Encoding UTF8
        }
    }
    $csv=Join-Path $root 'data\season-ranks.csv'
    $rows=@(if(Test-Path $csv){Import-Csv $csv})
    $updated=@()
    foreach($event in @('120021','120022','120023','120024')) {
        $m=$messages | Where-Object {$_.p.c -eq 'lw.season.alliance.devotes.rank.info' -and $_.p.p.event_id -eq $event} | Select-Object -Last 1
        if($m -and $m.p.p.ranks.Count -gt 0) {
            $rows=@($rows | Where-Object {$_.EventId -ne $event})
            $rows+=@($m.p.p.ranks | ForEach-Object {[pscustomobject]@{EventId=$event;Rank=$_.rank;Name=$_.name;Alliance=$_.abbr;Score=$_.score;UserId=$_.uid}})
            $updated+=$event
        }
    }
    $heroUpdated=& (Join-Path $PSScriptRoot 'ImportHeroPower.ps1') -Path (Join-Path $dest 'decoded.json')
    if($heroUpdated){$updated+='heroPower'}
    $memberUpdated=& (Join-Path $PSScriptRoot 'ImportMemberPower.ps1') -Path (Join-Path $dest 'decoded.json')
    if($memberUpdated){$updated+='memberPower'}
    $weeklyUpdated=& (Join-Path $PSScriptRoot 'ImportWeeklyScore.ps1') -Path (Join-Path $dest 'decoded.json')
    if($weeklyUpdated){$updated+='weeklyScore'}
    $dsVoteUpdated=if($voteDir -and $votePayloadUpdated){& (Join-Path $PSScriptRoot 'ImportChatVote.ps1') -SourceDir $voteDir -TitlePattern '(?i)DS\s*[-_ ]?Battlefield' -OutputFile 'ds-battlefield-vote.json'}else{$false}
    if($dsVoteUpdated){$updated+='dsVote'}
    $csVoteUpdated=if($voteDir -and $votePayloadUpdated){& (Join-Path $PSScriptRoot 'ImportChatVote.ps1') -SourceDir $voteDir -TitlePattern '(?i)CS\s*[-_ ]?Battlefield' -OutputFile 'cs-battlefield-vote.json'}else{$false}
    if($csVoteUpdated){$updated+='csVote'}
    if($accountState -in @('switched','updated')){$updated+='account'}
    if($updated.Count -eq 0){ State 'no_data' 'No ranking response received. Existing data retained.'; return }
    if($rows.Count){$rows | Export-Csv ($csv+'.tmp') -NoTypeInformation -Encoding UTF8}else{Set-Content ($csv+'.tmp') '"EventId","Rank","Name","Alliance","Score","UserId"' -Encoding UTF8}
    Move-Item -LiteralPath ($csv+'.tmp') -Destination $csv -Force
    $times=@{}
    $timePath=Join-Path $root 'data\event-updates.json'
    if(Test-Path $timePath){$meta=Get-Content $timePath -Raw -Encoding UTF8 | ConvertFrom-Json;foreach($p in $meta.PSObject.Properties){$times[$p.Name]=$p.Value}}
    $capturedAt=(Get-Item $inputFrames).LastWriteTime.ToString('o')
    foreach($event in $updated | Where-Object {$_ -notin @('heroPower','memberPower','weeklyScore','dsVote','csVote','account')}){$times[$event]=$capturedAt}
    ConvertTo-Json -InputObject $times | Set-Content $timePath -Encoding UTF8
    @{capturedAt=(Get-Date).ToString('o');events=$updated} | ConvertTo-Json | Set-Content (Join-Path $root 'data\last-collection.json') -Encoding UTF8
    & (Join-Path $PSScriptRoot 'BuildSeasonSite.ps1') | Out-Null
    State 'complete' ($updated -join ',')
} catch {State 'error' $_.Exception.Message; throw}
