$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$dataDir=Join-Path $root 'data'
$contextPath=Join-Path $dataDir 'account-context.json'
$profileFiles=@('season-ranks.csv','hero-power.json','member-power.json','weekly-score.json','ds-battlefield-vote.json','cs-battlefield-vote.json','event-updates.json','last-collection.json')

$context=$null
if(Test-Path $contextPath){try{$context=Get-Content $contextPath -Raw -Encoding UTF8|ConvertFrom-Json}catch{}}
if($context -and $context.uid){
    $profileKey=([string]$context.uid+'-'+[string]$context.allianceId) -replace '[^A-Za-z0-9_.-]','_'
    $profileDir=Join-Path $dataDir ('profiles\'+$profileKey)
    New-Item -ItemType Directory -Path $profileDir -Force|Out-Null
    foreach($name in $profileFiles){
        $active=Join-Path $dataDir $name
        if(Test-Path $active){Copy-Item -LiteralPath $active -Destination (Join-Path $profileDir $name) -Force}
    }
}

foreach($name in $profileFiles){Remove-Item -LiteralPath (Join-Path $dataDir $name) -Force -ErrorAction SilentlyContinue}
foreach($name in @('account-context.json','connection-account.json','packet-signal.json','collection-status.json','season-archive-context.json','account-history-context.json')){
    Remove-Item -LiteralPath (Join-Path $dataDir $name) -Force -ErrorAction SilentlyContinue
}
Write-Output 'Account context reset.'
