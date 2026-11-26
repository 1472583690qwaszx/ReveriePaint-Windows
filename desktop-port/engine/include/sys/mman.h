// SPDX-License-Identifier: GPL-3.0-or-later
// Windows shim for <sys/mman.h>.
// Only mprotect is used (vtable backup for the RGB colour-space hook); it maps
// to VirtualProtect and degrades to failure, which the caller already handles.
#pragma once

#include <cstddef>

#ifndef PROT_READ
#define PROT_READ 0x1
#endif
#ifndef PROT_WRITE
#define PROT_WRITE 0x2
#endif
#ifndef PROT_NONE
#define PROT_NONE 0x0
#endif

#ifdef __cplusplus
extern "C" {
#endif

int mprotect(void *addr, size_t len, int prot);

#ifdef __cplusplus
}
#endif
