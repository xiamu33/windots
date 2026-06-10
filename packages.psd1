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
            Title = 'pkg.group.cli'
            Items = @(
                @{
                    Title   = 'pkg.group.cli.base'
                    Default = $true
                    Items   = @(
                        @{ Name = '7zip' }
                        @{ Name = 'curl' }
                        @{ Name = 'fd' }
                        @{ Name = 'fzf' }
                        @{ Name = 'jq' }
                        @{ Name = 'ripgrep' }
                        @{ Name = 'zoxide' }
                        @{ Name = 'aria2'; Default = $false }
                        @{ Name = 'sudo'; Default = $false }
                        @{ Name = 'scoop-search'; Default = $false }
                        @{ Name = 'uutils-coreutils'; Default = $false }
                    )
                }
                @{
                    Title   = 'pkg.group.cli.plus'
                    Default = $true
                    Items   = @(
                        @{ Name = 'bat' }
                        @{ Name = 'btop' }
                        @{ Name = 'delta' }
                        @{ Name = 'eza' }
                        @{ Name = 'bottom'; Default = $false }
                        @{ Name = 'lsd'; Default = $false }
                        @{ Name = 'dark'; Default = $false }
                        @{ Name = 'jd'; Default = $false }
                        @{ Name = 'tldr'; Default = $false }
                    )
                }
            )
        }
        @{
            Title   = 'pkg.group.session'
            Default = $false
            Items   = @(
                @{
                    Title = 'pkg.group.session.term'
                    Items = @(
                        @{ Name = 'alacritty'; Packages = 'extras/alacritty' }
                        @{ Name = 'rio' }
                        @{ Name = 'nushell'; Packages = 'nu' }
                        @{ Name = 'vim' }
                        @{ Name = 'neovim' }
                        @{ Name = 'zellij' }
                    )
                }
                @{
                    Title = 'pkg.group.session.enhance'
                    Items = @(
                        @{ Name = 'starship' }
                        @{ Name = 'atuin' }
                        @{ Name = 'fastfetch' }
                    )
                }
            )
        }
        @{
            Title   = 'pkg.group.dev'
            Default = $false
            Items   = @(
                @{
                    Title = 'pkg.group.dev.runtime'
                    Items = @(
                        @{
                            Name     = 'mise'
                            Default  = $true
                            Packages = @('mise', 'extras/vcredist2022')
                        }
                        @{ Name = 'fnm' }
                        @{ Name = 'pnpm' }
                        @{ Name = 'rust' }
                    )
                }
                @{
                    Title = 'pkg.group.dev.tools'
                    Items = @(
                        @{ Name = 'lazygit' }
                        @{
                            Name     = 'yazi'
                            Packages = @('yazi', 'ffmpeg', '7zip', 'jq', 'poppler', 'fd', 'ripgrep', 'fzf', 'zoxide', 'resvg', 'imagemagick')
                        }
                        @{ Name = 'PSCompletions'; Packages = 'abyss/abgox.PSCompletions' }
                    )
                }
            )
        }
        @{
            Title   = 'pkg.group.desktop'
            Default = $false
            Items   = @(
                @{
                    Title = 'pkg.group.desktop.wm'
                    Items = @(
                        @{
                            Name     = 'glazewm'
                            Dotfiles = @{ Src = 'dotfiles/glazewm/config.yaml'; Dest = 'HOME\.glzr\glazewm\config.yaml' }
                        }
                        @{
                            Name     = 'komorebi'
                            Packages = @('komorebi', 'whkd')
                        }
                    )
                }
                @{
                    Title = 'pkg.group.desktop.bar'
                    Items = @(
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
                        @{ Name = 'tacky-borders'; Packages = 'extras/tacky-borders' }
                    )
                }
            )
        }
        @{
            Title   = 'pkg.group.win'
            Default = $false
            Items   = @(
                @{ Name = 'flow-launcher'; Packages = 'extras/Flow-Launcher' }
                @{ Name = 'altsnap'; Packages = 'extras/altsnap' }
                @{ Name = 'InputTip'; Packages = 'abyss/abgox.InputTip-zip' }
                @{ Name = 'powertoys' }
            )
        }
        @{
            Title   = 'pkg.group.fonts'
            Default = $true
            Items   = @(
                @{ Name = 'JetBrainsMono-NF'; Packages = 'nerd-fonts/JetBrainsMono-NF' }
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
