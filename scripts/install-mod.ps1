#requires -Version 5.1
<#
  install-mod.ps1 - cai dat / go bo mod "XAML-Video-Injector" cho Windhawk
  va dat san video lam nen Start menu.

  Windhawk 1.7.3 khong co CLI de cai mod (CLI `windhawk-cli` chi co tu ban
  2.0-alpha), nen script nay lam dung nhung gi giao dien Windhawk lam:

    1. tai .wh.cpp cua mod (hoac dung file co san)
    2. compile bang clang++.exe cua Windhawk, dung y nguyen tham so
       trong compilerUtils.ts (v1.7.3) cua ramensoftware/windhawk
    3. copy DLL -> <appdata>\Engine\Mods\64\  + nguon -> <appdata>\ModsSource\
    4. ghi cau hinh vao HKLM\SOFTWARE\Windhawk\Engine\Mods\<id>  (+ \Settings)
    5. khoi dong lai Windhawk va StartMenuExperienceHost

  PHAI CHAY BANG QUYEN ADMIN (can ghi vao ProgramData + HKLM).

  Vi du:
    .\scripts\install-mod.ps1 -VideoPath "D:\startmenu-live-bg\media\start-bg.mp4"
    .\scripts\install-mod.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    # Video lam nen Start menu. Bo trong neu chi muon cai mod.
    [string]$VideoPath = "",

    # Nguon mod: file .wh.cpp co san, hoac URL.
    [string]$SourceFile = "",
    [string]$SourceUrl = "https://raw.githubusercontent.com/bbmaster123/FWFU/refs/heads/main/Personal%20Windhawk%20Mods/XAML-Video-Injector.cpp",

    # DLL da compile san (bo qua buoc compile).
    [string]$DllFile = "",

    [string]$Id = "xaml-video-injector",
    [string]$Version = "1.0.0",

    # Gia tri mac dinh cho Start menu.
    [int]$ZIndex = -1,
    [int]$Opacity = 100,
    [int]$Rate = 100,
    [int]$CornerRadius = 8,

    [switch]$NoRestartStartMenu,
    [switch]$NoLayoutPatch,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

function Write-Step($n, $msg) { Write-Host "[$n] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)       { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn2($msg)    { Write-Host "    $msg" -ForegroundColor Yellow }

<#
  Va loi layout cua XAML-Video-Injector.

  Trong CreateAndInjectVideo() (ban UWP, dung cho Start menu) mod tao mot Grid
  roi chen vao child[0] cua root Start menu, NHUNG khong dat Width/Height.
  MediaPlayerElement khong co kich thuoc se cong kich thuoc tu nhien cua video
  (vi du 1280x720) vao desired size cua Grid cha => Start menu rong ra va tran
  khoi man hinh.

  Ban va ghim kich thuoc cua ca container lan player theo dung o chua, va dong
  bo lai moi khi o chua doi kich thuoc.

  Chi sua ban UWP: ban WinUI3 (CreateAndInjectVideoWinUI3) nam sau va khong
  duoc Start menu dung toi, sua vao se sai namespace (mux::).
#>
function Repair-XamlVideoInjectorLayout {
    param([string]$Source, [string]$Path)

    if ($Source.Contains('[patch] Ghim kich thuoc')) {
        Write-Ok "ban va layout: da co san, bo qua"
        return $Source
    }

    $anchorA = "        videoContainer.Opacity(0);`n"
    $anchorB = "        player.IsHitTestVisible(false);`n"

    if (-not $Source.Contains($anchorA) -or -not $Source.Contains($anchorB)) {
        Write-Warn2 "khong tim thay diem neo de va layout - mod da doi? Bo qua ban va."
        return $Source
    }

    $patchA = @"
        videoContainer.Opacity(0);

        // [patch] Ghim kich thuoc vao dung o chua. MediaPlayerElement khong co
        // Width/Height se cong kich thuoc tu nhien cua video (1280x720) vao
        // desired size -> Grid cha phinh ra -> Start menu rong va tran man hinh.
        const double fixedW = targetGrid.ActualWidth();
        const double fixedH = targetGrid.ActualHeight();
        if (fixedW > 0 && fixedH > 0) {
            videoContainer.Width(fixedW);
            videoContainer.Height(fixedH);
        }
"@

    $patchB = @"
        player.IsHitTestVisible(false);
        if (fixedW > 0 && fixedH > 0) {
            player.Width(fixedW);
            player.Height(fixedH);
            auto weakContainer = winrt::make_weak(videoContainer);
            auto weakPlayer = winrt::make_weak(player);
            targetGrid.SizeChanged([weakContainer, weakPlayer](
                    auto const&, winrt::Windows::UI::Xaml::SizeChangedEventArgs const& args) {
                auto const& sz = args.NewSize();
                if (auto c = weakContainer.get()) { c.Width(sz.Width); c.Height(sz.Height); }
                if (auto p = weakPlayer.get()) { p.Width(sz.Width); p.Height(sz.Height); }
            });
        }
"@

    # thay B truoc (nam sau A) de chi so cua A khong bi lech
    $iB = $Source.IndexOf($anchorB)
    $s2 = $Source.Substring(0, $iB) + $patchB + $Source.Substring($iB + $anchorB.Length)
    $iA = $s2.IndexOf($anchorA)
    $patched = $s2.Substring(0, $iA) + $patchA + $s2.Substring($iA + $anchorA.Length)

    Set-Content $Path -Value $patched -NoNewline
    Write-Ok "ban va layout: da ghim kich thuoc video vao o chua"
    return $patched
}

# ---------------------------------------------------------------- quyen admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "Script nay can quyen admin. Mo PowerShell bang 'Run as administrator' roi chay lai."
}

# ------------------------------------------------------------------ duong dan
$appRoot = "C:\Program Files\Windhawk"
if (-not (Test-Path $appRoot)) { $appRoot = Split-Path (Get-Command windhawk.exe).Source }

$iniPath = Join-Path $appRoot "windhawk.ini"
$appDataPath = Join-Path $env:ProgramData "Windhawk"
$compilerPath = Join-Path $appRoot "Compiler"
$engineRoot = Join-Path $appRoot "Engine"

if (Test-Path $iniPath) {
    $ini = @{}
    Get-Content $iniPath | ForEach-Object {
        if ($_ -match '^\s*([^=\[]+?)\s*=\s*(.+?)\s*$') { $ini[$Matches[1]] = $Matches[2] }
    }
    if ($ini['AppDataPath']) {
        $appDataPath = [Environment]::ExpandEnvironmentVariables($ini['AppDataPath'])
    }
    if ($ini['CompilerPath']) { $compilerPath = Join-Path $appRoot $ini['CompilerPath'] }
    if ($ini['EnginePath'])   { $engineRoot   = Join-Path $appRoot $ini['EnginePath'] }
}

# thu muc Engine chua windhawk.lib: lay ban moi nhat neu EnginePath tro sai
if (-not (Test-Path (Join-Path $engineRoot "64\windhawk.lib"))) {
    $alt = Get-ChildItem $engineRoot -Directory -ErrorAction SilentlyContinue |
           Sort-Object Name -Descending | Select-Object -First 1
    if ($alt) { $engineRoot = $alt.FullName }
}

$engineModsDir = Join-Path $appDataPath "Engine\Mods\64"
$modsSourceDir = Join-Path $appDataPath "ModsSource"
$regRoot       = "HKLM:\SOFTWARE\Windhawk\Engine\Mods"
$regKey        = Join-Path $regRoot $Id

Write-Host ""
Write-Host "Windhawk      : $appRoot" -ForegroundColor DarkGray
Write-Host "Mods          : $engineModsDir" -ForegroundColor DarkGray
Write-Host "ModsSource    : $modsSourceDir" -ForegroundColor DarkGray
Write-Host ""

# ------------------------------------------------------------------- go bo mod
if ($Uninstall) {
    Write-Step 1 "Go bo mod $Id"
    $windhawkExe = Join-Path $appRoot "windhawk.exe"

    # dong Start menu truoc: no dang giu DLL cua mod nen xoa se that bai
    Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue
    if (Get-Process -Name windhawk -ErrorAction SilentlyContinue) {
        & $windhawkExe -exit -wait 2>$null
        Start-Sleep -Milliseconds 800
    }

    if (Test-Path $regKey) { Remove-Item $regKey -Recurse -Force; Write-Ok "da xoa registry" }

    foreach ($f in @(Get-ChildItem $engineModsDir -Filter "$Id*.dll" -ErrorAction SilentlyContinue)) {
        try { Remove-Item $f.FullName -Force -ErrorAction Stop; Write-Ok "da xoa $($f.Name)" }
        catch { Write-Warn2 "$($f.Name) dang bi mot tien trinh giu (thuong la explorer.exe) - se xoa duoc sau khi dang xuat/dang nhap lai" }
    }

    $src = Join-Path $modsSourceDir "$Id.wh.cpp"
    if (Test-Path $src) {
        try { Remove-Item $src -Force -ErrorAction Stop; Write-Ok "da xoa source" }
        catch { Write-Warn2 "khong xoa duoc source" }
    }

    Start-Process $windhawkExe -ArgumentList "-tray-only"
    Write-Host ""
    Write-Host "Xong. Mod da duoc go." -ForegroundColor Green
    return
}

if ($VideoPath -and -not (Test-Path $VideoPath)) {
    throw "Khong tim thay video: $VideoPath"
}

# ------------------------------------------------------------- 1. lay nguon mod
Write-Step 1 "Lay nguon mod"
$workDir = Join-Path $env:TEMP "windhawk-install-$Id"
New-Item -ItemType Directory -Force -Path $workDir | Out-Null
$srcPath = Join-Path $workDir "$Id.wh.cpp"

if ($SourceFile) {
    Copy-Item $SourceFile $srcPath -Force
    Write-Ok "dung file: $SourceFile"
}
else {
    Invoke-WebRequest -Uri $SourceUrl -OutFile $srcPath -UseBasicParsing
    Write-Ok "tai tu: $SourceUrl"
}
$sourceText = Get-Content $srcPath -Raw

# doc metadata tu header ==WindhawkMod==
$hdr = $sourceText -split '==WindhawkMod==', 3
$meta = @{}
if ($hdr.Count -ge 2) {
    foreach ($line in ($hdr[1] -split "`n")) {
        if ($line -match '^\s*//\s*@(\w+)\s+(.*?)\s*$') { $meta[$Matches[1]] = $Matches[2] }
    }
}
if ($meta['id'])      { $Id = $meta['id'].Trim() }
if ($meta['version']) { $Version = $meta['version'].Trim() }

# @include xuat hien nhieu lan -> phai gom lai, khong duoc de hashtable ghi de
$includes = @()
foreach ($m in [regex]::Matches($sourceText, '(?m)^\s*//\s*@include\s+(\S+)\s*$')) {
    $includes += $m.Groups[1].Value
}
$arch       = if ($meta['architecture']) { $meta['architecture'].Trim() } else { "x86-64" }
$compilerOpts = if ($meta['compilerOptions']) { $meta['compilerOptions'].Trim() } else { "" }
Write-Ok "id=$Id  version=$Version  arch=$arch"
Write-Ok "include: $($includes -join ' | ')"

if (-not $NoLayoutPatch -and $Id -eq "xaml-video-injector") {
    $sourceText = Repair-XamlVideoInjectorLayout -Source $sourceText -Path $srcPath
}

# ---------------------------------------------------------------- 2. compile
Write-Step 2 "Compile mod"
if ($DllFile) {
    $newDllName = "$Id`_$Version`_$(Get-Random -Minimum 100000 -Maximum 999999).dll"
    Copy-Item $DllFile (Join-Path $workDir $newDllName) -Force
    Write-Ok "dung DLL co san: $DllFile"
}
else {
    $clang     = Join-Path $compilerPath "bin\clang++.exe"
    $engineLib = Join-Path $engineRoot "64\windhawk.lib"
    if (-not (Test-Path $clang))     { throw "Khong thay clang: $clang" }
    if (-not (Test-Path $engineLib)) { throw "Khong thay windhawk.lib: $engineLib" }

    # thu muc Engine\Mods\64 co the chua ghi duoc -> build ra temp truoc
    do {
        $newDllName = "$Id`_$Version`_$(Get-Random -Minimum 100000 -Maximum 999999).dll"
    } while (Test-Path (Join-Path $engineModsDir $newDllName))
    $buildDll = Join-Path $workDir $newDllName

    $defines = @(
        '-DWINVER=0x0A00', '-D_WIN32_WINNT=0x0A00', '-D_WIN32_IE=0x0A00', '-DNTDDI_VERSION=0x0A000008'
    )
    # Phai tinh truoc: trong array literal @(), bieu thuc
    #   '-DWH_MOD_ID=L"' + $Id + '"'
    # bi PowerShell tach thanh 3 phan tu rieng, clang se nhan 3 argument rac.
    $defModId  = '-DWH_MOD_ID=L"' + $Id + '"'
    $defModVer = '-DWH_MOD_VERSION=L"' + $Version + '"'

    $clangArgs = @(
        '-std=c++23', '-O2', '-shared',
        '-DUNICODE', '-D_UNICODE'
    ) + $defines + @(
        '-D__USE_MINGW_ANSI_STDIO=0',
        '-DWH_MOD',
        $defModId,
        $defModVer,
        $engineLib,
        '-x', 'c++', '-',
        '-include', 'windhawk_api.h',
        '-target', 'x86_64-w64-mingw32',
        '-Wl,--export-all-symbols',
        '-o', $buildDll
    )
    if ($compilerOpts) { $clangArgs += ($compilerOpts -split '\s+' | Where-Object { $_ }) }

    # Start-Process ghep argv bang dau cach -> phai tu escape
    $quoted = $clangArgs | ForEach-Object {
        $e = $_ -replace '"', '\"'
        if ($e -match '\s') { '"' + $e + '"' } else { $e }
    }

    $outLog = Join-Path $workDir "compile.out"
    $errLog = Join-Path $workDir "compile.err"
    $p = Start-Process -FilePath $clang -ArgumentList $quoted -WorkingDirectory $compilerPath `
            -RedirectStandardInput $srcPath -RedirectStandardOutput $outLog -RedirectStandardError $errLog `
            -NoNewWindow -PassThru -Wait

    if ($p.ExitCode -ne 0 -or -not (Test-Path $buildDll)) {
        Get-Content $errLog -ErrorAction SilentlyContinue | Select-Object -Last 25 | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        throw "Compile that bai (exit $($p.ExitCode))"
    }
    Write-Ok "compile xong: $([math]::Round((Get-Item $buildDll).Length/1KB)) KB"
}

# ------------------------------------------- 3. dung Windhawk, copy file vao cho
Write-Step 3 "Cai dat file"
$windhawkExe = Join-Path $appRoot "windhawk.exe"
$running = Get-Process -Name windhawk -ErrorAction SilentlyContinue
if ($running) {
    & $windhawkExe -exit -wait 2>$null
    Start-Sleep -Milliseconds 800
    Write-Ok "da dong cua so Windhawk (service van chay)"
}

function Set-RegString($path, $name, $value) {
    if ($null -eq (Get-Item $path).GetValue($name)) {
        New-ItemProperty -Path $path -Name $name -Value $value -PropertyType String -Force | Out-Null
    } else {
        Set-ItemProperty -Path $path -Name $name -Value $value -Type String -Force
    }
}
function Set-RegDword($path, $name, $value) {
    # DWORD la 32-bit: -1 -> 0xFFFFFFFF. PowerShell tu choi gia tri > Int32.MaxValue,
    # nen ep ve [int] chu khong ep ve [uint32].
    $v = [int]$value
    if ($null -eq (Get-Item $path).GetValue($name)) {
        New-ItemProperty -Path $path -Name $name -Value $v -PropertyType DWord -Force | Out-Null
    } else {
        Set-ItemProperty -Path $path -Name $name -Value $v -Type DWord -Force
    }
}

try {
New-Item -ItemType Directory -Force -Path $engineModsDir, $modsSourceDir | Out-Null

# xoa DLL cu cua cung mod id
Get-ChildItem $engineModsDir -Filter "$Id`_*.dll" -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item $_.FullName -Force }

Copy-Item (Join-Path $workDir $newDllName) (Join-Path $engineModsDir $newDllName) -Force
Copy-Item $srcPath (Join-Path $modsSourceDir "$Id.wh.cpp") -Force
Write-Ok "DLL : $newDllName"
Write-Ok "src : $modsSourceDir\$Id.wh.cpp"

# --------------------------------------------------------------- 4. registry
Write-Step 4 "Ghi cau hinh (HKLM)"
New-Item -Path $regKey -Force | Out-Null

Set-RegString $regKey "LibraryFileName" $newDllName
Set-RegDword  $regKey "Disabled" 0
Set-RegDword  $regKey "LoggingEnabled" 0
Set-RegDword  $regKey "DebugLoggingEnabled" 0
Set-RegString $regKey "Include" ($includes -join '|')
Set-RegString $regKey "Exclude" ""
Set-RegString $regKey "Architecture" $arch
Set-RegString $regKey "Version" $Version
Set-RegDword  $regKey "SettingsChangeTime" ([int][double]::Parse((Get-Date -UFormat %s)))

# --- Settings: chi bat phan Start menu, tat taskbar / start button
$settingsKey = Join-Path $regKey "Settings"
New-Item -Path $settingsKey -Force | Out-Null

Set-RegDword  $settingsKey "loop" 1
Set-RegDword  $settingsKey "injectTaskbar" 0
Set-RegDword  $settingsKey "injectStartButton" 0
Set-RegDword  $settingsKey "injectStartMenu" 1
Set-RegDword  $settingsKey "TaskbarHeight" 0
Set-RegString $settingsKey "taskbarVideoUrl" ""
Set-RegString $settingsKey "startButtonVideoUrl" ""
Set-RegDword  $settingsKey "taskbarRate" 100
Set-RegDword  $settingsKey "taskbarOpacity" 100
Set-RegDword  $settingsKey "taskbarZIndex" 1
Set-RegDword  $settingsKey "taskbarCornerRadius" 0
Set-RegDword  $settingsKey "startButtonRate" 100
Set-RegDword  $settingsKey "startButtonOpacity" 100
Set-RegDword  $settingsKey "startButtonZIndex" 1
Set-RegDword  $settingsKey "startButtonCornerRadius" 0
Set-RegDword  $settingsKey "startMenuRate" $Rate
Set-RegDword  $settingsKey "startMenuOpacity" $Opacity
Set-RegDword  $settingsKey "startMenuZIndex" $ZIndex
Set-RegDword  $settingsKey "startMenuCornerRadius" $CornerRadius

if ($VideoPath) {
    Set-RegString $settingsKey "startMenuVideoUrl" $VideoPath
    Write-Ok "startMenuVideoUrl = $VideoPath"
}
else {
    Write-Warn2 "khong truyen -VideoPath, giu nguyen URL dang co (neu co)"
}
Write-Ok "zIndex=$ZIndex  opacity=$Opacity  rate=$Rate  cornerRadius=$CornerRadius"

}
finally {
    # ------------------------------------------------- 5. khoi dong lai
    # du cai dat thanh cong hay loi, Windhawk PHAI duoc mo lai
    Write-Step 5 "Khoi dong lai"
    if (-not (Get-Process -Name windhawk -ErrorAction SilentlyContinue)) {
        Start-Process $windhawkExe -ArgumentList "-tray-only"
        Start-Sleep -Seconds 2
        Write-Ok "da mo lai Windhawk (khay he thong)"
    }

    if (-not $NoRestartStartMenu) {
        $sme = Get-Process -Name "StartMenuExperienceHost" -ErrorAction SilentlyContinue
        if ($sme) {
            Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue
            Write-Ok "da restart StartMenuExperienceHost (Windows tu mo lai khi bam Start)"
        } else {
            Write-Ok "StartMenuExperienceHost chua chay - bam phim Windows mot lan la mod se vao"
        }
    }
}

Write-Host ""
Write-Host "XONG. Bam phim Windows de xem ket qua." -ForegroundColor Green
Write-Host "Khong thay gi? Mo Windhawk -> Mods -> XAML-Video-Injector -> xem tab Log/Status." -ForegroundColor DarkGray
