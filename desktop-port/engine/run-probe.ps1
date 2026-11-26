# Engine compile probe (syntax-only) for ReveriePaint v1.11.0 on Windows.
# 从 desktop-m1.yml 的 Engine compile probe 步骤抽出来的独立脚本：
# 这样调 include / flags 只需要改这个小文件，不用整份 workflow 重推。
# 退出码 0 = 全部 TU 无错误；1 = 有失败（日志已写进 logs/engine-probe.txt）。
$ErrorActionPreference = 'Continue'
Set-Location $env:GITHUB_WORKSPACE
$bs = [char]92
New-Item -ItemType Directory -Force logs | Out-Null
$log = 'logs/engine-probe.txt'
$root = $env:KRITA_ROOT
$qt = Join-Path $root '_install/include'
$build = Join-Path $root 'b_krita'
$src = Join-Path $root 'krita'
$rp = 'C:/rp'
if (-not (Test-Path (Join-Path $rp 'app/src/main/cpp'))) {
  git clone --filter=blob:none --sparse --depth 1 --branch $env:UPSTREAM_TAG https://github.com/LanRhyme/ReveriePaint.git $rp
  if ($LASTEXITCODE -ne 0) { throw 'clone upstream failed' }
  git -C $rp sparse-checkout set app/src/main/cpp
  if ($LASTEXITCODE -ne 0) { throw 'sparse checkout failed' }
}
$eng = Join-Path $rp 'app/src/main/cpp'
$shim = Join-Path $env:GITHUB_WORKSPACE 'desktop-port/engine/include'
$clang = Join-Path $env:LLVM_MINGW 'bin/clang++.exe'
# Qt 转发头写的是 include QtCore/qdebug.h，所以 _install/include 根目录本身必须在 -I 里
$incs = @($shim, $qt, $src, (Join-Path $src 'libs'), $build)
$srchdr = @(Get-ChildItem -Path (Join-Path $src 'libs') -Recurse -Filter '*.h' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique)
foreach ($d in $srchdr) { if ($incs -notcontains $d) { $incs += $d } }
$bldhdr = @(Get-ChildItem -Path $build -Recurse -Filter '*.h' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique)
foreach ($d in $bldhdr) { if ($incs -notcontains $d) { $incs += $d } }
$qtSub = @(Get-ChildItem -Path $qt -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
foreach ($d in $qtSub) { if ($incs -notcontains $d) { $incs += $d } }
# KDE 框架装在 include/KF6/<Framework>/ 下（例如 Ki18n/klocalizedstring.h），二级目录也要进 -I
$kf = Join-Path $qt 'KF6'
if (Test-Path $kf) {
  if ($incs -notcontains $kf) { $incs += $kf }
  foreach ($d in @(Get-ChildItem -Path $kf -Directory -ErrorAction SilentlyContinue)) {
    if ($incs -notcontains $d.FullName) { $incs += $d.FullName }
  }
}
# 引擎不只 include libs，还直接 include 了插件源码目录的头（上游 CMakeLists 同样这么做）：
#   plugins/impex/psd          -> psd_colormode_block.h / psd_image_data.h
#   plugins/paintops/libpaintop-> kis_brush_based_paintop_settings.h / kis_brush_option.h
#   plugins/paintops/defaultpaintops/brush -> kis_brushop.h
# 因此把 paintops / impex 两棵树（源码目录 + 构建目录）里所有含 .h 的目录都收进 -I。
$plugDirs = 0
foreach ($rel in @('plugins/paintops', 'plugins/impex')) {
  foreach ($base in @($src, $build)) {
    $p = Join-Path $base $rel
    if (Test-Path $p) {
      foreach ($d in @(Get-ChildItem -Path $p -Recurse -Filter '*.h' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique)) {
        if ($incs -notcontains $d) { $incs += $d; $plugDirs++ }
      }
    }
  }
}
# 上游 CMakeLists 里另外几个 DEPS 子目录
foreach ($dep in @('libmypaint', 'freetype2', 'libunibreak', 'eigen3')) {
  $p = Join-Path $qt $dep
  if ((Test-Path $p) -and ($incs -notcontains $p)) { $incs += $p }
}
foreach ($j in @('include', 'include/win32')) {
  $p = Join-Path $env:JAVA_HOME $j
  if ((Test-Path $p) -and ($incs -notcontains $p)) { $incs += $p }
}
$wanted = @()
foreach ($i in $incs) { if (Test-Path $i) { $wanted += ('-I' + $i) } }
$prelude = Join-Path $shim 'reverie_prelude.h'
# jni.h 走绝对路径强制包含：-I 里有几百个目录，可能先命中别的同名头，导致 JNIEnv 空定义
$jniForce = Join-Path $rp 'jni-force.h'
$jniReal = Join-Path $env:JAVA_HOME 'include/jni.h'
if (Test-Path $jniReal) {
  $jniText = ('#include ' + [char]34 + ($jniReal.Replace($bs, '/')) + [char]34)
  [System.IO.File]::WriteAllText($jniForce, $jniText, (New-Object System.Text.UTF8Encoding($false)))
}
# KoColorSpaceMaths.h 里有名为 xor / and / or 的函数，clang 默认会把它们当运算符关键字
# （xor 视作 ^ 并尝试解析成 block literal），必须用 -fno-operator-names 关掉替代运算符名
$flags = @('-std=c++17', '-fsyntax-only', '-w', '-fms-extensions', '-fno-operator-names')
if (Test-Path $jniForce) { $flags += ('-include ' + $jniForce) }
$flags += @(('-include ' + $prelude)) + $wanted
$rsp = Join-Path $rp 'probe.rsp'
# clang 的 @response 解析按 Windows 规则处理反斜杠：D:/a/x 原样有效，运行时统一转正斜杠
$flagsText = (($flags | ForEach-Object { ([string]$_).Replace($bs, '/') }) -join ([string][char]10))
[System.IO.File]::WriteAllText($rsp, $flagsText, (New-Object System.Text.UTF8Encoding($false)))
$diag = @('--- probe diag ---', ('JAVA_HOME=' + $env:JAVA_HOME))
$dgTime = Join-Path $rp 'dg-time.cpp'
Set-Content -Path $dgTime -Value @('#include <time.h>', 'int main(){ struct timespec dg_ts; (void)dg_ts; return 0; }') -Encoding utf8
$dgJni = Join-Path $rp 'dg-jni.cpp'
Set-Content -Path $dgJni -Value @('#include <jni.h>', 'JNIEnv* dg_env; jobject dg_obj;') -Encoding utf8
foreach ($d in @($dgTime, $dgJni)) {
  $o = & $clang ('@' + $rsp) ($d.Replace($bs, '/')) 2>&1
  $diag += ('[' + (Split-Path $d -Leaf) + '] rc=' + $LASTEXITCODE)
  $diag += @($o | Select-Object -First 12 | ForEach-Object { ([string]$_).Trim() })
}
$diag += '--- jni.h candidates ---'
foreach ($d in @($env:JAVA_HOME, $qt, $shim)) {
  if (Test-Path $d) {
    foreach ($h in @(Get-ChildItem -Path $d -Recurse -Filter 'jni.h' -File -ErrorAction SilentlyContinue | Select-Object -First 8)) {
      $diag += ('hit: ' + $h.FullName.Replace($bs, '/'))
    }
  }
}
# -E 的行标记会直接点出 <jni.h> 实际命中的文件；-fsyntax-only 与 -E 冲突，单独写一份 rsp
$rspE = Join-Path $rp 'probe-e.rsp'
$flagsE = @('-std=c++17', '-E', '-w') + $wanted
$flagsEText = (($flagsE | ForEach-Object { ([string]$_).Replace($bs, '/') }) -join ([string][char]10))
[System.IO.File]::WriteAllText($rspE, $flagsEText, (New-Object System.Text.UTF8Encoding($false)))
$oE = & $clang ('@' + $rspE) ($dgJni.Replace($bs, '/')) 2>&1
$diag += ('[dg-jni -E] rc=' + $LASTEXITCODE)
$diag += @($oE | Select-Object -First 16 | ForEach-Object { ([string]$_).Trim() })
$diag | Out-File -FilePath 'logs/probe-diag.txt' -Encoding utf8
$skip = @('ReverieCrashHandler.cpp')
$files = @(Get-ChildItem (Join-Path $eng '*.cpp') | Where-Object { $skip -notcontains $_.Name } | Sort-Object Name)
$failed = 0
$report = @()
$hist = @{}
foreach ($f in $files) {
  $out = & $clang ('@' + $rsp) ($f.FullName.Replace($bs, '/')) 2>&1
  if ($LASTEXITCODE -ne 0) {
    $failed++
    $report += ('### ' + $f.Name)
    $errs = @($out | Where-Object { ([string]$_) -match 'error' } | Select-Object -First 3)
    if ($errs.Count -eq 0) { $errs = @($out | Select-Object -Last 3) }
    $report += ($errs | ForEach-Object { ([string]$_).Trim() })
    # 第一条 error 定位到 文件:行，把该行前后各 3 行贴进报告，避免只看签名反复猜
    # 注意 clang 实际格式是 file:196:50: error:（冒号后无空格），正则不能多空格
    $first = @($out | Where-Object { ([string]$_) -match '^[A-Za-z]:.*:[0-9]+:[0-9]+: (fatal )?error: ' } | Select-Object -First 1)
    if ($first.Count -gt 0) {
      $m = [regex]::Match(([string]$first[0]).Trim(), '^(.*):([0-9]+):[0-9]+: (fatal )?error: ')
      if ($m.Success) {
        $cp = $m.Groups[1].Value
        $cl = [int]$m.Groups[2].Value
        if (Test-Path -LiteralPath $cp) {
          $arr = @(Get-Content -LiteralPath $cp -ErrorAction SilentlyContinue)
          $from = $cl - 3
          if ($from -lt 1) { $from = 1 }
          $to = $cl + 3
          if ($to -gt $arr.Count) { $to = $arr.Count }
          for ($k = $from; $k -le $to; $k++) {
            $mark = '   '
            if ($k -eq $cl) { $mark = '>> ' }
            $s = [string]$arr[$k - 1]
            if ($s.Length -gt 170) { $s = $s.Substring(0, 170) }
            $report += ($mark + $k + ': ' + $s)
          }
        }
      }
    }
    foreach ($e in @($out | Where-Object { ([string]$_) -match ': (fatal )?error: ' })) {
      $norm = (([string]$e).Trim() -replace '^.*?: (fatal error|error): ', '')
      if ($hist.ContainsKey($norm)) { $hist[$norm]++ } else { $hist[$norm] = 1 }
    }
  }
}
$summary = ('probe: ' + $failed + '/' + $files.Count + ' cpp files failed (incs: ' + $wanted.Count + ', src hdr dirs: ' + $srchdr.Count + ', build hdr dirs: ' + $bldhdr.Count + ', qt sub: ' + $qtSub.Count + ', plug: ' + $plugDirs + ')')
# 关键头文件是否可解析，直接写进日志首行区，省得靠 incs 数字猜
$probeHdr = @('kis_brush_based_paintop_settings.h', 'psd_colormode_block.h', 'kis_brushop.h')
foreach ($h in $probeHdr) {
  $hit = @($wanted | Where-Object { Test-Path (Join-Path $_.Substring(2) $h) } | Select-Object -First 1)
  $res = 'MISS'
  if ($hit.Count -gt 0) { $res = 'OK ' + $hit[0] }
  $summary = $summary + ' | ' + $h + ': ' + $res
}
$lines = @($summary)
if ($hist.Count -gt 0) {
  $lines += '--- 错误签名 Top 15 ---'
  $lines += ($hist.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 15 | ForEach-Object { ('[' + $_.Value + 'x] ' + $_.Key) })
}
Set-Content -Path $log -Value $lines -Encoding utf8
$lines | ForEach-Object { $_ }
$report | Select-Object -First 500 | Out-File -FilePath $log -Append -Encoding utf8
if ($failed -gt 0) { exit 1 }
exit 0
