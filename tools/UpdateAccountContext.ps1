param([string]$Path,[string]$Uid,[int]$ServerId,[string]$ServerName,[string]$Name,[string]$AllianceId,[string]$Alliance,[string]$AllianceName)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$contextPath=Join-Path $root 'data\account-context.json'
$previous=$null
if(Test-Path $contextPath){try{$previous=Get-Content $contextPath -Raw -Encoding UTF8 | ConvertFrom-Json}catch{}}
if($Path){
    $connectionPath=Join-Path $root 'data\connection-account.json'
    if(-not (Test-Path $connectionPath)){return 'none'}
    $connection=Get-Content $connectionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if(-not $connection.uid){return 'none'}
    $messages=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $candidates=@();$outerAllianceId=''
    foreach($message in $messages){
        if($message.p.c -eq 'get.new.user.info'){$candidates+=@($message.p.p)}
        if($message.p.c -eq 'al.rank' -and $message.p.p.allianceId -and @($message.p.p.list | Where-Object {[string]$_.uid -eq [string]$connection.uid}).Count){$outerAllianceId=[string]$message.p.p.allianceId}
        foreach($field in @('rankInfo','users','ranks','serverRanking','list')){if($message.p.p.$field){$candidates+=@($message.p.p.$field)}}
    }
    $p=$candidates | Where-Object {[string]$_.uid -eq [string]$connection.uid} | Sort-Object @{Expression={if($_.abbr -or $_.allianceId -or $_.aid){1}else{0}};Descending=$true} | Select-Object -First 1
    if(-not $p){return 'none'}
    $Uid=[string]$connection.uid;$ServerId=[int]$connection.serverId;$ServerName=('State#'+$connection.serverId);$Name=[string]$p.name
    $AllianceId=$(if($p.allianceId){[string]$p.allianceId}elseif($p.aid){[string]$p.aid}else{$outerAllianceId});$Alliance=[string]$p.abbr;$AllianceName=$(if($p.allianceName){[string]$p.allianceName}else{[string]$p.alName})
} elseif(-not $Uid -or -not $ServerId){return 'none'}
$uid=[string]$Uid
$allianceId=[string]$AllianceId
$sameUid=$previous -and [string]$previous.uid -eq $uid
$uidChanged=$previous -and -not $sameUid
$allianceChanged=$sameUid -and $allianceId -and [string]$previous.allianceId -ne $allianceId
$switched=$uidChanged -or $allianceChanged
$profileFiles=@('season-ranks.csv','hero-power.json','member-power.json','weekly-score.json','weekly-score-previous.json','ds-battlefield-vote.json','cs-battlefield-vote.json','event-updates.json','last-collection.json')
$restoredProfile=$false
if($switched){
    $profiles=Join-Path $root 'data\profiles'
    $oldKey=([string]$previous.uid+'-'+[string]$previous.allianceId) -replace '[^A-Za-z0-9_.-]','_'
    $oldDir=Join-Path $profiles $oldKey
    New-Item -ItemType Directory -Path $oldDir -Force | Out-Null
    foreach($profileName in $profileFiles){
        $active=Join-Path $root ('data\'+$profileName)
        $saved=Join-Path $oldDir $profileName
        if(-not (Test-Path $active)){continue}
        $keepSaved=$false
        if($profileName -eq 'season-ranks.csv' -and (Test-Path $saved)){
            try{$keepSaved=@(Import-Csv $active).Count -eq 0 -and @(Import-Csv $saved).Count -gt 0}catch{}
        }
        if($profileName -eq 'event-updates.json' -and (Test-Path $saved)){
            try{$activeMeta=Get-Content $active -Raw -Encoding UTF8 | ConvertFrom-Json;$savedMeta=Get-Content $saved -Raw -Encoding UTF8 | ConvertFrom-Json;$keepSaved=@($activeMeta.PSObject.Properties).Count -eq 0 -and @($savedMeta.PSObject.Properties).Count -gt 0}catch{}
        }
        if(-not $keepSaved){Copy-Item -LiteralPath $active -Destination $saved -Force}
    }
    if($previous){$previous | ConvertTo-Json | Set-Content (Join-Path $oldDir 'account-context.json') -Encoding UTF8}
    if($allianceId){
        $newKey=($uid+'-'+$allianceId) -replace '[^A-Za-z0-9_.-]','_'
        $newDir=Join-Path $profiles $newKey
    }else{
        $uidPrefix=($uid -replace '[^A-Za-z0-9_.-]','_')+'-'
        $newDir=Get-ChildItem -LiteralPath $profiles -Directory -ErrorAction SilentlyContinue |
            Where-Object {$_.Name.StartsWith($uidPrefix) -and $_.Name.Length -gt $uidPrefix.Length} |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
        if(-not $newDir){$newDir=Join-Path $profiles ($uidPrefix+'__new__')}
    }
    if($newDir -and (Test-Path $newDir)){
        $savedContextPath=Join-Path $newDir 'account-context.json'
        if(Test-Path $savedContextPath){
            try{
                $savedContext=Get-Content $savedContextPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if(-not $allianceId){$allianceId=[string]$savedContext.allianceId;$AllianceId=$allianceId}
                if(-not $Alliance){$Alliance=[string]$savedContext.alliance}
                if(-not $AllianceName){$AllianceName=[string]$savedContext.allianceName}
                if(-not $Name){$Name=[string]$savedContext.name}
            }catch{}
        }
        $savedMemberPath=Join-Path $newDir 'member-power.json'
        if(Test-Path $savedMemberPath){
            try{
                $savedMember=Get-Content $savedMemberPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if(-not $allianceId){$allianceId=[string]$savedMember.allianceId;$AllianceId=$allianceId}
                if(-not $Alliance){$Alliance=[string]$savedMember.alliance}
                if(-not $AllianceName){$AllianceName=[string]$savedMember.allianceName}
            }catch{}
        }
        $restoredProfile=$true
    }
    foreach($profileName in $profileFiles){$active=Join-Path $root ('data\'+$profileName);$saved=Join-Path $newDir $profileName;if(Test-Path $saved){Copy-Item -LiteralPath $saved -Destination $active -Force}elseif(Test-Path $active){Remove-Item -LiteralPath $active -Force}}
}
$context=[ordered]@{
    capturedAt=$(if($Path){(Get-Item $Path).LastWriteTime.ToString('o')}else{(Get-Date).ToString('o')})
    uid=$uid
    name=$(if($Name){$Name}elseif($sameUid){[string]$previous.name}else{''})
    serverId=[int]$ServerId
    serverName=$(if($ServerName){$ServerName}elseif($sameUid){[string]$previous.serverName}else{'State#'+$ServerId})
    allianceId=$(if($AllianceId){$AllianceId}elseif($sameUid){[string]$previous.allianceId}else{''})
    alliance=$(if($Alliance){$Alliance}elseif($sameUid){[string]$previous.alliance}else{''})
    allianceName=$(if($AllianceName){$AllianceName}elseif($sameUid){[string]$previous.allianceName}else{''})
}
$context | ConvertTo-Json | Set-Content ($contextPath+'.tmp') -Encoding UTF8
Move-Item -LiteralPath ($contextPath+'.tmp') -Destination $contextPath -Force
$uiSessionPath=Join-Path $root 'data\ui-session.json'
if(Test-Path $uiSessionPath){
    try{
        $uiSession=Get-Content $uiSessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $previousUid=[string]$uiSession.previousUid
        $uiSession | Add-Member -NotePropertyName accountVerified -NotePropertyValue $true -Force
        $uiSession | Add-Member -NotePropertyName detectedUid -NotePropertyValue $uid -Force
        $uiSession | Add-Member -NotePropertyName reuseStored -NotePropertyValue ([bool]((-not $switched) -or $restoredProfile)) -Force
        $uiSession | ConvertTo-Json | Set-Content ($uiSessionPath+'.tmp') -Encoding UTF8
        Move-Item -LiteralPath ($uiSessionPath+'.tmp') -Destination $uiSessionPath -Force
    }catch{}
}
return $(if($switched){'switched'}else{'updated'})
