# 03 编译：cmake 配置 + ninja install
# SPDX-License-Identifier: GPL-3.0-or-later
#
# 用法：
#   .\03-build.ps1 -Root "C:\krita-dev"
#   .\03-build.ps1 -Root "C:\krita-dev" -Jobs 12 -PythonRoot "C:\tools\Python-3.13"
#
# 首次 40~120 分钟。配置完成后 CMake 日志里能直接看到 Python / SIP / PyQt6 三个探测结果，
# 任何一个缺失都意味着 PyKrita 不会被编进去（脚本末尾会标红）。

[CmdletBinding()]
param(
    [string]$Root = 'C:\krita-dev',
    [string]$BuildDir = (Join-Path $Root 'b_krita'),
    [string]$InstallDir = (Join-Path $Root '_install'),
    [int]$Jobs = 8,
    [string]$Config = 'RelWithDebInfo',
    [string]$PythonRoot = '',
    [switch]$WithTests,
    [switch]$Clean
)

. "$PSScriptRoot\lib\common.ps1"

$ErrorActionPreference = 'Stop'

$kritaDir = Join-Path $Root 'krita'
Assert-Dir $kritaDir 'Krita 源码'
Assert-File (Join-Path $Root 'env.bat') 'env.bat（先跑 01-bootstrap-deps.ps1）'

if ($Clean -and (Test-Path -LiteralPath $BuildDir)) {
    Write-Warn "删除旧构建目录：$BuildDir"
    Remove-Item -LiteralPath $BuildDir -Recurse -Force
}
if (-not (Test-Path -LiteralPath $BuildDir)) {
    New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# cmake 更吃正斜杠，统一转换
$srcArg = $kritaDir.Replace('\', '/')
$installArg = $InstallDir.Replace('\', '/')
$buildArg = $BuildDir.Replace('\', '/')

$cmakeArgs = @(
    "-DCMAKE_BUILD_TYPE=$Config"
    "-DCMAKE_INSTALL_PREFIX=$installArg"
    '-DBUILD_WITH_QT6=ON'
    '-DALLOW_UNSTABLE=QT6'
    '-DKRITA_ENABLE_PCH=OFF'
    '-DHIDE_SAFE_ASSERTS=OFF'
    '-DKRITA_USE_SURFACE_COLOR_MANAGEMENT_API=OFF'
)
if (-not $WithTests) { $cmakeArgs += '-DBUILD_TESTING=OFF' } else { $cmakeArgs += '-DBUILD_TESTING=ON' }

# Windows 上 runner 里常另有 C:/mingw64 的 GNU 工具链，必须在配置阶段就把编译器钉死到 llvm-mingw
$llvmBin = $env:LLVM_MINGW
if ($llvmBin -and (Test-Path (Join-Path $llvmBin 'bin\clang++.exe'))) {
    $cc  = (Join-Path $llvmBin 'bin\clang.exe').Replace('\', '/')
    $cxx = (Join-Path $llvmBin 'bin\clang++.exe').Replace('\', '/')
    $rc  = (Join-Path $llvmBin 'bin\windres.exe').Replace('\', '/')
    $cmakeArgs += "-DCMAKE_C_COMPILER=$cc"
    $cmakeArgs += "-DCMAKE_CXX_COMPILER=$cxx"
    if (Test-Path (Join-Path $llvmBin 'bin\windres.exe')) { $cmakeArgs += "-DCMAKE_RC_COMPILER=$rc" }
}
if ($PythonRoot -and $PythonRoot.Length -gt 0) {
    $cmakeArgs += "-DPython_ROOT_DIR=$($PythonRoot.Replace('\', '/'))"
}

$configureLine = 'cmake "' + $srcArg + '" -G Ninja ' + (($cmakeArgs | ForEach-Object { '"' + $_ + '"' }) -join ' ')
$buildLine = "ninja -j$Jobs install"

Write-Step '构建命令'
Write-Host "  $configureLine" -ForegroundColor DarkGray
Write-Host "  $buildLine" -ForegroundColor DarkGray

$lines = @(
    "cd /d `"$($BuildDir)`""
    $configureLine
    'if errorlevel 1 exit /b 31'
    $buildLine
    'if errorlevel 1 exit /b 32'
)

Write-Step '编译（输出同时写入 build.log）'
$log = Join-Path $Root 'build.log'
$rc = [int](Invoke-InKritaEnv -Root $Root -Lines $lines -LogPath $log -BatName 'reverie-build.bat')
Write-Host "  exit code: $rc" -ForegroundColor DarkGray

Write-Step '配置探测结果'
$probePatterns = [ordered]@{
    'Python (Interpreter)' = 'Found Python:.*version'
    'Python (Development)' = 'Found Python.*Development'
    'SIP'                  = 'Found SIP'
    'PyQt6'                = 'Found PyQt6'
}
$missing = @()
foreach ($k in $probePatterns.Keys) {
    $hit = Select-String -Path $log -Pattern $probePatterns[$k] -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { Write-Ok ("{0}: {1}" -f $k, $hit.Line.Trim()) }
    else { Write-Warn ("{0}: 日志里没有探测记录" -f $k); $missing += $k }
}

if ($rc -ne 0) {
    Set-Content -LiteralPath (Join-Path $Root 'build-rc.txt') -Value ("exit={0}  {1}" -f $rc, (Get-Date -Format o)) -Encoding ASCII
    Write-Err "构建失败（exit $rc），完整日志：$log"
    Write-Host '  常见原因：' -ForegroundColor DarkGray
    Write-Host '    - PATH 混入其它编译器/Python，或存在 PYTHONHOME/PYTHONPATH' -ForegroundColor DarkGray
    Write-Host '    - 没先 call env.bat（本脚本已自动处理，手工构建时要先跑 env.bat）' -ForegroundColor DarkGray
    Write-Host '    - 依赖不全：重跑 01-bootstrap-deps.ps1' -ForegroundColor DarkGray
    exit 3
}

Write-Step '产物检查'
$exe = Join-Path $InstallDir 'bin\krita.exe'
if (Test-Path -LiteralPath $exe) { Write-Ok "krita.exe: $exe" } else { Write-Err '未生成 bin\krita.exe'; exit 4 }

$pykritaDll = @(Get-ChildItem -Path (Join-Path $InstallDir 'lib') -Recurse -Filter 'kritapykrita*.dll' -File -ErrorAction SilentlyContinue)
if ($pykritaDll.Count -gt 0) { $pykritaDll | ForEach-Object { Write-Ok ("PyKrita 插件: " + $_.FullName) } }
else { Write-Err '没有生成 kritapykrita.dll —— PyKrita 没被编进去，见 docs/PYKRITA-RESTORE.md §1' }

$pyLibs = Join-Path $InstallDir 'lib\krita-python-libs\krita\__init__.py'
if (Test-Path -LiteralPath $pyLibs) { Write-Ok "krita Python 包: $pyLibs" } else { Write-Err '缺少 lib\krita-python-libs\krita —— SIP 绑定没装出来' }

$pluginDesktops = @(Get-ChildItem -Path (Join-Path $InstallDir 'share\krita\pykrita') -Filter '*.desktop' -File -ErrorAction SilentlyContinue)
if ($pluginDesktops.Count -gt 0) { Write-Ok ("内置 Python 插件 {0} 个" -f $pluginDesktops.Count) } else { Write-Err 'share\krita\pykrita 下没有插件描述文件' }

if ($missing.Count -gt 0) {
    Write-Warn '有探测项缺失，PyKrita 可能不完整；确认后在 Windows 上仍需按 §5 排错表处理'
}

Write-Host ''
Write-Ok '下一步：.\04-stage-portable.ps1'
