// SPDX-License-Identifier: GPL-3.0-or-later
// Force-included prelude for the engine compile probe (and later the real DLL build).
//
// Why: the upstream Android JNI sources rely on android/log.h + the NDK sysroot to
// drag in <cstdlib> (atoi/strtol), <cstring>, <ctime> types and <jni.h>. On Windows
// those come from nowhere, so clang stops with "use of undeclared identifier 'atoi'"
// and libc++'s __thread/support/windows.h cannot find ::timespec. Including the C
// headers first gives both libc++ and the engine a consistent global namespace.
#pragma once

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
