param([int]$Port = 8080)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$dataDir=Join-Path $root 'data'
$binDir=Join-Path $dataDir 'bin'
$exe=Join-Path $binDir 'cloudflared.exe'
$statusPath=Join-Path $dataDir 'share-tunnel-status.json'
$urlPath=Join-Path $dataDir 'share-url.txt'
$pidPath=Join-Path $dataDir 'share-tunnel.pid'
$stopPath=Join-Path $dataDir 'share-tunnel-stop.flag'
$outLog=Join-Path $dataDir 'share-tunnel-output.log'
$errorLog=Join-Path $dataDir 'share-tunnel-error.log'
$process=$null

function Publish([string]$State,[string]$Detail=''){
    @{state=$State;detail=$Detail;at=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content ($statusPath+'.tmp') -Encoding UTF8
    Move-Item -LiteralPath ($statusPath+'.tmp') -Destination $statusPath -Force
}
function Read-SharedText([string]$Path){
    if(-not (Test-Path $Path)){return ''}
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try{
        $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true)
        try{return $reader.ReadToEnd()}finally{$reader.Dispose()}
    }finally{$stream.Dispose()}
}

try{
    New-Item -ItemType Directory -Path $dataDir,$binDir -Force | Out-Null
    Remove-Item -LiteralPath $urlPath -Force -ErrorAction SilentlyContinue
    if(Test-Path $stopPath){throw 'Share link creation was cancelled.'}
    if(-not (Test-Path $exe)){
        Publish 'downloading' 'Cloudflare 공유 도구를 다운로드하고 있습니다.'
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        $download='https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'
        Invoke-WebRequest -UseBasicParsing -Uri $download -OutFile ($exe+'.tmp')
        Move-Item -LiteralPath ($exe+'.tmp') -Destination $exe -Force
    }
    if(Test-Path $stopPath){throw 'Share link creation was cancelled.'}
    Remove-Item -LiteralPath $outLog,$errorLog -Force -ErrorAction SilentlyContinue
    Publish 'starting' '임시 공유 링크를 만들고 있습니다.'
    $process=Start-Process -FilePath $exe -WindowStyle Hidden -PassThru -ArgumentList @('tunnel','--url',"http://127.0.0.1:$Port",'--http-host-header',"localhost:$Port") -RedirectStandardOutput $outLog -RedirectStandardError $errorLog
    Set-Content -LiteralPath $pidPath -Value $process.Id -Encoding ASCII
    for($i=0;$i -lt 120;$i++){
        if(Test-Path $stopPath){throw 'Share link creation was cancelled.'}
        if($process.HasExited){throw 'Cloudflare 공유 프로세스가 링크 생성 전에 종료되었습니다.'}
        $log=(Read-SharedText $outLog)+"`n"+(Read-SharedText $errorLog)
        $match=[regex]::Match($log,'https://[a-z0-9-]+\.trycloudflare\.com')
        if($match.Success){
            $match.Value | Set-Content ($urlPath+'.tmp') -Encoding ASCII
            Move-Item -LiteralPath ($urlPath+'.tmp') -Destination $urlPath -Force
            Publish 'ready' '공유 링크가 열렸습니다.'
            exit 0
        }
        Start-Sleep -Milliseconds 500
    }
    throw '공유 링크 생성 시간이 초과되었습니다.'
}catch{
    if($process -and -not $process.HasExited){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue}
    Remove-Item -LiteralPath $pidPath,$urlPath -Force -ErrorAction SilentlyContinue
    Publish 'error' $_.Exception.Message
    exit 1
}
