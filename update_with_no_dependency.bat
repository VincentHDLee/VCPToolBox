@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo.
echo ============================================================
echo  VCPToolBox update_with_no_dependency.bat  —  DISABLED
echo ============================================================
echo.
echo  Bare "git pull" has been removed. This file will not change
echo  your working tree or install dependencies.
echo.
echo  Use docs\PRODUCTION_UPGRADE_SOP.md for production upgrades.
echo  Developer PR flow: docs\VCPToolbox更新与配置管理流程.txt
echo.
echo ============================================================
echo.

exit /b 2
