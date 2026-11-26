# 公共函数：日志、路径校验、cmd 环境调用、kritarc 写入
# SPDX-License-Identifier: GPL-3.0-or-later

Set-StrictMode -Version Latest

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "== $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "  [OK]   $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Write-Err([string]$Message) {
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

function Assert-Dir([string]$Path, [string]$What) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Err "$What 不存在: $Path"
        throw "missing directory: $Path"
    }
}

function Assert-File([string]$Path, [string]$What) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Err "$What 不存在: $Path"
        throw "missing file: $Path"
    }
}

function Test-Exe([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-KritaSource([string]$Root) {
    return (Join-Path $Root 'krita')
}

function Get-EnvBat([string]$Root) {
    return (Join-Path $Root 'env.bat')
}

# 在 Krita 的构建环境里执行一串命令。
# PowerShell 直接调用 .bat 不会保留它 set 的环境变量，所以统一落成一个临时 bat 再交给 cmd。
function Invoke-InKritaEnv {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Lines,
        [string]$LogPath = '',
        [string]$BatName = 'reverie-task.bat'
    )

    $envBat = Get-EnvBat $Root
    Assert-File $envBat 'Krita 构建环境 env.bat（先跑 01-bootstrap-deps.ps1）'

    $batPath = Join-Path $Root $BatName
    $content = @(
        '@echo off',
        'setlocal',
        "call `"$envBat`"",
        'if errorlevel 1 exit /b 21'
    ) + $Lines + @('exit /b 0')
    # 只用 ASCII 写 bat，避免 cmd 对 UTF-8 无 BOM 的解析差异
    Set-Content -LiteralPath $batPath -Value $content -Encoding ASCII

    Write-Host "  > cmd /c $batPath" -ForegroundColor DarkGray
    # 注意：Tee-Object 会把内容继续往管道外送，若不清空，函数返回值就会变成整份日志数组，
    # 调用方拿到的 $rc 也就不再是退出码（Krita 全量编译时这会把成功误判成失败）。
    if ($LogPath -and $LogPath.Length -gt 0) {
        & cmd /c "`"$batPath`"" 2>&1 | Tee-Object -FilePath $LogPath | Out-Null
    }
    else {
        & cmd /c "`"$batPath`"" 2>&1 | Out-Null
    }
    return [int]$LASTEXITCODE
}

# 取某个盘符的剩余空间（GB）
function Get-FreeGB([string]$Path) {
    $qualifier = Split-Path -Qualifier $Path
    $drive = $qualifier.TrimEnd('\')
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive'" -ErrorAction SilentlyContinue
    if ($null -eq $disk) { return -1 }
    return [math]::Round($disk.FreeSpace / 1GB, 1)
}

function Get-KritaRcPath {
    $appData = [Environment]::GetFolderPath('ApplicationData')
    return (Join-Path $appData 'krita\kritarc')
}

# 在 kritarc 的 [python] 组里写 enable_<module>=true（Krita 的插件启用状态就存在这里）
function Enable-KritaPythonPlugin([string]$ModuleName) {
    $rc = Get-KritaRcPath
    $dir = Split-Path -Parent $rc
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $lines = @()
    if (Test-Path -LiteralPath $rc) {
        $lines = @(Get-Content -LiteralPath $rc)
    }

    $key = "enable_$ModuleName=true"
    $sectionStart = -1
    $sectionEnd = $lines.Count
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[python\]\s*$') {
            $sectionStart = $i
            continue
        }
        if ($sectionStart -ge 0 -and $lines[$i] -match '^\s*\[') {
            $sectionEnd = $i
            break
        }
    }

    if ($sectionStart -lt 0) {
        $lines += '[python]'
        $lines += $key
    }
    else {
        $replaced = $false
        for ($i = $sectionStart + 1; $i -lt $sectionEnd; $i++) {
            if ($lines[$i] -match ("^\s*enable_" + [regex]::Escape($ModuleName) + "\s*=")) {
                $lines[$i] = $key
                $replaced = $true
                break
            }
        }
        if (-not $replaced) {
            $insertAt = $sectionEnd
            $head = @()
            $tail = @()
            if ($insertAt -gt 0) { $head = $lines[0..($insertAt - 1)] }
            if ($insertAt -lt $lines.Count) { $tail = $lines[$insertAt..($lines.Count - 1)] }
            $lines = @($head) + @($key) + @($tail)
        }
    }

    # 用无 BOM 的 UTF-8 写回：KConfig 对 BOM 敏感，Windows PowerShell 5.1 的 -Encoding UTF8 会带 BOM
    [System.IO.File]::WriteAllText($rc, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  已写入 $rc : [python] $key" -ForegroundColor DarkGray
}

function Copy-Tree([string]$From, [string]$To) {
    Assert-Dir $From "源目录"
    New-Item -ItemType Directory -Path $To -Force | Out-Null
    Copy-Item -LiteralPath $From -Destination $To -Recurse -Force
}
