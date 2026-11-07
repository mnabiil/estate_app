@echo off
rem Login Firebase CLI memakai alat yang terpasang di D:\Tools.
set "PATH=D:\Tools\node;D:\Tools\npm-global;D:\Tools\pub-cache\bin;D:\Tools\flutter\bin;%PATH%"
set "npm_config_prefix=D:\Tools\npm-global"
set "npm_config_cache=D:\Tools\npm-cache"
set "PUB_CACHE=D:\Tools\pub-cache"
call firebase login
echo.
echo Selesai. Akun yang login:
call firebase login:list
