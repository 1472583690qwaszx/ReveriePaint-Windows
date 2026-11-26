# Engine real compilation (codegen) for ReveriePaint v1.11.0 on Windows.
# 探针只做 -fsyntax-only；这一步真的编出 .o（-c，优化打开），用来暴露
# 语法检查看不到的问题：模板实例化、内联汇编、codegen、缺失定义等。
# 退出码 0 = 全部 TU 编出目标文件；1 = 有失败（日志在 logs/engine-compile.txt）。
$ErrorActionPreference = 'Continue'
Set-Location $env:GITHUB_WORKSPACE
$bs = [char]92
New-Item -ItemType Directory -Force logs | Out-Null
$log = 'logs/engine-compile.txt'
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
$incs = @($shim, $qt, $src, (Join-Path $src 'libs'), $build)
$srchdr = @(Get-ChildItem -Path (Join-Path $src 'libs') -Recurse -Filter '*.h' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique)
foreach ($d in $srchdr) { if ($incs -notcontains $d) { $incs += $d } }
$bldhdr = @(Get-ChildItem -Path $build -Recurse -Filter '*.h' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique)
foreach ($d in $bldhdr) { if ($incs -notcontains $d) { $incs += $d } }
$qtSub = @(Get-ChildItem -Path $qt -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
foreach ($d in $qtSub) { if ($incs -notcontains $d) { $incs += $d } }
$kf = Join-Path $qt 'KF6'
if (Test-Path $kf) {
  if ($incs -notcontains $kf) { $incs += $kf }
  foreach ($d in @(Get-ChildItem -Path $kf -Directory -ErrorAction SilentlyContinue)) {
    if ($incs -notcontains $d.FullName) { $incs += $d.FullName }
  }
}
foreach ($rel in @('plugins/paintops', 'plugins/impex')) {
  foreach ($base in @($src, $build)) {
    $p = Join-Path $base $rel
    if (Test-Path $p) {
      foreach ($d in @(Get-ChildItem -Path $p -Recurse -Filter '*.h' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique)) {
        if ($incs -notcontains $d) { $incs += $d }
      }
    }
  }
}
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
$jniForce = Join-Path $rp 'jni-force.h'
$jniReal = Join-Path $env:JAVA_HOME 'include/jni.h'
if (Test-Path $jniReal) {
  $jniText = ('#include ' + [char]34 + ($jniReal.Replace($bs, '/')) + [char]34)
  [System.IO.File]::WriteAllText($jniForce, $jniText, (New-Object System.Text.UTF8Encoding($false)))
}
$objDir = Join-Path $rp 'obj'
New-Item -ItemType Directory -Force $objDir | Out-Null
$flags = @('-std=c++17', '-O1', '-w', '-fms-extensions', '-fno-operator-names', '-DUNICODE', '-D_UNICODE', '-c')
if (Test-Path $jniForce) { $flags += ('-include ' + $jniForce) }
$flags += @(('-include ' + $prelude)) + $wanted
$rsp = Join-Path $rp 'compile.rsp'
$flagsText = (($flags | ForEach-Object { ([string]$_).Replace($bs, '/') }) -join ([string][char]10))
[System.IO.File]::WriteAllText($rsp, $flagsText, (New-Object System.Text.UTF8Encoding($false)))
$skip = @('ReverieCrashHandler.cpp', 'ReverieCoreCollab.cpp')
$files = @(Get-ChildItem (Join-Path $eng '*.cpp') | Where-Object { $skip -notcontains $_.Name } | Sort-Object Name)
$failed = 0
$okCount = 0
$totalBytes = 0
$report = @()
$hist = @{}
$idx = 0
foreach ($f in $files) {
  $idx++
  $obj = Join-Path $objDir (('{0:D2}' -f $idx) + '-' + $f.BaseName + '.o')
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $out = & $clang ('@' + $rsp) ($f.FullName.Replace($bs, '/')) '-o' ($obj.Replace($bs, '/')) 2>&1
  $sw.Stop()
  $sec = [int]($sw.Elapsed.TotalSeconds)
  if ($LASTEXITCODE -ne 0) {
    $failed++
    $report += ('### ' + $f.Name + '  (' + $sec + 's)')
    $errs = @($out | Where-Object { ([string]$_) -match 'error' } | Select-Object -First 3)
    if ($errs.Count -eq 0) { $errs = @($out | Select-Object -Last 3) }
    $report += ($errs | ForEach-Object { ([string]$_).Trim() })
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
  } else {
    $okCount++
    if (Test-Path $obj) { $totalBytes += (Get-Item $obj).Length }
    $report += ('ok ' + $f.Name + '  (' + $sec + 's)')
  }
}
$summary = ('compile: ' + $failed + '/' + $files.Count + ' cpp files failed, ' + $okCount + ' objects built, ' + [int]($totalBytes / 1024) + ' KB total, flags -O1')
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
