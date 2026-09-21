param([int]$Port = 8080)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$site = Join-Path $root 'site'
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
$token=[Guid]::NewGuid().ToString('N')
function Find-Collector {
    $pidPath=Join-Path $root 'data\npcap-worker.pid'
    if(-not (Test-Path $pidPath)){return $null}
    try{
        $collectorPid=[int](Get-Content $pidPath -ErrorAction Stop)
        $process=Get-Process -Id $collectorPid -ErrorAction Stop
        if($process.ProcessName -eq 'powershell'){return $process}
    }catch{}
    return $null
}
$worker=Find-Collector
$routes = @{
    '/' = 'season-ranks.html'
    '/season-ranks.html' = 'season-ranks.html'
}
try {
    $listener.Start()
    Set-Content -LiteralPath (Join-Path $root 'data\local-server.pid') -Value $PID
    Write-Output "LastwarHub: http://localhost:$Port"
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $client.ReceiveTimeout = 3000
            $client.SendTimeout = 10000
            $stream = $client.GetStream()
            $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 1024, $true)
            $line = $reader.ReadLine()
            if (-not $line -or $line.Length -gt 4096) { continue }
            $parts = $line.Split(' ')
            if ($parts.Length -lt 2) { continue }
            $method = $parts[0]
            $path = $parts[1].Split('?')[0]
            $requestHeaders=@{}
            for($i=0;$i -lt 100;$i++){
                $h=$reader.ReadLine()
                if(-not $h){break}
                $colon=$h.IndexOf(':')
                if($colon -gt 0){$requestHeaders[$h.Substring(0,$colon).ToLowerInvariant()]=$h.Substring($colon+1).Trim()}
            }
            $status = '200 OK'
            $contentType='text/html; charset=utf-8'
            if($requestHeaders['host'] -notin @("localhost:$Port","127.0.0.1:$Port")){
                $status='403 Forbidden';$body=[Text.Encoding]::UTF8.GetBytes('Invalid host')
            } elseif($path -eq '/api/share-link' -and $method -eq 'GET'){
                $contentType='application/json; charset=utf-8'
                $shareUrl=''
                $shareFile=Join-Path $root 'data\share-url.txt'
                if(Test-Path $shareFile){$shareUrl=[IO.File]::ReadAllText($shareFile).Trim()}
                if($shareUrl -notmatch '^https://(?:[a-z0-9-]+\.trycloudflare\.com|[a-z0-9-]+\.workspace-[0-9]+\.chatgpt\.site)/?$'){$shareUrl=''}
                $body=[Text.Encoding]::UTF8.GetBytes((@{url=$shareUrl} | ConvertTo-Json -Compress))
            } elseif($path -eq '/api/status' -and $method -eq 'GET'){
                $contentType='application/json; charset=utf-8'
                $state=@{state='idle'}
                $stateFile=Join-Path $root 'data\collection-status.json'
                if(Test-Path $stateFile){try{$state=Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json}catch{}}
                # A new app run starts with an empty dashboard. Do not expose an
                # older collection timestamp, otherwise the browser mistakes it
                # for a fresh update and enters a reload loop.
                $uiSessionFile=Join-Path $root 'data\ui-session.json'
                if($state.lastUpdate -and (Test-Path $uiSessionFile)){
                    try{
                        $uiStarted=[DateTimeOffset]::Parse((Get-Content $uiSessionFile -Raw -Encoding UTF8 | ConvertFrom-Json).startedAt)
                        $lastCaptured=[DateTimeOffset]::Parse([string]$state.lastUpdate.capturedAt)
                        if($lastCaptured -lt $uiStarted){$state.lastUpdate=$null}
                    }catch{}
                }
                $signalFile=Join-Path $root 'data\packet-signal.json'
                if(Test-Path $signalFile){
                    try{$state | Add-Member -NotePropertyName packetSignal -NotePropertyValue (Get-Content $signalFile -Raw -Encoding UTF8 | ConvertFrom-Json) -Force}catch{}
                }
                if(-not $worker -or $worker.HasExited){$worker=Find-Collector}
                if($worker -and $worker.HasExited -and $state.state -in @('starting','capturing','processing','watching','waiting_game','reconnecting')){
                    $state=@{state='error';detail='Collection process stopped unexpectedly.'}
                }
                if(-not $worker -and $state.state -in @('starting','capturing','processing','watching','waiting_game','reconnecting')){
                    $state=@{state='error';detail='Collection process is not running.'}
                }
                $body=[Text.Encoding]::UTF8.GetBytes((@{token=$token;status=$state} | ConvertTo-Json -Depth 5))
            } elseif($path -in @('/api/collect','/api/stop') -and $method -eq 'POST'){
                $contentType='application/json; charset=utf-8'
                if($requestHeaders['x-collection-token'] -ne $token -or $requestHeaders['origin'] -notin @("http://localhost:$Port","http://127.0.0.1:$Port")){
                    $status='403 Forbidden';$body=[Text.Encoding]::UTF8.GetBytes('{"error":"Invalid request"}')
                } elseif($path -eq '/api/stop'){
                    Set-Content (Join-Path $root 'data\npcap-stop.flag') 'stop'
                    $body=[Text.Encoding]::UTF8.GetBytes('{"stopping":true}')
                } elseif(($worker=Find-Collector) -and -not $worker.HasExited){
                    $status='409 Conflict';$body=[Text.Encoding]::UTF8.GetBytes('{"error":"Collection already running"}')
                } else {
                    try{
                        $scriptPath=Join-Path $root 'tools\WatchNpcap.ps1'
                        @{state='starting';at=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $root 'data\collection-status.json') -Encoding UTF8
                        $worker=Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$scriptPath+'"') -PassThru
                        $body=[Text.Encoding]::UTF8.GetBytes('{"started":true}')
                    } catch {
                        @{state='error';detail='Administrator launch cancelled or failed.'} | ConvertTo-Json | Set-Content (Join-Path $root 'data\collection-status.json') -Encoding UTF8
                        $status='500 Internal Server Error';$body=[Text.Encoding]::UTF8.GetBytes('{"error":"Administrator launch cancelled or failed"}')
                    }
                }
            } elseif ($method -notin @('GET','HEAD')) {
                $status = '405 Method Not Allowed'
                $body = [Text.Encoding]::UTF8.GetBytes('Method not allowed')
            } elseif (-not $routes.ContainsKey($path)) {
                $status = '404 Not Found'
                $body = [Text.Encoding]::UTF8.GetBytes('Not found')
            } else {
                $body = [IO.File]::ReadAllBytes((Join-Path $site $routes[$path]))
            }
            $headers = "HTTP/1.1 $status`r`nContent-Type: $contentType`r`nContent-Length: $($body.Length)`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nConnection: close`r`n`r`n"
            $bytes = [Text.Encoding]::ASCII.GetBytes($headers)
            $stream.Write($bytes, 0, $bytes.Length)
            if ($method -ne 'HEAD') { $stream.Write($body, 0, $body.Length) }
            $stream.Flush()
        } catch {
            Write-Warning $_.Exception.Message
        } finally {
            $client.Close()
        }
    }
} finally { $listener.Stop() }
