param([Parameter(Mandatory=$true)][string]$Path)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$messages=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
$context=$null
$contextFile=Join-Path $root 'data\account-context.json'
if(Test-Path $contextFile){$context=Get-Content $contextFile -Raw -Encoding UTF8 | ConvertFrom-Json}
if((-not $context) -or (-not [string]$context.uid)){
    $connectionFile=Join-Path $root 'data\connection-account.json'
    if(Test-Path $connectionFile){$connection=Get-Content $connectionFile -Raw -Encoding UTF8 | ConvertFrom-Json;if(-not $context){$context=$connection}elseif(-not [string]$context.uid){$context.uid=[string]$connection.uid}}
}
$rankMessages=@($messages | Where-Object {$_.p.c -eq 'al.rank' -and $_.p.p.allianceId -and $_.p.p.list.Count -gt 0})
if([string]$context.allianceId){
    $m=$rankMessages | Where-Object {[string]$_.p.p.allianceId -eq [string]$context.allianceId} | Select-Object -Last 1
}elseif([string]$context.uid){
    $m=$rankMessages | Where-Object {@($_.p.p.list | Where-Object {[string]$_.uid -eq [string]$context.uid}).Count -gt 0} | Select-Object -Last 1
}else{
    $m=$null
}
if(-not $m){return $false}
$id=[string]$m.p.p.allianceId
$alliance=$id
$allianceName=''
if($context -and [string]$context.allianceId -eq $id){$alliance=[string]$context.alliance;$allianceName=[string]$context.allianceName}
$heroFile=Join-Path $root 'data\hero-power.json'
if(Test-Path $heroFile){$heroes=Get-Content $heroFile -Raw -Encoding UTF8 | ConvertFrom-Json;$found=$heroes.rows | Where-Object {$_.allianceId -eq $id} | Select-Object -First 1;if($found){$alliance=$found.alliance}}
$rows=@($m.p.p.list | Where-Object {$_.uid -and $null -ne $_.power} | ForEach-Object {
    [ordered]@{uid=[string]$_.uid;name=$_.name;alliance=$alliance;allianceId=$id;power=[long]$_.power;serverId=$_.serverId}
})
if(-not $rows.Count){return $false}
$serverId=($rows | Group-Object serverId | Sort-Object Count -Descending | Select-Object -First 1).Name
$data=[ordered]@{capturedAt=(Get-Item $Path).LastWriteTime.ToString('o');serverId=[int]$serverId;allianceId=$id;alliance=$alliance;allianceName=$allianceName;source='al.rank/list/power';rows=$rows}
$out=Join-Path $root 'data\member-power.json'
$data | ConvertTo-Json -Depth 5 | Set-Content ($out+'.tmp') -Encoding UTF8
Move-Item -LiteralPath ($out+'.tmp') -Destination $out -Force
return $true
