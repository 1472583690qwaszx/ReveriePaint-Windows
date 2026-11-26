# 01 引导：克隆 Krita 源码 + 预编译依赖 + 生成 env.bat
# SPDX-License-Identifier: GPL-3.0-or-later
#
# 用法：
#   .\01-bootstrap-deps.ps1 -Root "C:\krita-dev" `
#       -LlvmMingw "C:\deps\llvm-mingw-20251118-ucrt-x86_64" -NinjaDir "C:\deps\Ninja"
#
# 该步骤会下载数百 MB 依赖，首次约 20~60 分钟，取决于网速。

[CmdletBinding()]
param(
    [string]$Root = 'C:\krita-dev',
    [string]$KritaTag = 'v6.0.4',
    [string]$LlvmMingw = 'C:\deps\llvm-mingw-20251118-ucrt-x86_64',
    [string]$NinjaDir = 'C:\deps\Ninja',
    [string]$PythonExe = 'python',
    [string]$DepsBranch = 'master',
    [string]$KritaRepo = 'https://invent.kde.org/graphics/krita.git',
    [string]$DepsRepo = 'https://invent.kde.org/packaging/krita-deps-management.git',
    [string]$CiRepo = 'https://invent.kde.org/packaging/krita-ci-utilities.git'
)

. "$PSScriptRoot\lib\common.ps1"

$ErrorActionPreference = 'Stop'

Write-Step '准备工作目录'
if (-not (Test-Path -LiteralPath $Root)) {
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
}
Write-Ok $Root

Assert-Dir (Join-Path $LlvmMingw 'bin') 'llvm-mingw bin'
Assert-Dir (Join-Path $LlvmMingw 'x86_64-w64-mingw32\bin') 'llvm-mingw 目标 bin'

Write-Step "Krita 源码（$KritaTag）"
$kritaDir = Join-Path $Root 'krita'
if (Test-Path -LiteralPath (Join-Path $kritaDir '.git')) {
    Write-Warn "已存在源码目录，跳过克隆：$kritaDir"
    Write-Warn '如需换版本：git -C 该目录 fetch --depth 1 origin <tag> && git checkout FETCH_HEAD'
}
else {
    & git clone --depth 1 --branch $KritaTag $KritaRepo $kritaDir
    if ($LASTEXITCODE -ne 0) { Write-Err '克隆 Krita 失败'; exit 2 }
    Write-Ok "已克隆到 $kritaDir"
}

Write-Step '依赖管理脚本'
$depsDir = Join-Path $Root 'krita-deps-management'
if (-not (Test-Path -LiteralPath $depsDir)) {
    & git clone --depth 1 --branch $DepsBranch $DepsRepo $depsDir
    if ($LASTEXITCODE -ne 0) { Write-Err '克隆 krita-deps-management 失败'; exit 3 }
}
else { Write-Warn "已存在，跳过：$depsDir" }

$ciDir = Join-Path $depsDir 'ci-utilities'
if (-not (Test-Path -LiteralPath $ciDir)) {
    & git clone --depth 1 $CiRepo $ciDir
    if ($LASTEXITCODE -ne 0) { Write-Err '克隆 ci-utilities 失败'; exit 4 }
}
else { Write-Warn "已存在，跳过：$ciDir" }

Write-Step 'Python 虚拟环境（只用于跑构建脚本，不是 Krita 内嵌的 Python）'
$venvDir = Join-Path $Root 'PythonEnv'
$venvPy = Join-Path $venvDir 'Scripts\python.exe'
if (-not (Test-Path -LiteralPath $venvPy)) {
    & $PythonExe -m venv $venvDir --upgrade-deps
    if ($LASTEXITCODE -ne 0) { Write-Err '创建 venv 失败（需要 Python 3.13 x64 在 PATH 里）'; exit 5 }
}
else { Write-Warn "已存在，跳过创建：$venvDir" }

& $venvPy -m pip install --upgrade pip
$req1 = Join-Path $depsDir 'requirements.txt'
$req2 = Join-Path $ciDir 'requirements-windows.txt'
Assert-File $req1 'krita-deps-management/requirements.txt'
Assert-File $req2 'ci-utilities/requirements-windows.txt'
& $venvPy -m pip install -r $req1
if ($LASTEXITCODE -ne 0) { Write-Err '安装 requirements.txt 失败'; exit 6 }
& $venvPy -m pip install -r $req2
if ($LASTEXITCODE -ne 0) { Write-Err '安装 requirements-windows.txt 失败'; exit 7 }
Write-Ok '构建脚本依赖就绪'

Write-Step '拉取预编译依赖并生成 env.bat（耗时最长的一步）'
$setupEnv = Join-Path $depsDir 'tools\setup-env.py'
Assert-File $setupEnv 'setup-env.py'
$envBat = Join-Path $Root 'env.bat'
if ((Test-Path -LiteralPath $envBat) -and (Test-Path -LiteralPath (Join-Path $Root '_install'))) {
    Write-Warn 'env.bat 与 _install 已存在，跳过依赖下载；如需重来请删掉它们'
}
else {
    Push-Location $Root
    try {
        & $venvPy $setupEnv --full-krita-env -v $venvDir -b $DepsBranch `
            -p (Join-Path $LlvmMingw 'bin') `
            -p (Join-Path $LlvmMingw 'x86_64-w64-mingw32\bin') `
            -p $NinjaDir
        $rc = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    if ($rc -ne 0) { Write-Err "setup-env.py 失败（exit $rc）"; exit 8 }
}

Write-Step '结果检查'
Assert-File $envBat '生成的 env.bat'
Write-Ok "env.bat: $envBat"
$installDir = Join-Path $Root '_install'
if (Test-Path -LiteralPath $installDir) { Write-Ok "_install: $installDir" } else { Write-Warn '_install 尚未生成（部分流程在构建时才写入）' }
$pythonDir = Join-Path $installDir 'python'
if (Test-Path -LiteralPath $pythonDir) { Write-Ok "内嵌 Python: $pythonDir" } else { Write-Warn '未找到 _install\python：打包阶段 PyKrita 会报 "Bundled Python not found"，请检查依赖是否完整' }

Write-Host ''
Write-Ok '下一步：.\02-apply-patches.ps1'
