// SPDX-License-Identifier: GPL-3.0-or-later
// Windows shim for <android/log.h>. Values match Android's enum so existing
// ANDROID_LOG_* comparisons in ReveriePaint keep working unchanged.
#pragma once

#include <cstdarg>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    ANDROID_LOG_UNKNOWN = 0,
    ANDROID_LOG_DEFAULT = 1,
    ANDROID_LOG_VERBOSE = 2,
    ANDROID_LOG_DEBUG = 3,
    ANDROID_LOG_INFO = 4,
    ANDROID_LOG_WARN = 5,
    ANDROID_LOG_ERROR = 6,
    ANDROID_LOG_FATAL = 7,
    ANDROID_LOG_SILENT = 8
};

int __android_log_print(int prio, const char *tag, const char *fmt, ...);
int __android_log_vprint(int prio, const char *tag, const char *fmt, va_list ap);
int __android_log_write(int prio, const char *tag, const char *text);
void __android_log_assert(const char *cond, const char *tag, const char *fmt, ...);

#ifdef __cplusplus
}
#endif
