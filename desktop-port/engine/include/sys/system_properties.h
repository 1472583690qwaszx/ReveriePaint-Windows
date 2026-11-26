// SPDX-License-Identifier: GPL-3.0-or-later
// Windows shim for <sys/system_properties.h>.
// Implemented in src/android_shims_win.cpp: always reports "property unset".
#pragma once

#define PROP_VALUE_MAX 92
#define PROP_NAME_MAX 32

#ifdef __cplusplus
extern "C" {
#endif

int __system_property_get(const char *name, char *value);

#ifdef __cplusplus
}
#endif
