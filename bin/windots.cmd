@echo off
:: windots - Windows dev environment manager
:: Usage: windots [install|update|link|doctor]
:: Requires WINDOTS_ROOT env var pointing to the repo.
if "%WINDOTS_ROOT%"=="" (
    echo [ERR] WINDOTS_ROOT not set. Please run setup.ps1 from the repo first.
    exit /b 1
)
pwsh -NoProfile -ExecutionPolicy Bypass -File "%WINDOTS_ROOT%\setup.ps1" %*
