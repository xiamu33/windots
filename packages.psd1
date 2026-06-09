# =====================================================================
# Windots 包定义清单 (packages.psd1)
#
# 结构说明：
#   PackageManagers  - 包管理器选择（多选）
#   Packages         - 安装包树（分组与包可任意嵌套、混排）
#   Extras           - 全局配置（不属于具体工具，如 PowerShell Profile）
#
# 分组节点：
#   Title    - 组名或 i18n 键（优先查语言包，无则原样显示）
#   Items    - 子节点（分组或包）
#   Default  - 可选；子树内未声明 Default 的包继承此值
#
# 包节点：
#   Name     - 菜单标识名（必填）
#   Desc     - 可选；包描述（字符串或 @{ 'zh-CN'='...'; 'en-US'='...' }）
#              未配置时使用 i18n/pkg.<Name>.desc
#   Default  - 可选；覆盖分组 Default
#   Packages - 可选；实际 scoop 安装名（字符串或数组）
#   Dotfiles - 可选；@{ Src='...'; Dest='...' } 或数组
#
# 重要：
#   - Dest 路径写成字符串字面量，由脚本在运行时展开
#   - 此文件只允许字面量，不允许表达式（psd1 格式限制）
# =====================================================================
@{
    PackageManagers = @(
        @{ Key = 'scoop'; Name = 'Scoop'; Default = $true; Supported = $true }
        @{ Key = 'winget'; Name = 'Winget'; Default = $false; Supported = $false }
    )

    Packages        = @(
        @{
            Title   = 'ui.packages.group.rec'
            Default = $true
            Items   = @(
                @{ Name = 'curl' }
                @{ Name = 'fd' }
                @{ Name = 'sudo' }
                @{ Name = 'aria2'; Default = $false }
                @{ Name = 'bat' }
                @{ Name = 'delta' }
                @{ Name = 'eza' }
                @{ Name = 'lsd'; Default = $false }
                @{ Name = 'fzf' }
                @{ Name = 'jd' }
                @{ Name = 'jq' }
                @{ Name = 'ripgrep' }
                @{ Name = 'tldr'; Default = $false }
                @{ Name = 'zoxide' }
            )
        }
        @{
            Title   = 'ui.packages.group.dev'
            Default = $false
            Items   = @(
                @{
                    Name     = 'mise'
                    Packages = @('mise', 'extras/vcredist2022')
                }
                @{ Name = 'fnm' }
                @{ Name = 'pnpm' }
                @{ Name = 'rust' }
            )
        }
        @{
            Title   = 'ui.packages.group.term'
            Default = $false
            Items   = @(
                @{ Name = 'lazygit' }
                @{ Name = 'neovim' }
                @{
                    Name     = 'yazi'
                    Packages = @('yazi', 'ffmpeg', '7zip', 'jq', 'poppler', 'fd', 'ripgrep', 'fzf', 'zoxide', 'resvg', 'imagemagick')
                }
                @{ Name = 'zellij' }
            )
        }
        @{
            Title   = 'ui.packages.group.beauty'
            Default = $false
            Items   = @(
                @{ Name = 'starship' }
                @{
                    Name     = 'glazewm'
                    Dotfiles = @{ Src = 'dotfiles/glazewm/config.yaml'; Dest = 'HOME\.glzr\glazewm\config.yaml' }
                }
                @{
                    Name     = 'zebar'
                    Dotfiles = @{ Src = 'dotfiles/zebar/settings.json'; Dest = 'HOME\.glzr\zebar\settings.json' }
                }
                @{
                    Name     = 'yasb'
                    Dotfiles = @(
                        @{ Src = 'dotfiles/yasb/config.yaml'; Dest = 'HOME\.config\yasb\config.yaml' }
                        @{ Src = 'dotfiles/yasb/styles.css'; Dest = 'HOME\.config\yasb\styles.css' }
                    )
                }
                @{
                    Name     = 'flow-launcher'
                    Packages = 'extras/Flow-Launcher'
                }
            )
        }
    )

    Extras          = @(
        @{
            Src  = 'dotfiles/powershell/Profile.ps1'
            Dest = 'PROFILE'
        }
    )
}
