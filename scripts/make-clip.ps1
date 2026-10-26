#requires -Version 5.1
<#
  make-clip.ps1 - tai mot doan video YouTube va cat thanh clip ngan lam
  background cho Start menu Windows 11.

  Vi du co ban (dung cho may dang bi YouTube chan bot-check):
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\make-clip.ps1 `
        -Url "https://www.youtube.com/watch?v=J0shA9J-4Nc"

  Lay ban net nhat (can cookie trinh duyet da dang nhap YouTube):
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\make-clip.ps1 `
        -Url "https://www.youtube.com/watch?v=J0shA9J-4Nc" -Browser firefox

  Tham so:
    -Url        URL video YouTube (bat buoc)
    -Start      moc bat dau, "HH:MM:SS" hoac "MM:SS"   (mac dinh 00:01:00)
    -Duration   so giay can lay                        (mac dinh 15)
    -Width      be rong xuat ra, chieu cao theo 16:9   (mac dinh 1280)
    -Client     player client cua yt-dlp               (mac dinh android)
    -Browser    cookies-from-browser: chrome|edge|firefox|brave|...
    -OutFile    duong dan xuat (mac dinh media\start-bg.mp4)
    -KeepRaw    giu lai file doan cat goc
#>
param(
    [Parameter(Mandatory = $true)][string]$Url,
    [string]$Start = "00:01:00",
    [int]$Duration = 15,
    [int]$Width = 1280,
    [string]$Client = "android",
    [string]$Browser = "",
    [string]$OutFile = "",
    [switch]$KeepRaw
)

$ErrorActionPreference = "Stop"

$root  = Split-Path -Parent $PSScriptRoot
$media = Join-Path $root "media"
$tools = Join-Path $root ".tools"
New-Item -ItemType Directory -Force -Path $media, $tools | Out-Null
if (-not $OutFile) { $OutFile = Join-Path $media "start-bg.mp4" }

function Resolve-Tool {
    param([string]$Name, [string]$Url)

    $cmd = Get-Command "$Name.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # winget cai ffmpeg vao Packages\<id>\...\bin, khong phai luc nao cung co trong PATH
    $wg = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "$Name.exe" `
            -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($wg) { return $wg.FullName }

    $local = Join-Path $tools "$Name.exe"
    if (-not (Test-Path $local)) {
        Write-Host "[tai] $Name..." -ForegroundColor Cyan
        if ($Name -eq "yt-dlp") {
            Invoke-WebRequest -Uri "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" `
                -OutFile $local -UseBasicParsing
        }
        else {
            $zip = Join-Path $tools "ffmpeg.zip"
            Invoke-WebRequest -Uri "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" `
                -OutFile $zip -UseBasicParsing
            Expand-Archive -Path $zip -DestinationPath (Join-Path $tools "ffx") -Force
            $found = Get-ChildItem (Join-Path $tools "ffx") -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
            Copy-Item $found.FullName $local -Force
            $probe = Get-ChildItem (Join-Path $tools "ffx") -Recurse -Filter "ffprobe.exe" | Select-Object -First 1
            if ($probe) { Copy-Item $probe.FullName (Join-Path $tools "ffprobe.exe") -Force }
        }
    }
    return $local
}

function To-TimeString {
    param([string]$Value)
    $p = $Value.Split(":")
    if ($p.Count -eq 2) { return [TimeSpan]::new(0, [int]$p[0], [int]$p[1]) }
    if ($p.Count -eq 3) { return [TimeSpan]::new([int]$p[0], [int]$p[1], [int]$p[2]) }
    throw "Moc thoi gian khong hop le: $Value"
}

$ytdlp    = Resolve-Tool -Name "yt-dlp"
$ffmpeg   = Resolve-Tool -Name "ffmpeg"
$ffprobe  = Resolve-Tool -Name "ffprobe"

$t0  = To-TimeString $Start
$t1  = $t0.Add([TimeSpan]::FromSeconds($Duration))
$sec = "*{0:hh\:mm\:ss}-{1:hh\:mm\:ss}" -f $t0, $t1
$raw = Join-Path $tools "section.%(ext)s"

$args = @(
    "--no-playlist",
    "--extractor-args", "youtube:player_client=$Client",
    "-f", "bv*[height<=1080]+ba/b[height<=1080]/b",
    "--merge-output-format", "mp4",
    "--download-sections", $sec,
    "--force-keyframes-at-cuts",
    "-o", $raw,
    $Url
)
if ($Browser) { $args = @("--cookies-from-browser", $Browser) + $args }

Write-Host "[1/2] Tai doan $sec tu YouTube (client: $Client)" -ForegroundColor Cyan
& $ytdlp @args
if ($LASTEXITCODE -ne 0) { throw "yt-dlp that bai (exit $LASTEXITCODE). Thu them -Browser firefox." }

$src = Get-ChildItem $tools -Filter "section.*" |
        Where-Object { $_.Extension -notin @(".part", ".ytdl") } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $src) { throw "Khong tim thay file vua tai." }

$height = [int]([math]::Round($Width * 9 / 16 / 2) * 2)

Write-Host "[2/2] Xuat $OutFile (${Width}x${height})" -ForegroundColor Cyan
& $ffmpeg -y -hide_banner -loglevel error -i $src.FullName `
    -t $Duration -an `
    -vf "scale=${Width}:${height}:flags=lanczos,unsharp=5:5:0.55:5:5:0.0" `
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p `
    -movflags +faststart $OutFile
if ($LASTEXITCODE -ne 0) { throw "ffmpeg that bai (exit $LASTEXITCODE)" }

if (-not $KeepRaw) { Remove-Item $src.FullName -Force }

Write-Host ""
Write-Host "Xong: $OutFile" -ForegroundColor Green
& $ffprobe -hide_banner -v error -show_entries format=duration:stream=width,height,codec_name `
    -of default=noprint_wrappers=1 $OutFile
