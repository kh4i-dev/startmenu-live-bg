#requires -Version 5.1
<#
  restore-startmenu.ps1 - cuu Start menu khi bi mod lam crash.

  Trieu chung: bam phim Windows khong thay gi; Event Viewer co
  "Faulting application name: StartMenuExperienceHost.exe ... Faulting module
  name: StartDocked.dll / StartMenu.dll".

  Nguyen nhan: mot controlStyle trong mod "Windows 11 Start Menu Styler"
  collapse mot element ma XAML engine can -> nem exception luc layout -> tien
  trinh Start menu chet ngay khi mo.

  -Mode restore   xoa het controlStyles roi ghi lai tu file backup
  -Mode disable   tat han mod Start Menu Styler (Disabled=1) - cuu cuoi
  -Mode enable    bat lai mod
  -Mode status    in trang thai (khong can admin)

  PHAI CHAY BANG QUYEN ADMIN (tru -Mode status).

  LUU Y KY THUAT: ten gia tri registry o day chua '[', ']' - PowerShell hieu
  chung la WILDCARD, nen Remove-ItemProperty -Name 'controlStyles[7].target'
  KHONG xoa duoc gi. Script nay dung thang API .NET de tranh bay do.

  Vi du:
    .\scripts\restore-startmenu.ps1 -Mode restore
    .\scripts\restore-startmenu.ps1 -Mode disable
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("restore", "disable", "enable", "status")]
    [string]$Mode,

    [string]$BackupFile = "",
    [string]$ModId = "windows-11-start-menu-styler"
)

$ErrorActionPreference = "Stop"

$regSub    = "SOFTWARE\Windhawk\Engine\Mods\$ModId"
$regSubSet = "$regSub\Settings"
$regSubKey = "HKLM:\$regSub"

if (-not (Test-Path $regSubKey)) { throw "Khong thay mod '$ModId'." }

function Get-SettingsKey {
    param([switch]$Writable)
    $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
        $regSubSet, [bool]$Writable)
    if (-not $k) { throw "Khong mo duoc key $regSubSet" }
    return $k
}

function Set-Value {
    param($key, [string]$name, $value, [string]$kind = "String")
    $key.SetValue($name, [string]$value,
        [Microsoft.Win32.RegistryValueKind]::$kind)
}

function Show-State {
    $disabled = 0
    $mk = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($regSub)
    if ($mk) { $disabled = $mk.GetValue("Disabled", 0); $mk.Close() }

    Write-Host ""
    Write-Host "Mod $ModId : $(if ($disabled) { 'DANG TAT' } else { 'dang bat' })" -ForegroundColor Cyan

    $k = Get-SettingsKey
    try {
        $targets = @($k.GetValueNames() | Where-Object { $_ -match '^controlStyles\[\d+\]\.target$' } |
                     Sort-Object { [int]([regex]::Match($_, '\d+').Value) })
        foreach ($tn in $targets) {
            $idx = [regex]::Match($tn, '\d+').Value
            $styles = @($k.GetValueNames() | Where-Object { $_ -match "^controlStyles\[$idx\]\.styles\[\d+\]$" } |
                        Sort-Object | ForEach-Object { $k.GetValue($_) }) -join ' | '
            Write-Host ("  [{0}] {1}" -f $idx, $k.GetValue($tn)) -NoNewline
            Write-Host "   $styles" -ForegroundColor DarkGray
        }
    }
    finally { $k.Close() }
    Write-Host ""
}

if ($Mode -eq 'status') { Show-State; return }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw "Can quyen admin." }

Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue

if ($Mode -eq 'disable' -or $Mode -eq 'enable') {
    $mk = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($regSub, $true)
    try {
        $mk.SetValue("Disabled", [int]$(if ($Mode -eq 'disable') { 1 } else { 0 }),
            [Microsoft.Win32.RegistryValueKind]::DWord)
        $mk.SetValue("SettingsChangeTime",
            [int][double]::Parse((Get-Date -UFormat %s)),
            [Microsoft.Win32.RegistryValueKind]::DWord)
    }
    finally { $mk.Close() }
    Write-Host "Da $(if ($Mode -eq 'disable') { 'TAT' } else { 'BAT' }) mod $ModId." -ForegroundColor Green
    Show-State
    return
}

# ---------------------------------------------------------------- restore
if (-not $BackupFile) {
    $cands = Get-ChildItem "$env:TEMP\startmenu-hide-backup\controlStyles.json",
                            "$env:TEMP\startmenu-bg-backup\controlStyles.json" -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending
    if (-not $cands) { throw "Khong thay backup nao. Dung -BackupFile, hoac -Mode disable." }
    $BackupFile = $cands[0].FullName
}
if (-not (Test-Path $BackupFile)) { throw "Khong thay backup: $BackupFile" }

Write-Host "Khoi phuc tu: $BackupFile" -ForegroundColor Cyan
$dump = Get-Content $BackupFile -Raw | ConvertFrom-Json

$k = Get-SettingsKey -Writable
try {
    # xoa het bang API .NET -> khong dinh bay wildcard cua ten co []
    $existing = @($k.GetValueNames() | Where-Object { $_ -match '^controlStyles\[' })
    foreach ($n in $existing) { $k.DeleteValue($n, $false) }
    Write-Host "  da xoa $($existing.Count) gia tri controlStyles cu" -ForegroundColor DarkGray

    foreach ($p in $dump.PSObject.Properties) { Set-Value $k $p.Name $p.Value }
    Write-Host "  da ghi lai $($dump.PSObject.Properties.Count) gia tri tu backup" -ForegroundColor DarkGray
}
finally { $k.Close() }

$mk = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($regSub, $true)
try {
    $mk.SetValue("SettingsChangeTime", [int][double]::Parse((Get-Date -UFormat %s)),
        [Microsoft.Win32.RegistryValueKind]::DWord)
}
finally { $mk.Close() }

Write-Host "Da khoi phuc controlStyles." -ForegroundColor Green
Show-State
