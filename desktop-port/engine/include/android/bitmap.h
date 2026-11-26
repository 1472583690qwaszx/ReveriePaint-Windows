// SPDX-License-Identifier: GPL-3.0-or-later
// Windows shim for <android/bitmap.h>.
//
// On Android these calls read/lock android.graphics.Bitmap pixel memory. On the
// desktop JVM there is no android.graphics.Bitmap, so the UI hands us
// com.reverie.paint.rt.RtBitmap instead: a plain class with width/height/stride/
// format fields plus a direct java.nio.ByteBuffer named "pixels". The 57 existing
// call sites in the engine stay untouched because the API shape is identical.
#pragma once

#include <cstdint>
#include <jni.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    ANDROID_BITMAP_RESULT_SUCCESS = 0,
    ANDROID_BITMAP_RESULT_BAD_PARAMETER = -1,
    ANDROID_BITMAP_RESULT_JNI_EXCEPTION = -2,
    ANDROID_BITMAP_RESULT_ALLOCATION_FAILED = -3
};

enum {
    ANDROID_BITMAP_FORMAT_NONE = 0,
    ANDROID_BITMAP_FORMAT_RGBA_8888 = 1,
    ANDROID_BITMAP_FORMAT_RGB_565 = 3,
    ANDROID_BITMAP_FORMAT_RGBA_4444 = 7,
    ANDROID_BITMAP_FORMAT_A_8 = 8
};

typedef struct {
    uint32_t width;
    uint32_t height;
    uint32_t stride;
    uint32_t format;
    uint32_t flags;
} AndroidBitmapInfo;

int AndroidBitmap_getInfo(JNIEnv *env, jobject bitmap, AndroidBitmapInfo *info);
int AndroidBitmap_lockPixels(JNIEnv *env, jobject bitmap, void **addrPtr);
int AndroidBitmap_unlockPixels(JNIEnv *env, jobject bitmap);

#ifdef __cplusplus
}
#endif
