# 一键：体检 → 依赖 → 补丁 → 编译 → 组包 → 安装包
# SPDX-License-Identifier: GPL-3.0-or-later
#
# 用法（在 Windows 上，PowerShell 里）：
#   .\build-all.ps1 -Root "C:\krita-dev" `
#       -LlvmMingw "C:\deps\llvm-mingw-20251118-ucrt-x86_64" -NinjaDir "C:\deps\Ninja"
#
# 产物：
#   C:\krita-dev\dist\ReveriePaint\        便携目录（可直接压包分发）
#   C:\krita-dev\dist\ReveriePaint.zip     便携压缩包
#   windows\out\ReveriePaint-*-setup.exe   Inno Setup 安装包（需装 Inno Setup 6）

[CmdletBinding()]
param(
    [string]$Root = 'C:\krita-dev',
    [string]$LlvmMingw = 'C:\deps\llvm-mingw-20251118-ucrt-x86_64',
    [string]$NinjaDir = 'C:\deps\Ninja',
    [string]$PythonExe = 'python',
    [int]$Jobs = 8,
    [switch]$IncludeExperimental,
    [switch]$SkipPrereq,
    [switch]$SkipInstaller
)

$ErrorActionPreference = 'Stop'
$scripts = $PSScriptRoot

function Step([string]$Name, [string]$Script, [string[]]$Args) {
    Write-Host ""
    Write-Host ("========== {0} ==========" -f $Name) -ForegroundColor Cyan
    $cmd = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $scripts $Script)) + $Args
    & powershell @cmd
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("[x] {0} 失败（exit {1}）" -f $Name, $LASTEXITCODE) -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

if (-not $SkipPrereq) {
    Step '00 环境体检' '00-check-prereqs.ps1' @('-LlvmMingw', $LlvmMingw, '-NinjaDir', $NinjaDir, '-PythonExe', $PythonExe, '-Root', $Root)
}

Step '01 源码与依赖' '01-bootstrap-deps.ps1' @('-Root', $Root, '-LlvmMingw', $LlvmMingw, '-NinjaDir', $NinjaDir, '-PythonExe', $PythonExe)

$patchArgs = @('-Root', $Root)
if ($IncludeExperimental) { $patchArgs += '-IncludeExperimental' }
Step '02 应用补丁' '02-apply-patches.ps1' $patchArgs

Step '03 编译安装' '03-build.ps1' @('-Root', $Root, '-Jobs', $Jobs)

Step '04 组装便携版' '04-stage-portable.ps1' @('-Root', $Root)

if (-not $SkipInstaller) {
    $iscc = Get-Command iscc.exe -ErrorAction SilentlyContinue
    if ($null -eq $iscc) {
        Write-Host ""
        Write-Host '[!] 没找到 iscc.exe（Inno Setup 6 未安装），跳过安装包。' -ForegroundColor Yellow
        Write-Host '    装好后单独跑：iscc windows\installer\reveriepaint.iss' -ForegroundColor Yellow
    }
    else {
        Write-Host ''
        Write-Host '========== 05 生成安装包 ==========' -ForegroundColor Cyan
        $iss = Join-Path $scripts '..\installer\reveriepaint.iss'
        $iss = (Resolve-Path $iss).Path
        & iscc.exe $iss
        if ($LASTEXITCODE -ne 0) {
            Write-Host ("[x] Inno Setup 编译失败（exit {0}）" -f $LASTEXITCODE) -ForegroundColor Red
            exit $LASTEXITCODE
        }
    }
}

Write-Host ""
Write-Host '[OK] 全部完成' -ForegroundColor Green
Write-Host "  便携目录: $(Join-Path $Root 'dist\ReveriePaint')"
Write-Host "  安装包:   windows\out\"
Write-Host '  建议接着跑：.\05-verify.ps1 -Root <Root>（会启动一次程序验证 PyKrita）'
