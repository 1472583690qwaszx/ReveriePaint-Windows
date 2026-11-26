# 04 组包：调用 Krita 官方 Windows 打包脚本生成便携目录，并注入 ReveriePaint 的插件与资产
# SPDX-License-Identifier: GPL-3.0-or-later
#
# 用法：
#   .\04-stage-portable.ps1 -Root "C:\krita-dev"
#
# 产物：<Root>\dist\ReveriePaint\（可直接压缩分发），以及同目录同名 zip。

[CmdletBinding()]
param(
    [string]$Root = 'C:\krita-dev',
    [string]$DistDir = '',
    [string]$PackageName = 'ReveriePaint',
    [string]$LlvmMingw = 'C:\deps\llvm-mingw-20251118-ucrt-x86_64',
    [string]$AssetSource = '',
    [switch]$SkipPackaging
)

. "$PSScriptRoot\lib\common.ps1"

$ErrorActionPreference = 'Stop'

if (-not $DistDir -or $DistDir.Length -eq 0) { $DistDir = Join-Path $Root 'dist' }
$installDir = Join-Path $Root '_install'
$kritaDir = Join-Path $Root 'krita'

Assert-Dir $kritaDir 'Krita 源码'
Assert-Dir $installDir '_install（先跑 03-build.ps1）'
Assert-File (Join-Path $installDir 'bin\krita.exe') 'krita.exe'

# windows/ 一般放在仓库根；也兼容"仓库还在别处"的情况
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
function Resolve-AssetSource {
    param([string]$Explicit)
    if ($Explicit -and (Test-Path -LiteralPath $Explicit)) { return (Resolve-Path -LiteralPath $Explicit).Path }
    $candidates = @(
        (Join-Path $repoRoot 'app\src\main\assets')
        (Join-Path $repoRoot 'work\ReveriePaint-main\app\src\main\assets')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $c 'paintoppresets')) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return $null
}

$assets = Resolve-AssetSource $AssetSource
if (-not $assets) {
    Write-Err '找不到 app\src\main\assets（含 paintoppresets/brushes/patterns）。'
    Write-Host '  把 windows\ 放到 ReveriePaint 仓库根再跑，或用 -AssetSource 指定 assets 目录。' -ForegroundColor DarkGray
    exit 2
}
Write-Ok "资产源: $assets"

if (-not (Test-Path -LiteralPath $DistDir)) { New-Item -ItemType Directory -Path $DistDir -Force | Out-Null }
$pkgRoot = Join-Path $DistDir $PackageName

Write-Step '官方打包（合并 Python 运行时 / PyQt6 / krita-python-libs）'
if ($SkipPackaging -and (Test-Path -LiteralPath $pkgRoot)) {
    Write-Warn '-SkipPackaging：复用已有目录'
}
else {
    if (Test-Path -LiteralPath $pkgRoot) {
        Write-Warn "删除旧包目录：$pkgRoot"
        Remove-Item -LiteralPath $pkgRoot -Recurse -Force
    }
    $py = Join-Path $Root 'PythonEnv\Scripts\python.exe'
    Assert-File $py 'PythonEnv（先跑 01-bootstrap-deps.ps1）'
    $packScript = Join-Path $kritaDir 'packaging\windows\package-complete.py'
    Assert-File $packScript 'Krita 官方打包脚本'

    $env:MINGW_BIN_DIR = (Join-Path $LlvmMingw 'bin')
    # Krita 官方打包脚本在 Release 构建上仍会尝试用 GNU 风格的 objcopy/strip
    # 分离调试符号；llvm-mingw 里只有 llvm-objcopy/llvm-strip，找不到就会直接崩。
    # Release 构建本来没有 .debug 段，这里按官方 CI 的开关跳过这一步。
    $env:KRITACI_SKIP_SPLIT_DEBUG = '1'
    if (-not (Test-Exe '7z')) { Write-Warn 'PATH 里没有 7z.exe：打包脚本会尝试 Program Files\7-Zip' }

    $consoleLog = Join-Path $DistDir 'stage-console.log'
    Push-Location $DistDir
    try {
        & $py -u $packScript --no-interactive --package-name $PackageName `
            --src-dir $kritaDir --deps-install-dir $installDir --krita-install-dir $installDir `
            2>&1 | Tee-Object -FilePath $consoleLog | Out-Null
        $rc = [int]$LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    if (Test-Path $consoleLog) { Get-Content $consoleLog -Tail 40 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray } }
    if ($rc -ne 0) { Write-Err "官方打包脚本失败（exit $rc），日志：$DistDir\package_complete.log"; exit 3 }
}

Assert-Dir $pkgRoot '打包产物目录'
Write-Ok "便携目录: $pkgRoot"

Write-Step '注入 ReveriePaint Python 插件'
$pykritaSrc = Join-Path $PSScriptRoot '..\pykrita'
$pykritaDst = Join-Path $pkgRoot 'share\krita\pykrita'
Assert-Dir $pykritaSrc 'windows\pykrita'
New-Item -ItemType Directory -Path $pykritaDst -Force | Out-Null
Get-ChildItem -LiteralPath $pykritaSrc -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $pykritaDst -Recurse -Force
    Write-Ok $_.Name
}

Write-Step '注入笔刷 / 笔尖 / 图案'
$assetDst = Join-Path $pkgRoot 'share\reveriepaint\assets'
New-Item -ItemType Directory -Path $assetDst -Force | Out-Null
foreach ($sub in @('paintoppresets', 'brushes', 'patterns')) {
    $srcDir = Join-Path $assets $sub
    if (-not (Test-Path -LiteralPath $srcDir)) { Write-Warn "缺少资产目录 $sub"; continue }
    $dstDir = Join-Path $assetDst $sub
    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    $count = 0
    Get-ChildItem -LiteralPath $srcDir -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $dstDir -Force
        $count++
    }
    Write-Ok ("{0}: {1} 个文件" -f $sub, $count)
}

Write-Step 'GPL 合规材料'
$legalDst = Join-Path $pkgRoot 'share\reveriepaint'
New-Item -ItemType Directory -Path $legalDst -Force | Out-Null
$license = Join-Path $repoRoot 'LICENSE'
if (-not (Test-Path -LiteralPath $license)) { $license = Join-Path $repoRoot 'work\ReveriePaint-main\LICENSE' }
if (Test-Path -LiteralPath $license) {
    Copy-Item -LiteralPath $license -Destination (Join-Path $legalDst 'LICENSE-GPL-3.0.txt') -Force
    Write-Ok 'LICENSE 已附带'
}
else { Write-Warn '找不到 LICENSE，请手工补 GPL-3.0 文本' }

$patchSrc = Join-Path $PSScriptRoot '..\patches'
if (Test-Path -LiteralPath $patchSrc) {
    Copy-Item -LiteralPath $patchSrc -Destination (Join-Path $legalDst 'patches') -Recurse -Force
    Write-Ok 'Krita 补丁集已附带（含 0005b 重基补丁）'
}

$notice = @(
    'ReveriePaint for Windows'
    ''
    '本发行版基于 Krita 6（GPL-3.0-or-later）构建，附带 ReveriePaint 的补丁与笔刷资产。'
    '源码与补丁见 share\reveriepaint\patches 与项目仓库。'
    ''
    'Python 插件：share\krita\pykrita 下含 ReveriePaint 自带插件；'
    '用户插件目录：%APPDATA%\krita\pykrita'
) -join "`r`n"
Set-Content -LiteralPath (Join-Path $pkgRoot 'README-PORT.txt') -Value $notice -Encoding UTF8

Write-Step '启动包装'
$launcher = @(
    '@echo off'
    'setlocal'
    'set "REVERIE_ROOT=%~dp0"'
    'set "REVERIE_ASSET_DIR=%REVERIE_ROOT%share\reveriepaint\assets"'
    'start "" "%REVERIE_ROOT%bin\krita.exe" %*'
) -join "`r`n"
Set-Content -LiteralPath (Join-Path $pkgRoot 'ReveriePaint.cmd') -Value $launcher -Encoding ASCII
Write-Ok 'ReveriePaint.cmd'

Write-Step '体积'
$size = (Get-ChildItem -LiteralPath $pkgRoot -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Ok ("{0:N1} MB" -f ($size / 1MB))

Write-Host ''
Write-Ok '下一步：.\05-verify.ps1（会启动一次程序，验证 PyKrita 真的加载）'
