# 00 环境体检：Windows 构建 ReveriePaint 所需工具链逐项核对
# SPDX-License-Identifier: GPL-3.0-or-later
#
# 用法：
#   .\00-check-prereqs.ps1 -LlvmMingw "C:\deps\llvm-mingw-20251118-ucrt-x86_64" -NinjaDir "C:\deps\Ninja"

[CmdletBinding()]
param(
    [string]$LlvmMingw = 'C:\deps\llvm-mingw-20251118-ucrt-x86_64',
    [string]$NinjaDir = 'C:\deps\Ninja',
    [string]$PythonExe = 'python',
    [string]$Root = 'C:\krita-dev',
    [int]$MinFreeGB = 120
)

. "$PSScriptRoot\lib\common.ps1"

$results = @()
function Add-Result([string]$Item, [bool]$Ok, [string]$Detail, [bool]$Required = $true) {
    $script:results += [PSCustomObject]@{ Item = $Item; Ok = $Ok; Required = $Required; Detail = $Detail }
}

Write-Step '系统'
$os = Get-CimInstance Win32_OperatingSystem
$is64 = [Environment]::Is64BitOperatingSystem
Add-Result 'Windows x64' ($os.Caption -match 'Windows' -and $is64) ("{0} / {1}" -f $os.Caption, $os.Version)

$freeGB = Get-FreeGB (Split-Path -Qualifier $Root)
Add-Result ("磁盘剩余 ≥ {0} GB" -f $MinFreeGB) ($freeGB -ge $MinFreeGB) ("{0} GB 可用（{1}）" -f $freeGB, (Split-Path -Qualifier $Root)) $false

Write-Step '构建工具'
$gitOk = Test-Exe 'git'
$gitVer = if ($gitOk) { (& git --version) } else { '未安装' }
Add-Result 'Git' $gitOk $gitVer

$cmakeOk = Test-Exe 'cmake'
$cmakeVer = '未安装'
$cmakeVersionOk = $false
if ($cmakeOk) {
    $line = (& cmake --version | Select-Object -First 1)
    if ($line -match 'cmake version (\d+)\.(\d+)\.(\d+)') {
        $cmakeVer = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
        $major = [int]$Matches[1]
        $minor = [int]$Matches[2]
        $cmakeVersionOk = ($major -eq 3 -and $minor -ge 31)
    }
    else {
        $cmakeVer = $line
    }
}
Add-Result 'CMake 3.31.x（4.x 上游不支持）' ($cmakeOk -and $cmakeVersionOk) $cmakeVer

$ninjaInPath = (Test-Exe 'ninja')
$ninjaInDir = (Test-Path -LiteralPath (Join-Path $NinjaDir 'ninja.exe'))
$ninjaVer = if ($ninjaInPath) { (& ninja --version) } elseif ($ninjaInDir) { (& (Join-Path $NinjaDir 'ninja.exe') --version) } else { '未找到' }
Add-Result 'Ninja（PATH 或 -NinjaDir）' ($ninjaInPath -or $ninjaInDir) $ninjaVer

Write-Step '编译器与 Python'
$clangxx = Join-Path $LlvmMingw 'bin\clang++.exe'
$toolchainOk = (Test-Path -LiteralPath $clangxx)
$toolchainVer = if ($toolchainOk) { (& $clangxx --version | Select-Object -First 1) } else { "未找到 $clangxx" }
Add-Result 'llvm-mingw (clang 21, UCRT)' $toolchainOk $toolchainVer

$tripPrefix = Join-Path $LlvmMingw 'x86_64-w64-mingw32'
Add-Result 'llvm-mingw 目标前缀目录' (Test-Path -LiteralPath $tripPrefix) $tripPrefix

$pyOk = $false
$pyDetail = '未找到'
if (Test-Exe $PythonExe) {
    $probe = & $PythonExe -c "import sys, struct; print('%d.%d|%d' % (sys.version_info[0], sys.version_info[1], struct.calcsize('P') * 8))" 2>$null
    if ($LASTEXITCODE -eq 0 -and $probe) {
        $parts = $probe.Split('|')
        $pyDetail = "Python $($parts[0]) / $($parts[1]) 位"
        $pyOk = ($parts[0] -eq '3.13' -and $parts[1] -eq '64')
    }
}
Add-Result 'Python 3.13 x64（Krita 6 口径）' $pyOk $pyDetail
Add-Result 'Python 未混入其它版本' (-not ($env:PYTHONHOME)) 'PYTHONHOME 为空' $false

Write-Step '可选'
Add-Result '7-Zip（打包用）' (Test-Exe '7z') '7z.exe' $false
Add-Result 'Inno Setup 6（做安装包用）' (Test-Exe 'iscc') 'iscc.exe' $false

Write-Host ''
foreach ($r in $results) {
    $tag = if ($r.Ok) { 'OK  ' } elseif ($r.Required) { 'FAIL' } else { 'WARN' }
    $color = if ($r.Ok) { 'Green' } elseif ($r.Required) { 'Red' } else { 'Yellow' }
    Write-Host ("[{0}] {1,-40} {2}" -f $tag, $r.Item, $r.Detail) -ForegroundColor $color
}

$failed = @($results | Where-Object { -not $_.Ok -and $_.Required })
Write-Host ''
if ($failed.Count -eq 0) {
    Write-Ok '环境检查通过，可以继续 01-bootstrap-deps.ps1'
    exit 0
}
Write-Err ("有 {0} 项必填条件不满足，先按提示装好再继续" -f $failed.Count)
exit 1
