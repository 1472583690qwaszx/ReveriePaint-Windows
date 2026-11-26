// SPDX-License-Identifier: GPL-3.0-or-later
// Force-included prelude for the engine compile probe (and later the real DLL build).
//
// Why: the upstream Android JNI sources rely on android/log.h + the NDK sysroot to
// drag in <cstdlib> (atoi/strtol), <cstring>, <ctime> types and <jni.h>. On Windows
// those come from nowhere, so clang stops with "use of undeclared identifier 'atoi'"
// and libc++'s __thread/support/windows.h cannot find ::timespec. Including the C
// headers first gives both libc++ and the engine a consistent global namespace.
#pragma once

// Release-equivalent build: NDEBUG 必须在任何 C/C++ 头之前定义。
// 起因：Eigen 的 eigen_assert -> assert(x)，而这条 Windows include 链上 assert 标识符
// 在 Eigen 头展开时已经不可见（551 处 use of undeclared identifier 'assert'）。
// 定义 NDEBUG 后 Eigen 走 EIGEN_NO_DEBUG 分支，assert 调用整段消失，与 Release 语义一致。
#ifndef NDEBUG
#define NDEBUG 1
#endif

#ifndef __cplusplus
#error "reverie_prelude.h is C++ only"
#endif

#include <sys/types.h>
#include <time.h>
#include <wchar.h>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <cmath>
#include <cassert>

#include <jni.h>
#include "reverie_win_compat.h"
