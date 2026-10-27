#requires -Version 5.1
<#
  set-startmenu-bg.ps1 - doi nen Start menu dang dung gi, trong mod
  "Windows 11 Start Menu Styler".

  Hai cach lam nen, KHONG duoc bat cung luc:

    -Mode image   nen la anh/GIF qua ImageBrush, tro toi 1 URL cong khai
                  (mac dinh: start-menu.gif trong repo kh4i-dev/wallpapers)
    -Mode video   bo nen cua mod Styler di (Background=Transparent) de nhan
                  nhuong cho XAML-Video-Injector (video that, co chuyen dong)
    -Mode show    chi in ra dang dat gi, khong sua (khong can admin)

  PHAI CHAY BANG QUYEN ADMIN voi -Mode image / -Mode video.

  Vi du:
    .\scripts\set-startmenu-bg.ps1 -Mode video
    .\scripts\set-startmenu-bg.ps1 -Mode image
    .\scripts\set-startmenu-bg.ps1 -Mode image -ImageUrl https://.../khac.gif
    .\scripts\set-startmenu-bg.ps1 -Mode show
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("image", "video", "show")]
    [string]$Mode,

    [string]$ImageUrl = "https://raw.githubusercontent.com/kh4i-dev/wallpapers/main/start-menu.gif",

    [string[]]$Targets = @("Border#AcrylicBorder", "Border#AppBorder", "Border#AccentAppBorder"),

    [string]$ModId = "windows-11-start-menu-styler"
)

$ErrorActionPreference = "Stop"

$regKey = "HKLM:\SOFTWARE\Windhawk\Engine\Mods\$ModId\Settings"
$backupDir = Join-Path $env:TEMP "startmenu-bg-backup"
$backupFile = Join-Path $backupDir "controlStyles.json"

function Get-StyleMap {
    $key = Get-Item $regKey -ErrorAction SilentlyContinue
    if (-not $key) { throw "Khong thay mod '$ModId' trong registry. Da cai mod Windows 11 Start Menu Styler chua?" }

    $map = @{}
    foreach ($name in $key.Property) {
        if ($name -match '^controlStyles\[(\d+)\]\.(target|styles\[(\d+)\])$') {
            $idx = [int]$Matches[1]
            if (-not $map.ContainsKey($idx)) { $map[$idx] = @{ target = $null; styles = @{} } }
            if ($Matches[2] -eq 'target') {
                $map[$idx].target = $key.GetValue($name)
            } else {
                $map[$idx].styles[[int]$Matches[3]] = $key.GetValue($name)
            }
        }
    }
    return $map
}

$map = Get-StyleMap

if ($Mode -eq 'show') {
    Write-Host "" 
    Write-Host "Nen Start menu hien tai ($ModId):" -ForegroundColor Cyan
    foreach ($idx in ($map.Keys | Sort-Object)) {
        $e = $map[$idx]
        Write-Host ("  [{0}] {1}" -f $idx, $e.target)
        foreach ($j in ($e.styles.Keys | Sort-Object)) {
            if ("$($e.styles[$j])".Trim()) { Write-Host "        $($e.styles[$j])" -ForegroundColor DarkGray }
        }
    }
    Write-Host ""
    return
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw "Can quyen admin de sua registry cua Windhawk." }

# --- sao luu nguyen trang cau hinh controlStyles hien tai
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$dump = @{}
$key = Get-Item $regKey
foreach ($name in $key.Property) {
    if ($name -match '^controlStyles\[') { $dump[$name] = $key.GetValue($name) }
}
$dump | ConvertTo-Json -Depth 5 | Set-Content $backupFile -Encoding UTF8
Write-Host "  backup -> $backupFile" -ForegroundColor DarkGray

$newBackground = switch ($Mode) {
    'video' { 'Background=Transparent' }
    'image' { 'Background:=<ImageBrush Stretch="UniformToFill" Opacity="1" ImageSource="' + $ImageUrl + '" />' }
}

$changed = 0
foreach ($idx in ($map.Keys | Sort-Object)) {
    $target = $map[$idx].target
    if (-not $target -or ($Targets -notcontains $target)) { continue }

    # tim style bat dau bang "Background" trong entry nay
    $slot = $null
    foreach ($j in ($map[$idx].styles.Keys | Sort-Object)) {
        if ("$($map[$idx].styles[$j])" -match '^\s*Background\s*[:=]') { $slot = $j; break }
    }
    $regName = if ($null -ne $slot) { "controlStyles[$idx].styles[$slot]" }
               else { "controlStyles[$idx].styles[$($map[$idx].styles.Keys.Count)]" }

    Set-ItemProperty -Path $regKey -Name $regName -Value $newBackground -Type String -Force
    Write-Host "  $target  ->  $regName" -ForegroundColor Green
    $changed++
}

if ($changed -eq 0) {
    Write-Host ""
    Write-Host "  Khong tim thay target nao trong: $($Targets -join ', ')" -ForegroundColor Yellow
    Write-Host "  Chay '-Mode show' de xem cac target dang co." -ForegroundColor Yellow
    return
}

# bao cho Windhawk biet setting vua doi
Set-ItemProperty -Path (Split-Path $regKey -Parent) -Name "SettingsChangeTime" `
    -Value ([int][double]::Parse((Get-Date -UFormat %s))) -Type DWord -Force

Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "Xong ($Mode). Bam phim Windows de xem." -ForegroundColor Green
if ($Mode -eq 'video') {
    Write-Host "Video do XAML-Video-Injector ve (nho dat startMenuVideoUrl)." -ForegroundColor DarkGray
} else {
    Write-Host "Anh: $ImageUrl" -ForegroundColor DarkGray
}
