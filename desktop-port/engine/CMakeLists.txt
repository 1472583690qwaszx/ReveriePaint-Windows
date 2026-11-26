# SPDX-License-Identifier: GPL-3.0-or-later
# Windows build of ReveriePaint's native engine (reverie_core.dll).
#
# Inputs:
#   REVERIE_SRC   path to upstream app/src/main/cpp (v1.11.0)
#   KRITA_SRC     path to the Krita 6.0.4 source tree
#   KRITA_INSTALL path to the Krita install prefix (Qt + kis_*.dll import libs)
cmake_minimum_required(VERSION 3.21)
project(reverie_core LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT REVERIE_SRC)
  message(FATAL_ERROR "REVERIE_SRC not set")
endif()

set(SHIM_DIR "${CMAKE_CURRENT_SOURCE_DIR}/include")

# The Android crash handler is built on ucontext/unwind and Android tombstoning;
# it has no Windows counterpart yet, so it is excluded rather than stubbed.
list(APPEND REVERIE_EXCLUDED ReverieCrashHandler.cpp)

file(GLOB REVERIE_SOURCES "${REVERIE_SRC}/*.cpp")
list(FILTER REVERIE_SOURCES EXCLUDE REGEX "*/(${REVERIE_EXCLUDED})$")

add_library(reverie_core SHARED ${REVERIE_SOURCES}
  "${CMAKE_CURRENT_SOURCE_DIR}/src/android_shims_win.cpp"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/posix_shims_win.cpp")

target_include_directories(reverie_core PRIVATE
  "${SHIM_DIR}"
  "${REVERIE_SRC}"
  "${KRITA_SRC}"
  "${KRITA_SRC}/libs"
  "${KRITA_SRC}/libs/global"
  "${KRITA_SRC}/libs/image"
  "${KRITA_SRC}/libs/pigment"
  "${KRITA_SRC}/libs/ui"
  "${KRITA_SRC}/libs/flake"
  "${KRITA_SRC}/libs/brush"
  "${KRITA_SRC}/libs/color"
  "${KRITA_SRC}/libs/command"
  "${KRITA_SRC}/libs/impex"
  "${KRITA_SRC}/libs/metadata"
  "${KRITA_SRC}/libs/psd"
  "${KRITA_SRC}/libs/store"
  "${KRITA_SRC}/libs/resources")

# Shims must win over any toolchain header of the same name.
target_compile_options(reverie_core PRIVATE
  "-include" "${SHIM_DIR}/reverie_win_compat.h")

find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets Concurrent)
target_link_libraries(reverie_core PRIVATE Qt6::Core Qt6::Gui Qt6::Widgets Qt6::Concurrent)

set_target_properties(reverie_core PROPERTIES
  PREFIX ""
  OUTPUT_NAME "reverie_core")
