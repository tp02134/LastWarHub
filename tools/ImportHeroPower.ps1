param([Parameter(Mandatory=$true)][string]$Path)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$messages=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
$out=Join-Path $root 'data\hero-power.json'
$byId=@{}
if(Test-Path $out){$previous=Get-Content $out -Raw -Encoding UTF8 | ConvertFrom-Json;foreach($row in $previous.rows){$byId[[string]$row.uid]=$row}}
$members=@{}
$memberFile=Join-Path $root 'data\member-power.json'
if(Test-Path $memberFile){$roster=Get-Content $memberFile -Raw -Encoding UTF8 | ConvertFrom-Json;foreach($row in $roster.rows){$members[[string]$row.uid]=$row}}
$capturedAt=(Get-Item $Path).LastWriteTime.ToString('o')
$changed=$false
foreach($message in $messages){
    $desert=$message.p.c -eq 'dragon.assign.player.info'
    if(-not $desert){continue}
    $entries=$message.p.p.users
    foreach($entry in $entries){
        if(-not $entry.uid -or $null -eq $entry.heroPower){continue}
        $uid=[string]$entry.uid;$old=$byId[$uid];$member=$members[$uid]
        $alliance=if($member){$member.alliance}else{$old.alliance}
        $allianceId=if($member){$member.allianceId}else{$old.allianceId}
        $byId[$uid]=[pscustomobject]@{uid=$uid;name=$entry.name;alliance=$alliance;allianceId=$allianceId;heroPower=[long]$entry.heroPower;serverRank=$null;serverId=$entry.serverId;source=$message.p.c;capturedAt=$capturedAt}
        $changed=$true
    }
}
if(-not $changed){return $false}
$data=[ordered]@{capturedAt=$capturedAt;source='Desert Battlefield player info';rows=@($byId.Values | Sort-Object uid)}
$data | ConvertTo-Json -Depth 5 | Set-Content ($out+'.tmp') -Encoding UTF8
Move-Item -LiteralPath ($out+'.tmp') -Destination $out -Force
return $true
