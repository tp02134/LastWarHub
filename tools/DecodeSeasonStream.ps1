param([string]$Path,[string]$OutputName='decoded.json')
if([IO.Path]::GetFileName($OutputName) -ne $OutputName){throw 'OutputName must be a filename.'}
if(-not ('LWZstd' -as [type])){ Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LWZstd {
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr LoadLibraryW(string p);
 [DllImport("libzstd.dll",CallingConvention=CallingConvention.Cdecl)] public static extern UIntPtr ZSTD_decompress(byte[] dst, UIntPtr capacity, byte[] src, UIntPtr size);
 [DllImport("libzstd.dll",CallingConvention=CallingConvention.Cdecl)] public static extern uint ZSTD_isError(UIntPtr code);
}
'@
}
$dll=Join-Path $env:LOCALAPPDATA 'FunFly\Last War-Survival Game\Game\LastWar_Data\Plugins\x86_64\libzstd.dll'
if([LWZstd]::LoadLibraryW($dll) -eq [IntPtr]::Zero){throw 'Cannot load decompressor'}
$script:b = [IO.File]::ReadAllBytes((Resolve-Path $Path))
$script:p = 0
function Num([int]$n) {
    if ($script:p+$n -gt $script:b.Length) { throw 'Truncated' }
    [long]$v=0
    for($i=0;$i -lt $n;$i++){ $v=($v -shl 8) -bor $script:b[$script:p++ ] }
    return $v
}
function Str {
    $n=Num 2
    if($script:p+$n -gt $script:b.Length){throw 'String truncated'}
    $s=[Text.Encoding]::UTF8.GetString($script:b,$script:p,$n)
    $script:p+=$n
    return $s
}
function Val([int]$t) {
    switch($t){
        0 {return $null}
        1 {return [bool](Num 1)}
        2 {return (Num 1)}
        3 {return (Num 2)}
        4 {return (Num 4)}
        5 {return (Num 8)}
        6 { $x=Num 4; return $x }
        7 { $x=Num 8; return $x }
        8 {return (Str)}
        10 { $n=Num 4; $script:p+=$n; return @{binaryBytes=$n} }
        12 { $n=Num 2; $a=@(); for($j=0;$j -lt $n;$j++){$a+=,(Num 4)}; return ,$a }
        17 {
            $n=Num 2; $a=@()
            for($j=0;$j -lt $n;$j++){ $a+=,(Val (Num 1)) }
            return ,$a
        }
        18 {
            $n=Num 2; $h=[ordered]@{}
            for($j=0;$j -lt $n;$j++){ $k=Str; $h[$k]=Val (Num 1) }
            return $h
        }
        default { throw "Unsupported type $t at $script:p" }
    }
}
$messages=@()
while($script:p -lt $script:b.Length){
    $start=$script:p
    $flag=Num 1
    $len=if($flag -band 8){Num 4}else{Num 2}
    $rawLen=0
    if($flag -band 32){$rawLen=Num 4}
    $end=$script:p+$len
    if($end -gt $script:b.Length){Write-Output "Incomplete frame at $start";break}
    try {
        $original=$script:b
        if($flag -band 32){
            if($rawLen -gt 16777216){throw 'Decompressed size limit'}
            $compressed=[byte[]]$script:b[$script:p..($end-1)]
            $expanded=New-Object byte[] $rawLen
            $result=[LWZstd]::ZSTD_decompress($expanded,[UIntPtr]::new([uint64]$rawLen),$compressed,[UIntPtr]::new([uint64]$len))
            if([LWZstd]::ZSTD_isError($result) -ne 0 -or $result.ToUInt64() -ne $rawLen){throw 'Decompression failed'}
            $script:b=$expanded; $script:p=0
        }
        $v=Val (Num 1)
        $messages+=,$v
        if(($flag -band 32) -eq 0 -and $script:p -ne $end){Write-Output "Frame mismatch at $start"}
    } catch { Write-Output "Frame $start : $_" }
    $script:b=$original
    $script:p=$end
}
$out=Join-Path (Split-Path (Resolve-Path $Path)) $OutputName
ConvertTo-Json -InputObject $messages -Depth 90 | Set-Content -LiteralPath $out -Encoding UTF8
foreach($m in $messages){
    if($m.p.c){ Write-Output ('Message: '+$m.p.c) }
}
Write-Output ('Decoded frames: '+$messages.Count)
