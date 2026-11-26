# 02 打补丁：把 ReveriePaint 的桌面端补丁按依赖顺序应用到 Krita 源码
# SPDX-License-Identifier: GPL-3.0-or-later
#
# 用法：
#   .\02-apply-patches.ps1 -Root "C:\krita-dev"
#   .\02-apply-patches.ps1 -Root "C:\krita-dev" -IncludeExperimental    # 额外打移动端性能实验补丁
#
# 规则：每条补丁成功后立即 commit，失败则 reset 回上一条，绝不留下“半条补丁”。

[CmdletBinding()]
param(
    [string]$Root = 'C:\krita-dev',
    [string]$PatchDir = (Join-Path $PSScriptRoot '..\patches'),
    [switch]$IncludeExperimental,
    [switch]$Force
)

. "$PSScriptRoot\lib\common.ps1"

$ErrorActionPreference = 'Stop'

$kritaDir = Join-Path $Root 'krita'
Assert-Dir (Join-Path $kritaDir '.git') 'Krita 源码（先跑 01-bootstrap-deps.ps1）'
Assert-Dir $PatchDir '补丁目录'

Write-Step '源码状态检查'
$dirty = & git -C $kritaDir status --porcelain
if ($dirty) {
    if (-not $Force) {
        Write-Err '工作区不干净，为避免叠加出不可复现的树，先处理以下文件（或加 -Force 强行继续）：'
        $dirty | ForEach-Object { Write-Host "    $_" }
        exit 2
    }
    Write-Warn '工作区不干净，-Force 继续'
}
$head = (& git -C $kritaDir rev-parse --short HEAD)
Write-Ok "HEAD = $head"

# 提交身份：只在仓库内设置，不碰全局配置
$mail = & git -C $kritaDir config user.email
if (-not $mail) {
    & git -C $kritaDir config user.email 'port@reveriepaint.local'
    & git -C $kritaDir config user.name 'ReveriePaint Port'
    Write-Warn '已为本地仓库设置临时提交身份（不修改全局 git 配置）'
}

# 顺序不是随意的：0004/0016 依赖 0002；0014 依赖 0013；0005b 依赖 0005
$plan = @(
    @{ Id = '0002'; Exclude = @(); Desc = '圆头笔刷 KisMarkerPainter 修复' }
    @{ Id = '0003'; Exclude = @(); Desc = '换页 Swap qFatal 修复' }
    @{ Id = '0004'; Exclude = @(); Desc = '圆头笔刷边缘 COMPOSITE_OVER' }
    @{ Id = '0005'; Exclude = @('libs/psd/psd_layer_section.cpp', 'plugins/impex/psd/psd_loader.cpp'); Desc = '剪切蒙版（PSD 两文件另见 0005b）' }
    @{ Id = '0005b'; Exclude = @(); Desc = 'PSD 剪切蒙版读写重基（本工程新增）' }
    @{ Id = '0008'; Exclude = @(); Desc = 'kis_lockless_stack Qt 6.6 构建修复' }
    @{ Id = '0011'; Exclude = @('REVERIE-PATCHES.md'); Desc = 'Memento SIGABRT 修复' }
    @{ Id = '0012'; Exclude = @(); Desc = '事务中止修复' }
    @{ Id = '0015'; Exclude = @(); Desc = 'Sketch 笔刷查找表 O(N²)→O(1)' }
    @{ Id = '0017'; Exclude = @(); Desc = '网格笔刷 HSV 修复' }
)
if ($IncludeExperimental) {
    $plan += @{ Id = '0013'; Exclude = @(); Desc = 'fillPainterPath 块合并 + 60fps 节流（实验）' }
    $plan += @{ Id = '0014'; Exclude = @(); Desc = '三角划分 25fps 拆批（实验）' }
    $plan += @{ Id = '0016'; Exclude = @(); Desc = 'Marker 笔刷缓存（实验）' }
}

function Resolve-Patch([string]$Id) {
    $found = @(Get-ChildItem -Path $PatchDir -Recurse -Filter "$Id-*.patch" -File)
    if ($found.Count -eq 0) {
        $found = @(Get-ChildItem -Path $PatchDir -Filter "$Id-*.patch" -File)
    }
    if ($found.Count -eq 0) { return $null }
    return $found[0].FullName
}

Write-Step '按顺序应用'
$applied = @()
$failed = $null
foreach ($item in $plan) {
    $id = $item.Id
    $patch = Resolve-Patch $id
    if (-not $patch) {
        Write-Err "找不到补丁 $id-*.patch（$PatchDir）"
        $failed = $id
        break
    }

    $gitArgs = @('-C', $kritaDir, 'apply', '--whitespace=nowarn')
    foreach ($ex in $item.Exclude) { $gitArgs += "--exclude=$ex" }
    $gitArgs += $patch
    $gitArgs3w = @('-C', $kritaDir, 'apply', '--3way', '--whitespace=nowarn')
    foreach ($ex in $item.Exclude) { $gitArgs3w += "--exclude=$ex" }
    $gitArgs3w += $patch

    Write-Host ("  → {0}  {1}" -f $id, $item.Desc)
    $output = & git @gitArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        # 浅克隆 + Windows CRLF 工作树时 --3way 会因为找不到前像 blob 而失败，退回三路合并兜底
        $output = & git @gitArgs3w 2>&1
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Err "$id 应用失败，回滚到上一条补丁"
        $output | Select-Object -Last 8 | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
        & git -C $kritaDir reset --hard -q
        & git -C $kritaDir clean -fdq
        $failed = $id
        break
    }

    & git -C $kritaDir add -A
    & git -C $kritaDir commit -q -m "reverie-port: apply $id ($($item.Desc))"
    if ($LASTEXITCODE -ne 0) {
        Write-Err "$id 已应用但提交失败"
        $failed = $id
        break
    }
    Write-Ok "$id 已应用并提交"
    $applied += $id
}

Write-Step '结果'
if ($failed) {
    Write-Err "补丁链在 $failed 处中断，当前源码树已回到上一条补丁的状态"
    Write-Host ("  已成功：{0}" -f ($(if ($applied.Count -gt 0) { $applied -join ', ' } else { '无' })))
    Write-Host '  排查方式：git -C <krita> status；单条手动试：git apply <patch>'
    exit 3
}

Write-Ok ("{0} 条补丁全部应用：{1}" -f $applied.Count, ($applied -join ', '))
Write-Host ''
Write-Host '  提交历史：' -ForegroundColor DarkGray
& git -C $kritaDir log --oneline -n ($applied.Count + 1) | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
Write-Host ''
Write-Ok '下一步：.\03-build.ps1'
