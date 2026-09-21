param([string]$Source = 'data\season-ranks.csv')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sessionStarted=[DateTimeOffset]::MinValue
$reuseStored=$false
$sessionPath=Join-Path $root 'data\ui-session.json'
if(Test-Path $sessionPath){
    try{$session=Get-Content $sessionPath -Raw -Encoding UTF8 | ConvertFrom-Json;$sessionStarted=[DateTimeOffset]::Parse($session.startedAt);$reuseStored=[bool]$session.reuseStored}catch{}
}
function Test-SessionTime($value){
    if($script:reuseStored){return $true}
    if($script:sessionStarted -eq [DateTimeOffset]::MinValue){return $true}
    try{return [DateTimeOffset]::Parse([string]$value) -ge $script:sessionStarted}catch{return $false}
}
function Read-SessionJson([string]$path,[string]$empty){
    if(-not (Test-Path $path)){return $empty}
    $raw=[IO.File]::ReadAllText($path)
    try{if(Test-SessionTime (($raw | ConvertFrom-Json).capturedAt)){return $raw}}catch{}
    return $empty
}
try{$koreaZone=[TimeZoneInfo]::FindSystemTimeZoneById('Korea Standard Time')}catch{$koreaZone=[TimeZoneInfo]::FindSystemTimeZoneById('Asia/Seoul')}
function Get-WeeklyPeriod([DateTimeOffset]$value){
    $local=[TimeZoneInfo]::ConvertTime($value,$script:koreaZone)
    $daysSinceMonday=([int]$local.DayOfWeek+6)%7
    $monday=$local.Date.AddDays(-$daysSinceMonday).AddHours(11)
    $start=[DateTimeOffset]::new($monday,[TimeSpan]::FromHours(9))
    if($local -lt $start){$start=$start.AddDays(-7)}
    $archiveStart=$start.AddDays(6)
    return [pscustomobject]@{Start=$start;ArchiveWindow=($local -ge $archiveStart -and $local -lt $start.AddDays(7))}
}
function Get-WeeklyDataStart($value){
    if(-not $value){return $null}
    try{return (Get-WeeklyPeriod ([DateTimeOffset]::Parse([string]$value.capturedAt))).Start}catch{return $null}
}
$times=@{'120021'='2026-09-15T17:10:48+09:00';'120022'='2026-09-15T17:10:48+09:00';'120023'='2026-09-15T17:10:48+09:00';'120024'='2026-09-15T17:28:22+09:00'}
$metaPath=Join-Path $root 'data\event-updates.json'
if(Test-Path $metaPath){
    $meta=Get-Content $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach($p in $meta.PSObject.Properties){$times[$p.Name]=$p.Value}
}
$sourcePath=Join-Path $root $Source
$sourceRows=@(if(Test-Path $sourcePath){Import-Csv $sourcePath | Where-Object {Test-SessionTime $times[[string]$_.EventId]}})
$rows=@($sourceRows | ForEach-Object {
    [ordered]@{event=$_.EventId;rank=[int]$_.Rank;name=$_.Name;alliance=$_.Alliance;score=[long]$_.Score;uid=$_.UserId}
})
$payload=ConvertTo-Json -InputObject $rows -Compress -Depth 4
$payload=$payload.Replace('<','\u003c').Replace('>','\u003e').Replace('&','\u0026')
$knownLabels=@{
    '120021'=[string]::Concat([char]0xC0C1,[char]0xD638,' ',[char]0xC9C0,[char]0xC6D0)
    '120022'=[string]::Concat([char]0xACF5,[char]0xC131)
    '120023'=[string]::Concat([char]0xC7C1,[char]0xD0C8,[char]0xC804)
    '120024'=[string]::Concat([char]0xCC98,[char]0xCE58)
}
$locale=$null
$localePath=Join-Path $root 'data\ko.json'
if(Test-Path $localePath){$locale=Get-Content $localePath -Raw -Encoding UTF8 | ConvertFrom-Json}
$labels=[ordered]@{}
foreach($event in ($rows.event | Sort-Object -Unique)) {
    if($knownLabels.ContainsKey([string]$event)){$labels[$event]=$knownLabels[[string]$event];continue}
    $entry=if($locale){$locale.entries | Where-Object { $_.k -eq ('season_alliance_event_name_'+$event) } | Select-Object -First 1}else{$null}
    $labels[$event]=if($entry){$entry.v}else{'항목 '+$event}
}
$labelJson=(ConvertTo-Json -InputObject $labels -Compress).Replace('<','\u003c').Replace('>','\u003e').Replace('&','\u0026')
$html=Get-Content (Join-Path $root 'site\season-template.html') -Raw -Encoding UTF8
$html=$html.Replace('__SEASON_DATA__',$payload)
$html=$html.Replace('__SEASON_LABELS__',$labelJson)
$html=$html.Replace('__SEASON_TIMES__',(ConvertTo-Json -InputObject $times -Compress))
$lastUpdate=''
$lastFile=Join-Path $root 'data\last-collection.json'
if(Test-Path $lastFile){$candidateLastUpdate=(Get-Content $lastFile -Raw -Encoding UTF8 | ConvertFrom-Json).capturedAt;if(Test-SessionTime $candidateLastUpdate){$lastUpdate=$candidateLastUpdate}}
$html=$html.Replace('__SEASON_LAST_UPDATE__',(ConvertTo-Json -InputObject ([string]$lastUpdate) -Compress))
$heroJson='{"rows":[]}'
$heroFile=Join-Path $root 'data\hero-power.json'
$heroJson=Read-SessionJson $heroFile $heroJson
$heroJson=$heroJson.Replace('<','\u003c').Replace('>','\u003e').Replace('&','\u0026')
$html=$html.Replace('__HERO_DATA__',$heroJson)
$memberJson='{"rows":[]}'
$memberFile=Join-Path $root 'data\member-power.json'
$memberJson=Read-SessionJson $memberFile $memberJson
$memberJson=$memberJson.Replace('<','\u003c').Replace('>','\u003e').Replace('&','\u0026')
$html=$html.Replace('__MEMBER_DATA__',$memberJson)
$out=Join-Path $root 'site\season-ranks.html'
$currentPeriod=Get-WeeklyPeriod ([DateTimeOffset]::Now)
$currentWeekStart=$currentPeriod.Start
$previousWeekStart=if($currentPeriod.ArchiveWindow){$currentWeekStart}else{$currentWeekStart.AddDays(-7)}
$emptyWeekly=ConvertTo-Json -Compress -InputObject ([ordered]@{weekKey=$currentWeekStart.ToString('yyyy-MM-dd');weekStartsAt=$currentWeekStart.ToString('o');rows=@()})
$weeklyJson=$emptyWeekly
$weeklyPreviousJson=(ConvertTo-Json -Compress -InputObject ([ordered]@{weekKey=$previousWeekStart.ToString('yyyy-MM-dd');weekStartsAt=$previousWeekStart.ToString('o');rows=@()}))
$weeklyFile=Join-Path $root 'data\weekly-score.json'
$weeklyRaw=Read-SessionJson $weeklyFile '{"rows":[]}'
$weeklyObject=$null;try{$weeklyObject=$weeklyRaw | ConvertFrom-Json}catch{}
$weeklyStart=Get-WeeklyDataStart $weeklyObject
$previousCandidates=@()
if((-not $currentPeriod.ArchiveWindow) -and $weeklyStart -and $weeklyStart -eq $currentWeekStart){
    $weeklyObject | Add-Member -NotePropertyName weekKey -NotePropertyValue $currentWeekStart.ToString('yyyy-MM-dd') -Force
    $weeklyObject | Add-Member -NotePropertyName weekStartsAt -NotePropertyValue $currentWeekStart.ToString('o') -Force
    $weeklyJson=$weeklyObject | ConvertTo-Json -Compress -Depth 5
}
elseif($weeklyStart -and $weeklyStart -eq $previousWeekStart -and @($weeklyObject.rows).Count){$previousCandidates+=$weeklyObject}
$previousWeeklyFile=Join-Path $root 'data\weekly-score-previous.json'
$storedPreviousRaw=Read-SessionJson $previousWeeklyFile '{"rows":[]}'
$storedPrevious=$null;try{$storedPrevious=$storedPreviousRaw | ConvertFrom-Json}catch{}
$storedPreviousStart=Get-WeeklyDataStart $storedPrevious
if($storedPreviousStart -and $storedPreviousStart -eq $previousWeekStart -and @($storedPrevious.rows).Count){$previousCandidates+=$storedPrevious}
if($previousCandidates.Count){
    $selectedPrevious=$previousCandidates | Sort-Object {[DateTimeOffset]::Parse([string]$_.capturedAt)} -Descending | Select-Object -First 1
    $selectedPrevious | Add-Member -NotePropertyName weekKey -NotePropertyValue $previousWeekStart.ToString('yyyy-MM-dd') -Force
    $selectedPrevious | Add-Member -NotePropertyName weekStartsAt -NotePropertyValue $previousWeekStart.ToString('o') -Force
    $weeklyPreviousJson=$selectedPrevious | ConvertTo-Json -Compress -Depth 5
}
$html=$html.Replace('__WEEKLY_DATA__',$weeklyJson.Replace('<','\u003c').Replace('>','\u003e').Replace('&','\u0026'))
$html=$html.Replace('__PREVIOUS_WEEKLY_DATA__',$weeklyPreviousJson.Replace('<','\u003c').Replace('>','\u003e').Replace('&','\u0026'))
$voteJson='{}'
$voteFile=Join-Path $root 'data\ds-battlefield-vote.json'
$voteJson=Read-SessionJson $voteFile $voteJson
$html=$html.Replace('__VOTE_DATA__',$voteJson.Replace('<','\u003c').Replace('>','\u003e').Replace('&','\u0026'))
$canyonVoteJson='{}'
$canyonVoteFile=Join-Path $root 'data\cs-battlefield-vote.json'
$canyonVoteJson=Read-SessionJson $canyonVoteFile $canyonVoteJson
$html=$html.Replace('__CANYON_VOTE_DATA__',$canyonVoteJson.Replace('<','\u003c').Replace('>','\u003e').Replace('&','\u0026'))
$accountJson='{}'
$accountFile=Join-Path $root 'data\account-context.json'
$accountJson=Read-SessionJson $accountFile $accountJson
$html=$html.Replace('__ACCOUNT_DATA__',$accountJson.Replace('<','\u003c').Replace('>','\u003e').Replace('&','\u0026'))
$html=$html.Replace('</body>',([IO.File]::ReadAllText((Join-Path $root 'site\bilingual.html'))+'</body>'))
[IO.File]::WriteAllText(($out+'.tmp'),$html,(New-Object Text.UTF8Encoding($false)))
Move-Item -LiteralPath ($out+'.tmp') -Destination $out -Force
Write-Output "Built $out ($($rows.Count) rows)"
