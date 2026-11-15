@echo off
chcp 65001 >nul
rem Запуск игры "Тени Северного Леса" (двойной клик)
setlocal
set APPDATA=%~dp0tools\appdata
set LOCALAPPDATA=%~dp0tools\localdata
if exist "%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" goto run
echo.
echo Не найден движок Godot 4.7.2 stable win64.
echo Он не хранится в git-репозитории, скачайте бесплатно - установка не нужна:
echo https://github.com/godotengine/godot/releases/tag/4.7.2-stable
echo В архиве один exe. Распакуйте его в файл:
echo %~dp0tools\godot\Godot_v4.7.2-stable_win64.exe
echo Папку tools\godot создайте сами. После этого запустите этот файл снова.
echo.
pause
exit /b 1
:run
"%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0pixel-rpg"
