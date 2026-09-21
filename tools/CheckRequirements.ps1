param([switch]$Quiet)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$npcap=Join-Path $env:WINDIR 'System32\Npcap\wpcap.dll'
$zstd=Join-Path $env:LOCALAPPDATA 'FunFly\Last War-Survival Game\Game\LastWar_Data\Plugins\x86_64\libzstd.dll'
$missing=@()
if(-not (Test-Path $npcap)){$missing+='Npcap'}
if(-not (Test-Path $zstd)){$missing+='Last War PC client'}

New-Item -ItemType Directory -Path (Join-Path $root 'data') -Force|Out-Null
if($missing.Count){
    if(-not $Quiet){
        Write-Host 'LastwarHub 실행 준비가 필요합니다.' -ForegroundColor Yellow
        foreach($item in $missing){Write-Host ('- 찾을 수 없음: '+$item) -ForegroundColor Red}
        if($missing -contains 'Npcap'){
            Write-Host ''
            Write-Host 'Npcap 공식 다운로드: https://npcap.com/#download'
            Write-Host '설치 프로그램을 기본 설정으로 설치한 뒤 다시 확인하세요.'
        }
        if($missing -contains 'Last War PC client'){
            Write-Host ''
            Write-Host 'Last War PC 클라이언트를 설치하고 한 번 실행한 뒤 다시 확인하세요.'
        }
    }
    exit 1
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'BuildSeasonSite.ps1')|Out-Null
if(-not $Quiet){
    Write-Host '준비 완료: Last War PC 클라이언트와 Npcap을 확인했습니다.' -ForegroundColor Green
    Write-Host 'Start-LastwarHub.cmd를 실행하세요.'
}
exit 0
