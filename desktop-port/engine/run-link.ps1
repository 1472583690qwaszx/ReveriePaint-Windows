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
trap {
  $msg = 'EXCEPTION: ' + $_.Exception.Message + [char]10 + $_.ScriptStackTrace
  try { Set-Content -Path $log -Value $msg -Encoding utf8 } catch { }
  Write-Host $msg
  exit 1
}
$root = $env:KRITA_ROOT
$build = Join-Path $root 'b_krita'
$inst = Join-Path $root '_install'
$rp = 'C:/rp'
$objDir = Join-Path $rp 'obj'
$clang = Join-Path $env:LLVM_MINGW 'bin/clang++.exe'
$extraSrc = @(Get-ChildItem (Join-Path $env:GITHUB_WORKSPACE 'desktop-port/engine/src') -Filter '*.cpp' -File -ErrorAction SilentlyContinue | Sort-Object Name)
$cRsp = Join-Path $rp 'compile.rsp'
$extraLog = @()
if ($extraSrc.Count -gt 0) {
  New-Item -ItemType Directory -Force $objDir | Out-Null
  if (Test-Path $cRsp) {
    $eng = Join-Path $rp 'app/src/main/cpp'
    $extraRsp = Join-Path $rp 'compile-extra.rsp'
    $txt = (Get-Content -Path $cRsp -Raw) + [char]10 + ('-I' + $eng.Replace($bs, '/')) + [char]10
    [System.IO.File]::WriteAllText($extraRsp, $txt, (New-Object System.Text.UTF8Encoding($false)))
    foreach ($f in $extraSrc) {
      $xo = Join-Path $objDir ('xx-' + $f.BaseName + '.o')
      $xo2 = & $clang ('@' + $extraRsp) ($f.FullName.Replace($bs, '/')) '-o' ($xo.Replace($bs, '/')) 2>&1
      if ($LASTEXITCODE -ne 0) {
        $extraLog += ('EXTRA COMPILE FAILED: ' + $f.Name)
        $extraLog += @($xo2 | Where-Object { ([string]$_) -match 'error' } | Select-Object -First 5 | ForEach-Object { ([string]$_).Trim() })
        Set-Content -Path $log -Value $extraLog -Encoding utf8
        exit 1
      }
      $extraLog += ('extra ok: ' + $f.Name)
    }
  }
}
$objs = @(Get-ChildItem -Path $objDir -Filter '*.o' -File -ErrorAction SilentlyContinue | Sort-Object Name)
if ($objs.Count -eq 0) {
  Set-Content -Path $log -Value 'link: no objects in C:/rp/obj (run-compile 未产出)' -Encoding utf8
  Get-Content $log
  exit 1
}
$implibs = @()
$statics = @()
$scanRoots = @($build, $inst, (Join-Path $root 'deps'), (Join-Path $root '_deps'))
foreach ($base in $scanRoots) {
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
$summary = @('--- link diag ---', ('extras=' + $extraSrc.Count), ('objects=' + $objs.Count + ' implibs=' + $use.Count + ' statics=' + $statics.Count + ' rc=' + $rc + ' time=' + $sec + 's'))
if (Test-Path $out) { $summary += ('dll=' + [int]((Get-Item $out).Length / 1024) + ' KB') } else { $summary += 'dll=missing' }
$undef = @($lo | Where-Object { ([string]$_) -match 'undefined symbol' })
$summary += ('undefined symbols: ' + $undef.Count)
$diagRoots = @()
foreach ($base in $scanRoots) { $diagRoots += (([string]$base).Replace($bs, '/') + '=' + (Test-Path $base)) }
$summary += ('scan roots: ' + ($diagRoots -join ' ; '))
$summary += ('implibs(first 25): ' + (($use | ForEach-Object { [System.IO.Path]::GetFileName($_) } | Select-Object -First 25) -join ','))
$qtFiles = @(Get-ChildItem -Path $root -Recurse -Filter 'Qt6Core*' -File -ErrorAction SilentlyContinue | Select-Object -First 6)
$summary += ('Qt6Core files: ' + (($qtFiles | ForEach-Object { $_.FullName }) -join ' | '))
if ($undef.Count -gt 0) {
  $names = @{}
  foreach ($u in $undef) {
    $m = [regex]::Match(([string]$u), 'undefined symbol: (.+)$')
    if ($m.Success) {
      $n = $m.Groups[1].Value.Trim()
      $n = ($n -replace '^__declspec\(dllimport\) ', '')
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
  $summary += '--- implib exports (first 20) ---'
  $nm = Join-Path $env:LLVM_MINGW 'bin/llvm-nm.exe'
  if (Test-Path $nm) {
    $sy = @(& $nm '--defined-only' $outImplib 2>&1)
    $matched = @($sy | Where-Object { ([string]$_) -match 'Java_com_reverie' })
    $summary += @($matched | Select-Object -First 20 | ForEach-Object { ([string]$_).Trim() })
    $summary += ('Java_ exports: ' + $matched.Count)
  }
}
Set-Content -Path $log -Value $summary -Encoding utf8
$summary | Select-Object -First 40 | ForEach-Object { $_ }
if (-not (Test-Path $out)) { exit 1 }
exit 0
