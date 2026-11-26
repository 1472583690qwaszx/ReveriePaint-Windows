# Engine link (reverie_core.dll) for ReveriePaint v1.11.0 on Windows.
# 前提：Krita 已 build+install（b_krita 里有 DLL 与导入库），engine 的 .o 已由 run-compile.ps1 生成。
# 做法：把所有 *.dll.a（Krita 各库 + Qt6 + KF6 + 依赖）与 kritaglobal 静态库一起喂给链接器，
# 导入库只在实际用到符号时才有影响，多给不会造成多余依赖。
# 退出码 0 = reverie_core.dll 生成成功；1 = 失败（日志在 logs/engine-link.txt）。
$ErrorActionPreference = 'Continue'
Set-Location $env:GITHUB_WORKSPACE
$bs = [char]92
New-Item -ItemType Directory -Force logs | Out-Null
$log = 'logs/engine-link.txt'
$root = $env:KRITA_ROOT
$build = Join-Path $root 'b_krita'
$inst = Join-Path $root '_install'
$rp = 'C:/rp'
$objDir = Join-Path $rp 'obj'
$objs = @(Get-ChildItem -Path $objDir -Filter '*.o' -File -ErrorAction SilentlyContinue | Sort-Object Name)
if ($objs.Count -eq 0) {
  Set-Content -Path $log -Value 'link: no objects in C:/rp/obj (run-compile 未产出)' -Encoding utf8
  Get-Content $log
  exit 1
}
$implibs = @()
$statics = @()
foreach ($base in @($build, (Join-Path $inst 'lib'))) {
  if (Test-Path $base) {
    $implibs += @(Get-ChildItem -Path $base -Recurse -Filter '*.dll.a' -File -ErrorAction SilentlyContinue | Sort-Object FullName)
  }
}
$seen = @{}
$use = @()
foreach ($l in $implibs) {
  if (-not $seen.ContainsKey($l.Name)) { $seen[$l.Name] = 1; $use += $l.FullName }
}
foreach ($base in @($build, (Join-Path $inst 'lib'))) {
  if (Test-Path $base) {
    $statics += @(Get-ChildItem -Path $base -Recurse -Filter 'libkritaglobal.a' -File -ErrorAction SilentlyContinue | Select-Object -First 1)
  }
}
$clang = Join-Path $env:LLVM_MINGW 'bin/clang++.exe'
$out = Join-Path $rp 'reverie_core.dll'
$outImplib = Join-Path $rp 'reverie_core.dll.a'
$lines = @('-shared', '-o', ($out.Replace($bs, '/')), ('-Wl,--out-implib=' + $outImplib.Replace($bs, '/')))
foreach ($o in $objs) { $lines += $o.FullName }
foreach ($s in $statics) { $lines += $s.FullName }
foreach ($l in $use) { $lines += $l }
$rsp = Join-Path $rp 'link.rsp'
$rspText = (($lines | ForEach-Object { ([string]$_).Replace($bs, '/') }) -join ([string][char]10))
[System.IO.File]::WriteAllText($rsp, $rspText, (New-Object System.Text.UTF8Encoding($false)))
$t0 = Get-Date
$lo = & $clang ('@' + $rsp) 2>&1
$rc = $LASTEXITCODE
$sec = [int]((Get-Date) - $t0).TotalSeconds
$summary = @('--- link diag ---', ('objects=' + $objs.Count + ' implibs=' + $use.Count + ' statics=' + $statics.Count + ' rc=' + $rc + ' time=' + $sec + 's'))
if (Test-Path $out) { $summary += ('dll=' + [int]((Get-Item $out).Length / 1024) + ' KB') } else { $summary += 'dll=missing' }
$undef = @($lo | Where-Object { ([string]$_) -match 'undefined symbol' })
$summary += ('undefined symbols: ' + $undef.Count)
if ($undef.Count -gt 0) {
  $names = @{}
  foreach ($u in $undef) {
    $m = [regex]::Match(([string]$u), 'undefined symbol: (.+)$')
    if ($m.Success) {
      $n = $m.Groups[1].Value.Trim()
      $n = ($n -replace '\(.*$', '').Trim()
      if ($names.ContainsKey($n)) { $names[$n]++ } else { $names[$n] = 1 }
    }
  }
  $summary += '--- undefined top 20 ---'
  $summary += ($names.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20 | ForEach-Object { ('[' + $_.Value + 'x] ' + $_.Key) })
}
$summary += '--- linker output tail 60 ---'
$summary += @($lo | Select-Object -Last 60 | ForEach-Object { ([string]$_).Trim() })
if (Test-Path $out) {
  $summary += '--- implib 里的导出符号（前 20）---'
  $nm = Join-Path $env:LLVM_MINGW 'bin/llvm-nm.exe'
  if (Test-Path $nm) {
    $sy = & $nm '--defined-only' $outImplib 2>&1
    $summary += @($sy | Where-Object { ([string]$_) -match 'Java_com_reverie' } | Select-Object -First 20 | ForEach-Object { ([string]$_).Trim() })
    $summary += ('Java_ exports: ' + @($sy | Where-Object { ([string]$_ -match 'Java_com_reverie' }).Count))
  }
}
Set-Content -Path $log -Value $summary -Encoding utf8
$summary | Select-Object -First 40 | ForEach-Object { $_ }
if (-not (Test-Path $out)) { exit 1 }
exit 0
