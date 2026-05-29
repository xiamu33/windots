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
#   Name     - 菜单标识名（最少需配置 Name、Default）
#   Default  - 菜单中是否默认勾选
#   Desc     - 可选；列出时在包名后以括号显示说明
#   Packages - 可选；实际 scoop 安装名，配置后忽略 Name 作为安装名
#              支持字符串（单包）或数组（主包 + 依赖包）
#   Dotfiles - 可选；配置联动；null 表示无配置需要链接
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
        @{
            Name    = 'fd'
            Default = $true
            Desc    = '更快的 find 替代'
        }
        @{ Name = 'sudo'; Default = $true }
        @{ Name = 'aria2'; Default = $false }
        @{
            Name    = 'bat'
            Default = $true
            Desc    = '带语法高亮的 cat 替代'
        }
        @{
            Name    = 'delta'
            Default = $true
            Desc    = 'git diff 高亮增强'
        }
        @{
            Name    = 'eza'
            Default = $true
            Desc    = '更好的 ls 替代'
        }
        @{
            Name    = 'lsd'
            Default = $false
            Desc    = '更好的 ls 替代（eza 替代）'
        }
        @{
            Name    = 'fzf'
            Default = $true
            Desc    = '模糊搜索工具'
        }
        @{
            Name    = 'jd'
            Default = $true
            Desc    = 'JSON diff 工具'
        }
        @{
            Name    = 'jq'
            Default = $true
            Desc    = 'JSON 命令行处理器'
        }
        @{
            Name    = 'ripgrep'
            Default = $true
            Desc    = '更快的 grep 替代'
        }
        @{
            Name    = 'tldr'
            Default = $true
            Desc    = '简化版命令手册'
        }
        @{
            Name    = 'zoxide'
            Default = $true
            Desc    = '智能目录跳转（cd 增强）'
        }
    )

    # ------------------------------------------------------------------
    # 可选安装（默认不勾选）— 三个子分类
    # ------------------------------------------------------------------
    Optional        = @{

        # 开发环境
        Dev    = @(
            @{
                Name     = 'mise'
                Default  = $false
                Desc     = '多语言版本管理器（asdf 替代）'
                Packages = @('mise', 'extras/vcredist2022')
            }
            @{
                Name    = 'fnm'
                Default = $false
                Desc    = '快速 Node.js 版本管理器'
            }
            @{
                Name    = 'pnpm'
                Default = $false
                Desc    = '高效的 Node.js 包管理器'
            }
            @{ Name = 'rust'; Default = $false }
        )

        # 终端工具
        Term   = @(
            @{
                Name    = 'lazygit'
                Default = $false
                Desc    = 'Git TUI 客户端'
            }
            @{
                Name    = 'neovim'
                Default = $false
                Desc    = '基于 Vim 的现代编辑器'
            }
            @{
                Name     = 'yazi'
                Default  = $false
                Desc     = '终端文件管理器'
                Packages = @('yazi', 'ffmpeg', '7zip', 'jq', 'poppler', 'fd', 'ripgrep', 'fzf', 'zoxide', 'resvg', 'imagemagick')
            }
            @{
                Name    = 'zellij'
                Default = $false
                Desc    = '终端多路复用器'
            }
        )

        # 美化工具
        Beauty = @(
            @{
                Name    = 'starship'
                Default = $false
                Desc    = '跨 shell 提示符'
            }
            @{
                Name     = 'glazewm'
                Default  = $false
                Desc     = 'Windows 平铺式窗口管理器'
                Dotfiles = @{ Src = 'dotfiles/glazewm/config.yaml'; Dest = 'HOME\.glzr\glazewm\config.yaml' }
            }
            @{
                Name     = 'zebar'
                Default  = $false
                Desc     = 'Windows 状态栏'
                Dotfiles = @{ Src = 'dotfiles/zebar/settings.json'; Dest = 'HOME\.glzr\zebar\settings.json' }
            }
            @{
                Name     = 'yasb'
                Default  = $false
                Desc     = 'Windows 状态栏'
                Dotfiles = $null
            }
            @{
                Name    = 'flow-launcher'
                Default = $false
                Desc    = '应用启动器'
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