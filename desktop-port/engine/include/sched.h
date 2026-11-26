// SPDX-License-Identifier: GPL-3.0-or-later
// Windows shim for <sched.h>.
//
// The engine pins the render thread to the "big" cores (sched_setaffinity).
// On Windows we keep the API but only report success so callers never abort;
// real affinity tuning is a Windows-specific follow-up item.
#pragma once

#include <cstddef>

typedef struct {
    unsigned long bits[16];
} cpu_set_t;

#ifdef __cplusplus
extern "C" {
#endif

int sched_setaffinity(int pid, size_t cpusetsize, const cpu_set_t *mask);
int sched_yield(void);

#ifdef __cplusplus
}
#endif

#define CPU_ZERO(set) for (int _i = 0; _i < 16; ++_i) { (set)->bits[_i] = 0UL; }
#define CPU_SET(cpu, set) ((set)->bits[(cpu) / 32] |= (1UL << ((cpu) % 32)))
