@echo off
setlocal
set "SOURCE=%~dp0..\addon\npc_sitter"
set "GMOD=%~1"
if not defined GMOD set "GMOD=%ProgramFiles(x86)%\Steam\steamapps\common\GarrysMod\garrysmod"
if not exist "%SOURCE%\lua\" (echo Addon source not found: "%SOURCE%" & exit /b 1)
if not exist "%GMOD%\addons\" (echo Invalid Garrys Mod folder: "%GMOD%" & exit /b 1)
for %%I in ("%SOURCE%") do set "SOURCE=%%~fI"
for %%I in ("%GMOD%") do set "GMOD=%%~fI"
for %%I in ("%GMOD%") do if /I not "%%~nxI"=="garrysmod" (echo Expected the garrysmod directory. & exit /b 1)
set "DEST=%GMOD%\addons\npc_sitter"
if /I "%SOURCE%"=="%DEST%" (echo Source and destination must be different. & exit /b 1)
if exist "%DEST%\" (
    echo Removing old NPC Sitter...
    rmdir /S /Q "%DEST%"
    if exist "%DEST%\" (echo Failed to remove the old addon. & exit /b 1)
)
mkdir "%DEST%"
if errorlevel 1 (echo Failed to create addon folder. & exit /b 1)
xcopy "%SOURCE%\*" "%DEST%\" /E /I /Y /Q >nul
if errorlevel 1 (echo Installation failed. & exit /b 1)
echo NPC Sitter installed to: "%DEST%"
endlocal
