@echo off
rem 开发期启动脚本：从 clone 出来的发行目录直接起程序
setlocal
set "PKG=%~dp0..\dist\ReveriePaint"
if not exist "%PKG%\bin\krita.exe" (
    echo [x] 没有找到 %PKG%\bin\krita.exe
    echo     先跑 04-stage-portable.ps1
    exit /b 1
)
set "REVERIE_ROOT=%PKG%"
set "REVERIE_ASSET_DIR=%PKG%\share\reveriepaint\assets"
start "" "%PKG%\bin\krita.exe" %*
exit /b 0
