@echo off
rem Menyalakan emulator Android (HP virtual) yang tersimpan di D:\Tools\avd.
set "ANDROID_HOME=D:\Tools\android-sdk"
set "ANDROID_SDK_ROOT=D:\Tools\android-sdk"
set "ANDROID_AVD_HOME=D:\Tools\avd"
"D:\Tools\android-sdk\emulator\emulator.exe" -avd Medium_Phone_API_37.0 -memory 2048
