# =====================================================================
# Windots 包定义清单 (packages.psd1)
#
# 结构说明：
#   PackageManagers  - 包管理器选择（多选）
#   Recommended      - 推荐安装（默认全选）
#   Optional.Dev     - 可选：开发环境
#   Optional.Term    - 可选：终端工具
#   Optional.Beauty  - 可选：美化工具
#   Extras           - 全局配置（不属于具体工具，如 PowerShell Profile）
#
# 每个工具项字段：
#   Name     - 菜单标识名（必填）
#   Desc     - 可选；包描述，交互菜单中显示在名称后
#              字符串：任意语言下均使用该描述
#              对象：当前语言 Desc > i18n 当前语言 > 默认语言 Desc > i18n 默认语言
#              示例：
#                Desc = 'Universal description'
#                Desc = @{ 'zh-CN' = '中文描述'; 'en-US' = 'English description' }
#              未配置 Desc 时，直接使用 i18n/pkg.<Name>.desc
#   Default  - 菜单中是否默认勾选（必填）
#   Packages - 可选；实际 scoop 安装名，配置后忽略 Name 作为安装名
#              支持字符串（单包）或数组（主包 + 依赖包）
#   Dotfiles - 可选；配置联动；null 表示无配置
#              @{ Src='dotfiles/...'; Dest='系统目标路径' }
#
# 重要：
#   - Dest 路径写成字符串字面量（不含 $HOME/$env），由脚本在运行时展开
#   - 此文件只允许字面量，不允许表达式（psd1 格式限制）
# =====================================================================
@{
    PackageManagers = @(
        @{ Key = 'scoop'; Name = 'Scoop'; Default = $true; Supported = $true }
        @{ Key = 'winget'; Name = 'Winget'; Default = $false; Supported = $false }
    )

    Recommended     = @(
        @{ Name = 'curl'; Default = $true }
        @{ Name = 'fd'; Default = $true }
        @{ Name = 'sudo'; Default = $true }
        @{ Name = 'aria2'; Default = $false }
        @{ Name = 'bat'; Default = $true }
        @{ Name = 'delta'; Default = $true }
        @{ Name = 'eza'; Default = $true }
        @{ Name = 'lsd'; Default = $false }
        @{ Name = 'fzf'; Default = $true }
        @{ Name = 'jd'; Default = $true }
        @{ Name = 'jq'; Default = $true }
        @{ Name = 'ripgrep'; Default = $true }
        @{ Name = 'tldr'; Default = $true }
        @{ Name = 'zoxide'; Default = $true }
    )

    Optional        = @{
        Dev    = @(
            @{
                Name     = 'mise'
                Default  = $false
                Packages = @('mise', 'extras/vcredist2022')
            }
            @{ Name = 'fnm'; Default = $false }
            @{ Name = 'pnpm'; Default = $false }
            @{ Name = 'rust'; Default = $false }
        )

        Term   = @(
            @{ Name = 'lazygit'; Default = $false }
            @{ Name = 'neovim'; Default = $false }
            @{
                Name     = 'yazi'
                Default  = $false
                Packages = @('yazi', 'ffmpeg', '7zip', 'jq', 'poppler', 'fd', 'ripgrep', 'fzf', 'zoxide', 'resvg', 'imagemagick')
            }
            @{ Name = 'zellij'; Default = $false }
        )

        Beauty = @(
            @{ Name = 'starship'; Default = $false }
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
                Dotfiles = @(
                    @{ Src = 'dotfiles/yasb/config.yaml'; Dest = 'HOME\.config\yasb\config.yaml' }
                    @{ Src = 'dotfiles/yasb/styles.css'; Dest = 'HOME\.config\yasb\styles.css' }
                )
            }
            @{ Name = 'flow-launcher'; Default = $false }
        )
    }

    Extras          = @(
        @{
            Src  = 'dotfiles/powershell/Profile.ps1'
            Dest = 'PROFILE'
        }
        # @{
        #     Src  = 'dotfiles/windowsterminal/settings.json'
        #     Dest = 'LOCAL_APPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
        # }
    )
}
