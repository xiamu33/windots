# dotfiles 目录

此目录由 `setup.ps1` 自动管理，内容会通过符号链接或复制方式应用到系统对应位置。

- `powershell/`：PowerShell Profile
- `windowsterminal/`：Windows Terminal `settings.json`
- `git/`：全局 `.gitconfig`
- `lazygit/`、`bat/`：工具配置

跨平台工具配置（`nvim`、`starship`、`wezterm`）由 chezmoi 单独管理，不放在本目录。
