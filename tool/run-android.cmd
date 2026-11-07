@echo off
rem Menjalankan Nilaya Living di emulator/HP Android yang terhubung.
rem Tekan r = hot reload, R = restart, q = keluar.
set "ANDROID_HOME=D:\Tools\android-sdk"
set "ANDROID_SDK_ROOT=D:\Tools\android-sdk"
set "ANDROID_AVD_HOME=D:\Tools\avd"
set "GRADLE_USER_HOME=D:\Tools\gradle"
set "PUB_CACHE=D:\Tools\pub-cache"
set "PATH=D:\Tools\flutter\bin;D:\Tools\android-sdk\platform-tools;C:\Program Files\Git\cmd;%PATH%"
cd /d "%~dp0.."
flutter run
