# 05 校验：产物完整性 + PyKrita 真实加载探针
# SPDX-License-Identifier: GPL-3.0-or-later
#
# 用法：
#   .\05-verify.ps1 -Root "C:\krita-dev"
#   .\05-verify.ps1 -Root "C:\krita-dev" -NoLaunch     # 只做文件检查，不启动程序
#
# 原理：reverie_verify 探针插件被 PyKrita 加载后会写一个标记文件，
# 文件里带 Python 版本、PyQt 版本、krita 模块路径、资源目录。看到它 = Python 插件链路真的通了。

[CmdletBinding()]
param(
    [string]$Root = 'C:\krita-dev',
    [string]$DistDir = '',
    [string]$PackageName = 'ReveriePaint',
    [int]$TimeoutSec = 90,
    [switch]$NoLaunch
)

. "$PSScriptRoot\lib\common.ps1"

$ErrorActionPreference = 'Stop'

if (-not $DistDir -or $DistDir.Length -eq 0) { $DistDir = Join-Path $Root 'dist' }
$pkgRoot = Join-Path $DistDir $PackageName
Assert-Dir $pkgRoot '便携包目录（先跑 04-stage-portable.ps1）'

$problems = @()
function Check([string]$Label, [bool]$Ok, [string]$Detail) {
    if ($Ok) { Write-Ok ("{0}: {1}" -f $Label, $Detail) }
    else { Write-Err ("{0}: {1}" -f $Label, $Detail); $script:problems += $Label }
}

Write-Step '1. 基本产物'
Check 'bin\krita.exe' (Test-Path (Join-Path $pkgRoot 'bin\krita.exe')) (Join-Path $pkgRoot 'bin\krita.exe')

$dlls = @(Get-ChildItem -Path $pkgRoot -Recurse -Filter 'kritapykrita*.dll' -File -ErrorAction SilentlyContinue)
Check 'PyKrita 插件 DLL' ($dlls.Count -gt 0) ($(if ($dlls.Count -gt 0) { $dlls[0].FullName } else { '未找到' }))

$pyPkg = Join-Path $pkgRoot 'lib\krita-python-libs\krita\__init__.py'
Check 'krita Python 包' (Test-Path $pyPkg) $pyPkg

$pyQt = Join-Path $pkgRoot 'lib\site-packages\PyQt6\__init__.py'
Check 'PyQt6' (Test-Path $pyQt) $pyQt

$pyZip = @(Get-ChildItem -Path (Join-Path $pkgRoot 'python') -Filter 'python3*.zip' -File -ErrorAction SilentlyContinue)
Check '内嵌 Python 运行时' ($pyZip.Count -gt 0) ($(if ($pyZip.Count -gt 0) { $pyZip[0].FullName } else { 'python\ 下没有 python3xx.zip' }))

$desktops = @(Get-ChildItem -Path (Join-Path $pkgRoot 'share\krita\pykrita') -Filter '*.desktop' -File -ErrorAction SilentlyContinue)
Check 'Python 插件描述文件数量' ($desktops.Count -ge 10) ("{0} 个" -f $desktops.Count)

$ourPlugin = Join-Path $pkgRoot 'share\krita\pykrita\reveriepaint\__init__.py'
Check '随包插件 reveriepaint' (Test-Path $ourPlugin) $ourPlugin

Write-Step '2. 启用随包插件（写入 kritarc [python]）'
Enable-KritaPythonPlugin 'reveriepaint'
Enable-KritaPythonPlugin 'reverie_verify'

$probe = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'krita\reverie-pykrita-probe.txt'
if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe -Force }

if ($NoLaunch) {
    Write-Warn '-NoLaunch：跳过启动探针'
}
else {
    Write-Step ("3. 启动探针（最多等待 {0} 秒）" -f $TimeoutSec)
    $exe = Join-Path $pkgRoot 'bin\krita.exe'
    $proc = Start-Process -FilePath $exe -WorkingDirectory (Join-Path $pkgRoot 'bin') -PassThru
    Write-Host ("  已启动 pid={0}，等待插件写标记文件…" -f $proc.Id) -ForegroundColor DarkGray

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $probe)) {
        Start-Sleep -Seconds 2
        if ($proc.HasExited) { break }
    }

    if (-not $proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Seconds 3
        if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    }

    if (Test-Path -LiteralPath $probe) {
        Write-Ok 'PYKRITA_OK —— 探针插件已被加载'
        Write-Host ''
        Get-Content -LiteralPath $probe | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
        Write-Host ''
    }
    else {
        Write-Err 'PYKRITA_FAIL —— 插件没有被加载'
        $problems += 'pykrita-load'
        Write-Host '  排查顺序：' -ForegroundColor DarkGray
        Write-Host '    1) 设置 → 配置 Krita → Python 插件管理器：能看到 reverie_verify 吗？' -ForegroundColor DarkGray
        Write-Host '    2) 帮助 → 显示 Krita 日志：搜 "Loaded Python Plugins" 与 "Traceback"' -ForegroundColor DarkGray
        Write-Host '    3) 见 docs/PYKRITA-RESTORE.md §5 排错表' -ForegroundColor DarkGray
    }
}

Write-Step '结论'
if ($problems.Count -eq 0) {
    Write-Ok '全部通过：Windows 版 PyKrita 已可用'
    exit 0
}
Write-Err ("{0} 项未通过：{1}" -f $problems.Count, ($problems -join ', '))
exit 1
