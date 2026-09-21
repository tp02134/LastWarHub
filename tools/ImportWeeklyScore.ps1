param([Parameter(Mandatory=$true)][string]$Path)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
try{$koreaZone=[TimeZoneInfo]::FindSystemTimeZoneById('Korea Standard Time')}catch{$koreaZone=[TimeZoneInfo]::FindSystemTimeZoneById('Asia/Seoul')}
function Get-WeeklyPeriod([DateTimeOffset]$Value){
    $local=[TimeZoneInfo]::ConvertTime($Value,$koreaZone)
    $daysSinceMonday=([int]$local.DayOfWeek+6)%7
    $monday=$local.Date.AddDays(-$daysSinceMonday).AddHours(11)
    $start=[DateTimeOffset]::new($monday,[TimeSpan]::FromHours(9))
    if($local -lt $start){$start=$start.AddDays(-7)}
    $archiveStart=$start.AddDays(6)
    return [pscustomobject]@{Start=$start;ArchiveWindow=($local -ge $archiveStart -and $local -lt $start.AddDays(7))}
}
$messages=Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
$message=$messages | Where-Object {$_.p.c -eq 'al.battle.rank.info' -and $_.p.p.type -eq 1 -and $_.p.p.rankInfo.Count -gt 0} | Select-Object -Last 1
if(-not $message){return $false}
$rows=@($message.p.p.rankInfo | Where-Object {$_.uid -and $null -ne $_.score} | ForEach-Object {[ordered]@{uid=[string]$_.uid;name=$_.name;alliance=$_.abbr;score=[long]$_.score}})
if(-not $rows.Count){return $false}
$capturedAt=[DateTimeOffset](Get-Item $Path).LastWriteTime
$period=Get-WeeklyPeriod $capturedAt
$weekStart=$period.Start
$data=[ordered]@{capturedAt=$capturedAt.ToString('o');weekKey=$weekStart.ToString('yyyy-MM-dd');weekStartsAt=$weekStart.ToString('o');source='al.battle.rank.info/type=1';rows=$rows}
$out=Join-Path $root 'data\weekly-score.json'
$previousOut=Join-Path $root 'data\weekly-score-previous.json'
if($period.ArchiveWindow){
    $data | ConvertTo-Json -Depth 5 | Set-Content ($previousOut+'.tmp') -Encoding UTF8
    Move-Item ($previousOut+'.tmp') $previousOut -Force
    return $true
}
if(Test-Path $out){
    try{
        $existing=Get-Content $out -Raw -Encoding UTF8 | ConvertFrom-Json
        $existingPeriod=Get-WeeklyPeriod ([DateTimeOffset]::Parse([string]$existing.capturedAt))
        if($existingPeriod.Start -eq $weekStart.AddDays(-7) -and @($existing.rows).Count){
            $keepExisting=$true
            if(Test-Path $previousOut){
                $savedPrevious=Get-Content $previousOut -Raw -Encoding UTF8 | ConvertFrom-Json
                $savedCaptured=[DateTimeOffset]::Parse([string]$savedPrevious.capturedAt)
                if($savedCaptured -ge [DateTimeOffset]::Parse([string]$existing.capturedAt)){$keepExisting=$false}
            }
            if($keepExisting){
                $existing | Add-Member -NotePropertyName weekKey -NotePropertyValue $existingPeriod.Start.ToString('yyyy-MM-dd') -Force
                $existing | Add-Member -NotePropertyName weekStartsAt -NotePropertyValue $existingPeriod.Start.ToString('o') -Force
                $existing | ConvertTo-Json -Depth 5 | Set-Content ($previousOut+'.tmp') -Encoding UTF8
                Move-Item ($previousOut+'.tmp') $previousOut -Force
            }
        }
    }catch{}
}
$data | ConvertTo-Json -Depth 5 | Set-Content ($out+'.tmp') -Encoding UTF8
Move-Item ($out+'.tmp') $out -Force
return $true
