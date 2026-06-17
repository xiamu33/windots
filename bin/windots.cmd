@echo off
:: windots.cmd - cmd.exe fallback (cd works natively; other commands delegate to setup.ps1)
:: Usage: windots [init|install|i|uninstall|rm|update|up|migrate|clean|link|doctor|cd]
:: Requires WINDOTS_ROOT env var pointing to the repo.
if "%WINDOTS_ROOT%"=="" (
    echo [ERR] WINDOTS_ROOT not set. Please run setup.ps1 from the repo first.
    exit /b 1
)
if /i "%1"=="cd" (
    cd /d "%WINDOTS_ROOT%"
    exit /b 0
)
pwsh -NoProfile -ExecutionPolicy Bypass -File "%WINDOTS_ROOT%\setup.ps1" %*
