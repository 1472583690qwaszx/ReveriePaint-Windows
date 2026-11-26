// SPDX-License-Identifier: GPL-3.0-or-later
// Implementation of the Android bitmap / log / property shims on Windows.
#include <android/bitmap.h>
#include <android/log.h>
#include <sys/system_properties.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>

namespace {

const char *LevelName(int prio) {
    switch (prio) {
    case ANDROID_LOG_VERBOSE: return "V";
    case ANDROID_LOG_DEBUG:   return "D";
    case ANDROID_LOG_INFO:    return "I";
    case ANDROID_LOG_WARN:    return "W";
    case ANDROID_LOG_ERROR:   return "E";
    case ANDROID_LOG_FATAL:   return "F";
    default:                  return "?";
    }
}

bool LogDisabled() {
    static const bool disabled = [] {
        const char *raw = std::getenv("REVERIE_LOG");
        return raw != nullptr && std::strcmp(raw, "0") == 0;
    }();
    return disabled;
}

// Cached field ids for com.reverie.paint.rt.RtBitmap. Field lookup is guarded by
// a mutex because JNI calls can come from several stroke threads.
struct RtBitmapIds {
    jclass cls = nullptr;
    jfieldID width = nullptr;
    jfieldID height = nullptr;
    jfieldID stride = nullptr;
    jfieldID format = nullptr;
    jfieldID pixels = nullptr;
    bool ready = false;
};

RtBitmapIds g_ids;
std::mutex g_idsMutex;

bool EnsureIds(JNIEnv *env) {
    std::lock_guard<std::mutex> guard(g_idsMutex);
    if (g_ids.ready) {
        return true;
    }
    jclass local = env->FindClass("com/reverie/paint/rt/RtBitmap");
    if (local == nullptr) {
        env->ExceptionClear();
        return false;
    }
    g_ids.cls = static_cast<jclass>(env->NewGlobalRef(local));
    g_ids.width = env->GetFieldID(local, "width", "I");
    g_ids.height = env->GetFieldID(local, "height", "I");
    g_ids.stride = env->GetFieldID(local, "stride", "I");
    g_ids.format = env->GetFieldID(local, "format", "I");
    g_ids.pixels = env->GetFieldID(local, "pixels", "Ljava/nio/ByteBuffer;");
    env->DeleteLocalRef(local);
    if (g_ids.width == nullptr || g_ids.height == nullptr || g_ids.stride == nullptr ||
        g_ids.format == nullptr || g_ids.pixels == nullptr) {
        env->ExceptionClear();
        return false;
    }
    g_ids.ready = true;
    return true;
}

} // namespace

extern "C" {

int __android_log_print(int prio, const char *tag, const char *fmt, ...) {
    if (LogDisabled()) {
        return 0;
    }
    va_list ap;
    va_start(ap, fmt);
    std::fprintf(stderr, "%s/%-10s: ", LevelName(prio), tag ? tag : "reverie");
    std::vfprintf(stderr, fmt, ap);
    std::fputc('\n', stderr);
    va_end(ap);
    return 0;
}

int __android_log_vprint(int prio, const char *tag, const char *fmt, va_list ap) {
    if (LogDisabled()) {
        return 0;
    }
    std::fprintf(stderr, "%s/%-10s: ", LevelName(prio), tag ? tag : "reverie");
    std::vfprintf(stderr, fmt, ap);
    std::fputc('\n', stderr);
    return 0;
}

int __android_log_write(int prio, const char *tag, const char *text) {
    if (LogDisabled()) {
        return 0;
    }
    std::fprintf(stderr, "%s/%-10s: %s\n", LevelName(prio), tag ? tag : "reverie",
                 text ? text : "");
    return 0;
}

void __android_log_assert(const char *cond, const char *tag, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    std::fprintf(stderr, "ASSERT %s/%s: ", tag ? tag : "reverie", cond ? cond : "");
    std::vfprintf(stderr, fmt, ap);
    std::fputc('\n', stderr);
    va_end(ap);
    std::abort();
}

// Android debug properties are used here only to gate optional debug features.
// On Windows there is no property service, so every lookup reports "unset"; the
// call sites all treat a non-positive return as "use the default".
int __system_property_get(const char *name, char *value) {
    (void)name;
    if (value != nullptr) {
        value[0] = '\0';
    }
    return 0;
}

int AndroidBitmap_getInfo(JNIEnv *env, jobject bitmap, AndroidBitmapInfo *info) {
    if (env == nullptr || bitmap == nullptr || info == nullptr) {
        return ANDROID_BITMAP_RESULT_BAD_PARAMETER;
    }
    if (!EnsureIds(env)) {
        return ANDROID_BITMAP_RESULT_JNI_EXCEPTION;
    }
    info->width = static_cast<uint32_t>(env->GetIntField(bitmap, g_ids.width));
    info->height = static_cast<uint32_t>(env->GetIntField(bitmap, g_ids.height));
    info->stride = static_cast<uint32_t>(env->GetIntField(bitmap, g_ids.stride));
    info->format = static_cast<uint32_t>(env->GetIntField(bitmap, g_ids.format));
    info->flags = 0;
    return ANDROID_BITMAP_RESULT_SUCCESS;
}

int AndroidBitmap_lockPixels(JNIEnv *env, jobject bitmap, void **addrPtr) {
    if (env == nullptr || bitmap == nullptr || addrPtr == nullptr) {
        return ANDROID_BITMAP_RESULT_BAD_PARAMETER;
    }
    if (!EnsureIds(env)) {
        return ANDROID_BITMAP_RESULT_JNI_EXCEPTION;
    }
    jobject buffer = env->GetObjectField(bitmap, g_ids.pixels);
    if (buffer == nullptr) {
        return ANDROID_BITMAP_RESULT_BAD_PARAMETER;
    }
    void *addr = env->GetDirectBufferAddress(buffer);
    env->DeleteLocalRef(buffer);
    if (addr == nullptr) {
        // A non-direct buffer cannot be handed to native code; RtBitmap must
        // allocate with ByteBuffer.allocateDirect().
        return ANDROID_BITMAP_RESULT_BAD_PARAMETER;
    }
    *addrPtr = addr;
    return ANDROID_BITMAP_RESULT_SUCCESS;
}

int AndroidBitmap_unlockPixels(JNIEnv *env, jobject bitmap) {
    (void)env;
    (void)bitmap;
    // Direct buffers are always "locked" here, so there is nothing to release.
    return ANDROID_BITMAP_RESULT_SUCCESS;
}

} // extern "C"
