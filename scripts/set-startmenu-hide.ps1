#requires -Version 5.1
<#
  set-startmenu-hide.ps1 - an bot cac khoi cua Start menu Windows 11.

  Lam qua mod "Windows 11 Start Menu Styler".

  -Preset pinned   (AN TOAN, da kiem chung)
      StartMenu.PinnedList                                  -> ca khoi app ghim
      Windows.UI.Xaml.Controls.TextBlock#PinnedListHeaderText -> chu "Pinned"

  -Preset apps  (DA TAT - lam crash Start menu, xem cuoi file)

  -Mode hide / show / status.   hide|show can quyen admin.

  CANH BAO KY THUAT (da tung lam hong Start menu):
    Collapse mot element ma XAML engine can -> nem exception luc layout ->
    StartMenuExperienceHost.exe chet ngay khi bam Start (Event Viewer ghi
    "Faulting module name: StartMenu.dll"). Chi collapse nhung element ban
    CHAC CHAN khong phai phan bat buoc cua layout, va test ngay sau khi them.

  LUU Y: ten gia tri registry o day chua '[', ']' - PowerShell coi chung la
  WILDCARD, nen Remove-ItemProperty -Name 'controlStyles[7].target' KHONG xoa
  duoc gi (that bai im lang). Script nay dung thang API .NET.

  Vi du:
    .\scripts\set-startmenu-hide.ps1 -Preset pinned -Mode hide
    .\scripts\set-startmenu-hide.ps1 -Preset pinned -Mode show
    .\scripts\set-startmenu-hide.ps1 -Targets "StartMenu.Foo" -Mode hide
#>
[CmdletBinding()]
param(
    [ValidateSet("pinned", "view", "bare", "apps")]
    [string]$Preset,

    # Style ap cho target. Mac dinh an han; dung 'Opacity=0' de chi lam mo
    # (element van nam trong layout -> an toan hon, khong lam XAML engine no).
    [string]$Style = "Visibility=Collapsed",

    [Parameter(Mandatory = $true)]
    [ValidateSet("hide", "show", "status")]
    [string]$Mode,

    # Chi dinh tay danh sach target (bo qua preset).
    [string[]]$Targets,

    [string]$ModId = "windows-11-start-menu-styler"
)

$ErrorActionPreference = "Stop"

$presets = @{
    pinned = @(
        "StartMenu.PinnedList",
        "Windows.UI.Xaml.Controls.TextBlock#PinnedListHeaderText"
    )
    # An nut "View: Category|Grid|List" o goc phai tren cua muc All, va chu "All".
    #   Microsoft.UI.Xaml.Controls.DropDownButton#ViewSelectionButton
    #       -> type lay tu source cua mod, ten 'ViewSelectionButton' co that
    #          trong build nay (StartMenu.dll)
    #   TextBlock#AllAppsListHeadingText / TextBlock#AllHeading
    #       -> hai ten ung vien cho chu "All"; ten nao khong co thi style
    #          khong khop gi (vo hai)
    view = @(
        "Microsoft.UI.Xaml.Controls.DropDownButton#ViewSelectionButton",
        "Windows.UI.Xaml.Controls.TextBlock#AllAppsListHeadingText",
        "Windows.UI.Xaml.Controls.TextBlock#AllHeading"
    )

    # Chi de lai thanh search: lam mo (Opacity=0) toan bo khu app.
    # Dung Opacity=0 chu KHONG Collapsed: element van tham gia layout nen khong
    # lam XAML engine nem exception (bai hoc tu vu crash StartMenu.dll).
    # Dat kem -Style "Opacity=0".
    bare = @(
        "StartMenu.AllAppsControl",
        "Grid#AllAppsRoot",
        "GridView#AllAppsGrid",
        "Windows.UI.Xaml.Controls.TextBlock#AllAppsListHeadingText",
        "Windows.UI.Xaml.Controls.TextBlock#AllHeading"
    )

    # RONG co ly do: xem ghi chu o cuoi file.
    apps = @()
}

if ($Targets) { }
elseif ($Preset) { $Targets = $presets[$Preset] }
else { throw "Can -Preset hoac -Targets." }

if ($Targets.Count -eq 0) {
    Write-Host ""
    Write-Host "Preset '$Preset' da bi vo hieu hoa." -ForegroundColor Yellow
    Write-Host "Ly do: cach nay tung lam StartMenuExperienceHost.exe crash lien tuc" -ForegroundColor Yellow
    Write-Host "(Event Viewer: 'Faulting module name: StartMenu.dll'), bam Start khong hien gi." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Muon an khu vuc app, phai soi cay XAML song truoc de biet ten + type" -ForegroundColor DarkGray
    Write-Host "that su ton tai trong build nay (vi du bang UWPSpy cua m417z), roi dung:" -ForegroundColor DarkGray
    Write-Host "  .\scripts\set-startmenu-hide.ps1 -Targets ""<Type>#<Name>"" -Mode hide" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Cuu khi da lam hong: .\scripts\restore-startmenu.ps1 -Mode restore" -ForegroundColor DarkGray
    Write-Host ""
    return
}

$regSub    = "SOFTWARE\Windhawk\Engine\Mods\$ModId"
$regSubKey = "HKLM:\$regSub"

if (-not (Test-Path $regSubKey)) { throw "Khong thay mod '$ModId'. Da cai Windows 11 Start Menu Styler chua?" }

function Get-SettingsKey {
    param([switch]$Writable)
    $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$regSub\Settings", [bool]$Writable)
    if (-not $k) { throw "Khong mo duoc Settings cua $ModId" }
    return $k
}

function Read-Entries {
    $k = Get-SettingsKey
    try {
        $map = @{}
        foreach ($n in $k.GetValueNames()) {
            if ($n -match '^controlStyles\[(\d+)\]\.(target|styles\[(\d+)\])$') {
                $idx = [int]$Matches[1]
                if (-not $map.ContainsKey($idx)) { $map[$idx] = @{ target = $null; styles = @{} } }
                if ($Matches[2] -eq 'target') { $map[$idx].target = $k.GetValue($n) }
                else { $map[$idx].styles[[int]$Matches[3]] = $k.GetValue($n) }
            }
        }
        return $map
    }
    finally { $k.Close() }
}

function Show-State {
    Write-Host ""
    Write-Host "controlStyles cua ${ModId}:" -ForegroundColor Cyan
    $map = Read-Entries
    foreach ($idx in ($map.Keys | Sort-Object)) {
        Write-Host ("  [{0}] {1}" -f $idx, $map[$idx].target)
        foreach ($j in ($map[$idx].styles.Keys | Sort-Object)) {
            if ("$($map[$idx].styles[$j])".Trim()) { Write-Host "        $($map[$idx].styles[$j])" -ForegroundColor DarkGray }
        }
    }
    Write-Host ""
}

if ($Mode -eq 'status') { Show-State; return }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw "Can quyen admin." }

$map = Read-Entries

if ($Mode -eq 'hide') {
    $k = Get-SettingsKey -Writable
    try {
        $next = 0
        if ($map.Keys.Count -gt 0) { $next = ($map.Keys | Measure-Object -Maximum).Maximum + 1 }

        foreach ($t in $Targets) {
            $existing = $null
            foreach ($idx in $map.Keys) { if ($map[$idx].target -eq $t) { $existing = $idx; break } }

            if ($null -ne $existing) {
                $k.SetValue("controlStyles[$existing].styles[0]", $Style,
                    [Microsoft.Win32.RegistryValueKind]::String)
                Write-Host "  cap nhat [$existing] $t  ->  $Style" -ForegroundColor Green
            } else {
                $k.SetValue("controlStyles[$next].target", $t, [Microsoft.Win32.RegistryValueKind]::String)
                $k.SetValue("controlStyles[$next].styles[0]", $Style,
                    [Microsoft.Win32.RegistryValueKind]::String)
                Write-Host "  them moi  [$next] $t" -ForegroundColor Green
                $next++
            }
        }
    }
    finally { $k.Close() }
}
else {
    $k = Get-SettingsKey -Writable
    $removed = 0
    try {
        foreach ($idx in @($map.Keys | Sort-Object -Descending)) {
            $t = $map[$idx].target
            if ($Targets -notcontains $t) { continue }
            $want = '^\s*' + [regex]::Escape($Style).Replace('\ ', '\s*') + '\s*$'
            $isMatch = @($map[$idx].styles.Values | Where-Object { $_ -match $want })
            if (-not $isMatch) { continue }

            foreach ($n in @($k.GetValueNames())) {
                if ($n -match "^controlStyles\[$idx\]\.") { $k.DeleteValue($n, $false) }
            }
            Write-Host "  da go [$idx] $t" -ForegroundColor Green
            $removed++
        }
    }
    finally { $k.Close() }
    if ($removed -eq 0) { Write-Host "  khong co entry nao can go" -ForegroundColor Yellow }
}

$mk = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($regSub, $true)
try {
    $mk.SetValue("SettingsChangeTime", [int][double]::Parse((Get-Date -UFormat %s)),
        [Microsoft.Win32.RegistryValueKind]::DWord)
}
finally { $mk.Close() }

Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Xong ($Mode). Bam phim Windows de kiem tra NGAY." -ForegroundColor Green
Write-Host "Neu menu khong hien: .\scripts\restore-startmenu.ps1 -Mode restore" -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# Vi sao preset 'apps' bi tat:
#
# Da thu collapse khu vuc "All" bang:
#     Grid#AllAppsRoot, GridView#AllAppsGrid, Grid#AllListHeading
# Ket qua: StartMenuExperienceHost.exe crash lien tuc (12:37-12:49), Event
# Viewer ghi "Faulting application name: StartMenuExperienceHost.exe ...
# Faulting module name: StartMenu.dll", bam phim Windows khong hien gi.
#
# Ten trong build 25H2 (MicrosoftWindows.Client.Core\StartMenu.dll) la
# AllAppsRoot / AllAppsGrid / AllAppsControl / CategoryControl / AllHeading,
# nhung type that cua tung element thi chua xac minh, va collapse sai element
# la du de XAML engine no. Truoc khi thu lai: soi cay XAML song (UWPSpy) de
# biet chinh xac Type#Name, roi them MOT target, test ngay, va giu san
# restore-startmenu.ps1 de cuu.
# ---------------------------------------------------------------------------
