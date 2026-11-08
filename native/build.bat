@echo off
setlocal
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars32.bat" >nul 2>nul
cd /d "%~dp0"
if not exist build mkdir build
if not exist ..\game\sharp mkdir ..\game\sharp
cl /nologo /utf-8 /O2 /MT /W3 /GS- /D_CRT_SECURE_NO_WARNINGS /Fobuild\ rando_sharp.c /LD /link /OUT:..\game\sharp\rando_sharp.dll /IMPLIB:build\rando_sharp.lib /EXPORT:RandoSharpInstall=_RandoSharpInstall@0 /EXPORT:RandoSharpTestTarget=_RandoSharpTestTarget@12 d3d11.lib dxgi.lib dxguid.lib user32.lib gdi32.lib kernel32.lib || exit /b 1
cl /nologo /utf-8 /O2 /MT /W3 /D_CRT_SECURE_NO_WARNINGS /Fobuild\ upscale_test.c /Febuild\upscale_test.exe /link d3d11.lib dxgi.lib dxguid.lib user32.lib kernel32.lib || exit /b 1
cl /nologo /utf-8 /O2 /MT /W3 /D_CRT_SECURE_NO_WARNINGS /Fobuild\ rando_sharp_test.c /Febuild\rando_sharp_test.exe /link dxguid.lib user32.lib gdi32.lib kernel32.lib || exit /b 1
del /q ..\game\sharp\*.exp ..\game\sharp\*.lib 2>nul
echo built
