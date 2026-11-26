// SPDX-License-Identifier: GPL-3.0-or-later
#include <reverie_win_compat.h>

#include <dlfcn.h>
#include <sched.h>
#include <sys/mman.h>

#include <cstdio>
#include <cstring>
#include <windows.h>

extern "C" {

long sysconf(int name) {
    if (name == _SC_PAGESIZE) {
        SYSTEM_INFO info;
        GetSystemInfo(&info);
        return static_cast<long>(info.dwPageSize);
    }
    if (name == _SC_NPROCESSORS_CONF) {
        return static_cast<long>(GetActiveProcessorCount(ALL_PROCESSOR_GROUPS));
    }
    return -1;
}

int kill(int pid, int sig) {
    (void)pid;
    (void)sig;
    return 0;
}

int mprotect(void *addr, size_t len, int prot) {
    DWORD flags = PAGE_READONLY;
    if (prot & PROT_WRITE) {
        flags = PAGE_READWRITE;
    } else if (prot == PROT_NONE) {
        flags = PAGE_NOACCESS;
    }
    DWORD previous = 0;
    return VirtualProtect(addr, len, flags, &previous) ? 0 : -1;
}

int sched_setaffinity(int pid, size_t cpusetsize, const cpu_set_t *mask) {
    (void)pid;
    (void)cpusetsize;
    (void)mask;
    return 0;
}

int sched_yield(void) {
    SwitchToThread();
    return 0;
}

void *dlopen(const char *path, int mode) {
    (void)path;
    (void)mode;
    return nullptr;
}

void *dlsym(void *handle, const char *name) {
    (void)handle;
    (void)name;
    return nullptr;
}

int dlclose(void *handle) {
    (void)handle;
    return 0;
}

char *dlerror(void) {
    static char message[] = "dlfcn unavailable on Windows";
    return message;
}

} // extern "C"
