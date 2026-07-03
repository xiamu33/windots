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
#   Global   - 可选；子树内未声明 Global 的包继承此值（$true 时 scoop 使用 -g）
#
# 包节点：
#   Name     - 菜单标识名（必填）
#   Desc     - 可选；包描述（字符串或 @{ 'zh-CN'='...'; 'en-US'='...' }）
#              未配置时使用 i18n/pkg.<Name>.desc
#   Default  - 可选；覆盖分组 Default
#   Global   - 可选；为 $true 时 scoop install/uninstall 使用 -g（全局安装）
#   Packages - 可选；实际 scoop 安装名（字符串或数组）
#   Dotfiles - 可选；@{ Src='...'; Dest='...' } 或数组；Src/Dest 支持 glob（* ?）
#
# 重要：
#   - Dest 路径写成字符串字面量，由脚本在运行时展开
#   - 占位符：HOME\ APPDATA\ LOCAL_APPDATA\ SCOOP_ROOT\ SCOOP_GLOBAL\ SCOOP_PATH\ PROFILE ...
#   - SCOOP_PATH\：按包 intent scope 自动选 user/global scoop 根（用于 persist\ 下配置）
#   - glob 示例：Src='dotfiles/foo/*/bar.json' Dest='SCOOP_PATH\persist\foo\*\bar.json'
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
                        @{ Name = 'aria2'; Default = $false }
                        @{ Name = 'curl' }
                        @{ Name = 'fd' }
                        @{ Name = 'fzf' }
                        @{ Name = 'jq' }
                        @{ Name = 'ripgrep' }
                        @{ Name = 'scoop-search' }
                        @{ Name = 'sudo'; Default = $false }
                        @{ Name = 'uutils-coreutils'; Default = $false }
                        @{ Name = 'zoxide' }
                    )
                }
                @{
                    Title   = 'pkg.group.cli.plus'
                    Default = $false
                    Items   = @(
                        @{ Name = 'bat'; Default = $true }
                        @{ Name = 'bottom' }
                        @{ Name = 'btop'; Default = $true }
                        @{ Name = 'delta'; Default = $true }
                        @{ Name = 'dust' }
                        @{ Name = 'duf' }
                        @{ Name = 'eza'; Default = $true }
                        @{ Name = 'glow' }
                        @{ Name = 'hyperfine' }
                        @{ Name = 'jd' }
                        @{ Name = 'lsd' }
                        @{ Name = 'tealdeer'; Default = $true }
                        @{ Name = 'tldr' }
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
                        @{ Name = 'neovim' }
                        @{ Name = 'nushell'; Packages = 'nu' }
                        @{ Name = 'rio' }
                        @{ Name = 'vim' }
                        @{ Name = 'zellij' }
                    )
                }
                @{
                    Title = 'pkg.group.session.enhance'
                    Items = @(
                        @{ Name = 'atuin' }
                        @{ Name = 'fastfetch' }
                        @{ Name = 'PSCompletions'; Packages = 'abyss/abgox.PSCompletions' }
                        @{ Name = 'starship' }
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
                        @{ Name = 'fnm' }
                        @{
                            Name     = 'mise'
                            Default  = $true
                            Packages = @('mise', 'extras/vcredist2022')
                        }
                        @{ Name = 'pnpm' }
                        @{ Name = 'rust' }
                    )
                }
                @{
                    Title = 'pkg.group.dev.tools'
                    Items = @(
                        @{ Name = 'adb' }
                        @{ Name = 'direnv' }
                        @{ Name = 'helm' }
                        @{ Name = 'just' }
                        @{ Name = 'lazygit' }
                        @{
                            Name     = 'yazi'
                            Packages = @('yazi', 'ffmpeg', '7zip', 'jq', 'poppler', 'fd', 'ripgrep', 'fzf', 'zoxide', 'resvg', 'imagemagick')
                        }
                    )
                }
            )
        }
        @{
            Title   = 'pkg.group.apps'
            Default = $false
            Items   = @(
                @{
                    Title  = 'pkg.group.apps.editor'
                    Global = $true
                    Items  = @(
                        @{ Name = 'apifox'; Packages = 'extras/apifox' }
                        @{ Name = 'obsidian'; Packages = 'extras/obsidian' }
                        @{ Name = 'trae'; Packages = 'extras/trae' }
                        @{ Name = 'vscode'; Packages = 'extras/vscode' }
                        @{ Name = 'zed'; Packages = 'extras/zed' }
                    )
                }
                @{
                    Title  = 'pkg.group.apps.dev'
                    Global = $true
                    Items  = @(
                        @{ Name = 'dbeaver'; Packages = 'extras/dbeaver' }
                        @{ Name = 'rider'; Packages = 'extras/rider' }
                        @{ Name = 'unigetui'; Packages = 'extras/unigetui' }
                    )
                }
                @{
                    Title  = 'pkg.group.apps.remote'
                    Global = $true
                    Items  = @(
                        @{ Name = 'rustdesk'; Packages = 'extras/rustdesk' }
                        @{ Name = 'sunshine'; Packages = 'extras/sunshine' }
                        @{ Name = 'v2rayn'; Packages = 'extras/v2rayn' }
                    )
                }
                @{
                    Title = 'pkg.group.apps.productivity'
                    Items = @(
                        @{ Name = 'altsnap'; Packages = 'extras/altsnap' }
                        @{ Name = 'everything'; Packages = 'extras/everything'; Global = $true }
                        @{ Name = 'everythingtoolbar'; Packages = 'extras/everythingtoolbar'; Global = $true }
                        @{
                            Name     = 'flow-launcher'
                            Packages = 'extras/Flow-Launcher'
                            Dotfiles = @(
                                @{ Src = 'dotfiles/flow-launcher/Settings/Settings.json'; Dest = 'SCOOP_PATH\persist\Flow-Launcher\UserData\Settings\Settings.json' }
                                @{ Src = 'dotfiles/flow-launcher/Settings/Plugins/*/Settings.json'; Dest = 'SCOOP_PATH\persist\Flow-Launcher\UserData\Settings\Plugins\*\Settings.json' }
                            )
                        }
                        @{ Name = 'InputTip'; Packages = 'abyss/abgox.InputTip-zip' }
                        @{ Name = 'pixpin'; Packages = 'abyss/PixPin.PixPin' }
                        @{ Name = 'powertoys'; Packages = 'extras/powertoys'; Global = $true }
                    )
                }
                @{
                    Title = 'pkg.group.apps.utils'
                    Items = @(
                        @{ Name = 'rufus'; Packages = 'extras/rufus' }
                        @{ Name = 'steampp'; Packages = 'abyss/BeyondDimension.Steampp' }
                        @{ Name = 'windirstat'; Packages = 'extras/windirstat' }
                        @{ Name = 'wsl-dashboard'; Packages = 'abyss/owu.wsl-dashboard' }
                        @{ Name = 'wsl-ui'; Packages = 'abyss/OctasoftLtd.WSLUI' }
                    )
                }
                @{
                    Title = 'pkg.group.apps.wm'
                    Items = @(
                        @{
                            Name     = 'glazewm'
                            Dotfiles = @(
                                @{ Src = 'dotfiles/glazewm/config.yaml'; Dest = 'HOME\.glzr\glazewm\config.yaml' }
                                @{ Src = 'dotfiles/glazewm/toggle-win-maximize.cs'; Dest = 'HOME\.glzr\glazewm\toggle-win-maximize.cs' }
                                @{ Src = 'dotfiles/glazewm/build-toggle-win-maximize.ps1'; Dest = 'HOME\.glzr\glazewm\build-toggle-win-maximize.ps1' }
                            )
                        }
                        @{
                            Name     = 'komorebi'
                            Packages = @('komorebi', 'whkd')
                        }
                        @{ Name = 'tacky-borders'; Packages = 'extras/tacky-borders' }
                        @{
                            Name     = 'yasb'
                            Dotfiles = @(
                                @{ Src = 'dotfiles/yasb/config.yaml'; Dest = 'HOME\.config\yasb\config.yaml' }
                                @{ Src = 'dotfiles/yasb/styles.css'; Dest = 'HOME\.config\yasb\styles.css' }
                            )
                        }
                        @{
                            Name     = 'zebar'
                            Dotfiles = @{ Src = 'dotfiles/zebar/settings.json'; Dest = 'HOME\.glzr\zebar\settings.json' }
                        }
                    )
                }
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
        @{ Src = 'dotfiles/powershell/Profile.ps1'; Dest = 'PROFILE' }
        @{ Src = 'dotfiles/powershell/init'; Dest = 'PROFILE_ROOT\init' }
        @{ Src = 'dotfiles/powershell/functions'; Dest = 'PROFILE_ROOT\functions' }
        @{ Src = 'dotfiles/powershell/aliases'; Dest = 'PROFILE_ROOT\aliases' }
    )
}
