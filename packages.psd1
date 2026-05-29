# =====================================================================
# Windots 包定义清单 (packages.psd1)
#
# 结构说明：
#   PackageManagers  - 包管理器选择（多选，占位扩展用）
#   Recommended      - 推荐安装（默认全选）
#   Optional.Dev     - 可选：开发环境
#   Optional.Term    - 可选：终端工具
#   Optional.Beauty  - 可选：美化工具
#   Extras           - 全局配置（不属于具体工具，如 PowerShell Profile）
#
# 每个工具项字段：
#   Name     - scoop 包名
#   Default  - 菜单中是否默认勾选
#   Dotfiles - 配置联动；null 表示无配置需要链接
#              @{ Src='dotfiles/...'; Dest='系统目标路径' }
#
# 重要：
#   - Dest 路径写成字符串字面量（不含 $HOME/$env），由脚本在运行时展开
#   - 此文件只允许字面量，不允许表达式（psd1 格式限制）
# =====================================================================
@{
    # ------------------------------------------------------------------
    # 包管理器选择（第 1 步）
    # Supported=$false 的项在 UI 中显示为灰色占位，不可勾选
    # ------------------------------------------------------------------
    PackageManagers = @(
        @{ Key = 'scoop'; Name = 'Scoop'; Default = $true; Supported = $true }
        @{ Key = 'winget'; Name = 'Winget'; Default = $false; Supported = $false }
    )

    # ------------------------------------------------------------------
    # 推荐安装（默认全选）
    # ------------------------------------------------------------------
    Recommended     = @(
        @{ Name = 'curl'; Default = $true }
        @{ Name = 'fd'; Default = $true }
        @{ Name = 'sudo'; Default = $true }
        @{ Name = 'aria2'; Default = $false }
        @{ Name = 'bat'; Default = $true }
        @{ Name = 'delta'; Default = $true }
        @{ Name = 'eza'; Default = $true }
        @{ Name = 'fzf'; Default = $true }
        @{ Name = 'jd'; Default = $true }
        @{ Name = 'jq'; Default = $true }
        @{ Name = 'ripgrep'; Default = $true }
        @{ Name = 'tldr'; Default = $true }
        @{ Name = 'zoxide'; Default = $true }
    )

    # ------------------------------------------------------------------
    # 可选安装（默认不勾选）— 三个子分类
    # ------------------------------------------------------------------
    Optional        = @{

        # 开发环境
        Dev    = @(
            @{ Name = 'mise'; Default = $false }
            @{ Name = 'fnm'; Default = $false }
            @{ Name = 'pnpm'; Default = $false }
            @{ Name = 'rust'; Default = $false }
            @{ Name = 'starship'; Default = $false }
        )

        # 终端工具
        Term   = @(
            @{ Name = 'lazygit'; Default = $false }
            @{ Name = 'neovim'; Default = $false }
            @{ Name = 'yazi'; Default = $false }
            @{ Name = 'zellij'; Default = $false }
        )

        # 美化工具
        Beauty = @(
            @{
                Name     = 'glazewm'
                Default  = $false
                Dotfiles = @{ Src = 'dotfiles/glazewm/config.yaml'; Dest = 'HOME\.glzr\glazewm\config.yaml' }
            }
            @{
                Name     = 'zebar'
                Default  = $false
                Dotfiles = @{ Src = 'dotfiles/zebar/settings.json'; Dest = 'HOME\.glzr\zebar\settings.json' }
            }
            @{
                Name     = 'yasb'
                Default  = $false
                Dotfiles = $null
            }
            @{
                Name     = 'flow-launcher'
                Default  = $false
                Dotfiles = $null
            }
        )
    }

    # ------------------------------------------------------------------
    # 全局配置（不属于具体工具，但需要链接到系统）
    # Dest 中的特殊占位符由脚本展开：
    #   PROFILE_CurrentUserAllHosts -> $PROFILE.CurrentUserAllHosts
    #   HOME\... -> $HOME\...
    #   APPDATA\... -> $env:APPDATA\...
    #   LOCAL_APPDATA\... -> $env:LOCALAPPDATA\...
    # ------------------------------------------------------------------
    Extras          = @(
        @{
            Src  = 'dotfiles/powershell/Profile.ps1'
            Dest = 'PROFILE_CurrentUserAllHosts'
        }
        @{
            Src  = 'dotfiles/windowsterminal/settings.json'
            Dest = 'LOCAL_APPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
        }
    )
}