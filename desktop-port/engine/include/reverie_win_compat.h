// SPDX-License-Identifier: GPL-3.0-or-later
// Force-included (-include) ahead of every engine translation unit so that the
// few remaining POSIX symbols (sysconf / kill / getpid) resolve on MSVC / UCRT
// without shadowing the toolchain's own headers.
#pragma once

#include <process.h>

#ifndef _SC_PAGESIZE
#define _SC_PAGESIZE 30
#endif
#ifndef _SC_NPROCESSORS_CONF
#define _SC_NPROCESSORS_CONF 83
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Returns the page size or core count for the two selectors the engine uses.
long sysconf(int name);
// Crash handler signal path; the Windows build compiles the handler out, so a
// no-op keeps the remaining call sites linkable.
int kill(int pid, int sig);
// ReverieCoreIO.cpp 用 ::fsync 刷盘；Windows 走 _commit。
int fsync(int fd);

#ifdef __cplusplus
}
#endif
