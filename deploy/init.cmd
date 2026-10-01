@echo off
REM ============================================================
REM WAF Phase 1 — Windows 初始化脚本
REM 下载 OWASP CRS v4 规则集（Git Bash / WSL 运行更好）
REM ============================================================

echo === WAF Phase 1 Init (Windows) ===
echo.

where git >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] git not found. Install from https://git-scm.com/
    exit /b 1
)

set "CRS_DIR=data-plane\rules\owasp-crs"

if exist "%CRS_DIR%\.git" (
    echo Updating existing CRS...
    cd "%CRS_DIR%"
    git fetch --depth 1 origin
    git checkout v4.0.0 2>nul || git checkout master
    git pull --ff-only
    cd ..\..\..
) else (
    echo Downloading OWASP CRS v4...
    git clone --depth 1 --branch v4.0.0 https://github.com/coreruleset/coreruleset.git "%CRS_DIR%"
)

echo.
echo [OK] OWASP CRS ready at %CRS_DIR%
echo Next: edit data-plane\Caddyfile, then docker compose up
