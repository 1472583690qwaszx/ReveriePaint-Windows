// SPDX-License-Identifier: GPL-3.0-or-later
// Windows stub for <dlfcn.h>.
//
// Every dlopen/dlsym call in the engine exists only to reach Qt's Android JNI
// bootstrap (QtAndroidPrivate::initJNI). On Windows Qt is linked normally, so
// loading is a no-op and sym lookups report "not found".
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#define RTLD_LAZY 0
#define RTLD_NOW 0
#define RTLD_NOLOAD 0

void *dlopen(const char *path, int mode);
void *dlsym(void *handle, const char *name);
int dlclose(void *handle);
char *dlerror(void);

#ifdef __cplusplus
}
#endif
