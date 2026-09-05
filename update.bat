@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo.
echo ============================================================
echo  VCPToolBox update.bat  —  SAFETY INTERCEPT (no git pull)
echo ============================================================
echo.
echo  This script used to run a bare "git pull" and could wipe or
echo  conflict with local work. That path is DISABLED.
echo.
echo  Production / customer / CLI Agent upgrade:
echo    docs\PRODUCTION_UPGRADE_SOP.md
echo  (backup off-repo, pm2 stop, fetch + merge --ff-only, config fill,
echo   probe 6005=200/401 and 6006=200; NEVER auto git reset --hard)
echo.
echo  Developer PR rebase only:
echo    docs\VCPToolbox更新与配置管理流程.txt
echo.
echo  Machine-specific runbook:
echo    docs\UPSTREAM_STASH_PULL_POP_CHECKLIST.md
echo.
echo  Do NOT double-click this file expecting an upgrade.
echo  Do NOT run git pull / git pull --rebase from here.
echo ============================================================
echo.

exit /b 2
