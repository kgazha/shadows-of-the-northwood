@echo off
rem Запуск игры "Тени Северного Леса" (двойной клик)
setlocal
set APPDATA=%~dp0tools\appdata
set LOCALAPPDATA=%~dp0tools\localdata
"%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0pixel-rpg"
