param([string]$TitlePattern='(?i)DS\s*[-_ ]?Battlefield',[string]$SourceDir,[string]$OutputFile='ds-battlefield-vote.json')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not $SourceDir){
    $contextPath=Join-Path $root 'data\account-context.json'
    if(-not (Test-Path $contextPath)){return $false}
    $context=Get-Content $contextPath -Raw -Encoding UTF8|ConvertFrom-Json
    if(-not $context.uid){return $false}
    $profileKey=([string]$context.uid+'-'+[string]$context.allianceId) -replace '[^A-Za-z0-9_.-]','_'
    $SourceDir=Join-Path $root ('data\profiles\'+$profileKey+'\observed-votes')
}
$sourceDir=$SourceDir
if(-not (Test-Path $sourceDir)){return $false}

$candidates=@()
$noticeFiles=@(Get-ChildItem $sourceDir -File -Filter 'latest-alliance.notice.list.info.json')
if(-not $noticeFiles.Count){$noticeFiles=@(Get-ChildItem $sourceDir -File -Filter '*.json')}
foreach($file in $noticeFiles){
    try{$message=Get-Content $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json}catch{continue}
    if([string]$message.p.c -ne 'alliance.notice.list.info'){continue}
    foreach($notice in @($message.p.p.notices)){
        try{
            $outer=$notice.notice|ConvertFrom-Json
            $info=$outer.voteInfo|ConvertFrom-Json
            if([string]$info.title -notmatch $TitlePattern){continue}
            $result=$outer.voteResult|ConvertFrom-Json
            $candidates+=[pscustomobject]@{File=$file;Notice=$notice;Outer=$outer;Info=$info;Result=$result}
        }catch{}
    }
}
if(-not $candidates.Count){return $false}
$selected=$candidates|Sort-Object @{Expression={[int64]$_.Notice.create_time};Descending=$true},@{Expression={$_.File.LastWriteTime};Descending=$true}|Select-Object -First 1
$voteId=[string]$selected.Outer.voteId

$voteMessage=$null
$voteFiles=@(Get-ChildItem $sourceDir -File -Filter 'latest-vote.list.json')
if(-not $voteFiles.Count){$voteFiles=@(Get-ChildItem $sourceDir -File -Filter '*vote.list.json')}
foreach($file in $voteFiles|Sort-Object LastWriteTime -Descending){
    try{$message=Get-Content $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json}catch{continue}
    if([string]$message.p.p.voteId -eq $voteId){$voteMessage=$message;break}
}

$votersByOption=@{}
if($voteMessage){
    foreach($property in $voteMessage.p.p.list.PSObject.Properties){$votersByOption[[string]$property.Name]=@($property.Value)}
}
$counts=@{}
foreach($item in @($selected.Result.options)){$counts[[string]$item.itemId]=[int]$item.total}
$totalVotes=[int]$selected.Result.count
$options=@()
foreach($option in @($selected.Info.options)){
    $id=[string]$option.itemId
    $voters=@($votersByOption[$id]|ForEach-Object {[ordered]@{uid=[string]$_.uid;name=[string]$_.name;power=[long]$_.power}})
    $count=if($counts.ContainsKey($id)){$counts[$id]}else{$voters.Count}
    $options+=[ordered]@{
        id=$id
        label=[string]$option.item
        votes=[int]$count
        percent=$(if($totalVotes){[Math]::Round(100*$count/$totalVotes,1)}else{0})
        voters=$voters
    }
}
$created=[DateTimeOffset]::FromUnixTimeMilliseconds([int64]$selected.Notice.create_time).ToOffset([TimeSpan]::FromHours(9)).ToString('o')
$ends=[DateTimeOffset]::FromUnixTimeMilliseconds([int64]$selected.Outer.endTime).ToOffset([TimeSpan]::FromHours(9)).ToString('o')
$stable=[ordered]@{
    title=[string]$selected.Info.title
    voteId=$voteId
    noticeUuid=[string]$selected.Notice.uuid
    createdAt=$created
    endsAt=$ends
    durationHours=[int]$selected.Info.timeHour
    totalEligible=[int]$selected.Outer.total
    totalVotes=$totalVotes
    myOptionId=[string]$selected.Outer.itemId
    comments=[int]$selected.Notice.comment
    options=$options
}
$out=Join-Path $root ('data\'+$OutputFile)
$stableJson=$stable|ConvertTo-Json -Depth 8 -Compress
if(Test-Path $out){
    try{
        $existing=Get-Content $out -Raw -Encoding UTF8|ConvertFrom-Json
        $existingStable=[ordered]@{}
        foreach($name in $stable.Keys){$existingStable[$name]=$existing.$name}
        if(($existingStable|ConvertTo-Json -Depth 8 -Compress) -eq $stableJson){return $false}
    }catch{}
}
$data=[ordered]@{capturedAt=(Get-Date).ToString('o')}
foreach($name in $stable.Keys){$data[$name]=$stable[$name]}
$data|ConvertTo-Json -Depth 8|Set-Content ($out+'.tmp') -Encoding UTF8
Move-Item -LiteralPath ($out+'.tmp') -Destination $out -Force
return $true
