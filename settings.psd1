# =====================================================================
# Windots 用户全局配置 (settings.psd1)
# 修改此文件后重新运行 setup.ps1 或 windots init 使配置生效
# =====================================================================
@{
    # ------------------------------------------------------------------
    # 语言 / Language
    # 留空时自动检测系统区域：中文系统→zh-CN，英文系统→en-US，其他→en-US
    # 可选值：'zh-CN' | 'en-US' | ''（自动）
    # ------------------------------------------------------------------
    Language   = ''

    # ------------------------------------------------------------------
    # 代理
    # ------------------------------------------------------------------
    Proxy      = @{
        Enabled = $false
        Url     = 'socks5://127.0.0.1:10808'
    }

    # ------------------------------------------------------------------
    # Scoop
    # MirrorUrl：国内镜像安装脚本（UseMirror 为 $true 时使用）
    # SetConfig：scoop config 键值（安装后自动写入未设置的项）
    #   ROOT_PATH / root_path   → scoop 用户安装目录
    #   GLOBAL_PATH / global_path → scoop 全局安装目录
    #   SCOOP_REPO              → scoop 仓库镜像地址
    # Buckets：额外 bucket 列表（scoop 安装时默认仅含 main）
    #   - 字符串：bucket 名称，如 'extras'（使用 scoop 默认源）
    #   - 对象：@{ Name = 'mybucket'; Url = 'https://...' }
    # ------------------------------------------------------------------
    Scoop      = @{
        UseMirror = $true
        MirrorUrl = 'https://gitee.com/scoop-installer/install/raw/master/install.ps1'
        SetConfig = @{
            ROOT_PATH   = 'C:\Users\xiamu\scoop'
            GLOBAL_PATH = 'C:\ProgramData\scoop'
            SCOOP_REPO  = 'https://gitee.com/scoop-installer/scoop'
        }
        Buckets   = @(
            'extras',
            'nerd-fonts',
            @{ Name = 'abyss'; Url = 'https://gitee.com/abgox/abyss' }
        )
    }

    # ------------------------------------------------------------------
    # chezmoi（跨平台工具配置同步）
    # Username：GitHub 用户名（默认仓库 dotfiles）或完整仓库地址
    # ------------------------------------------------------------------
    Chezmoi    = @{
        Enabled     = $true
        Username    = 'xiamu33'
        ApplyOnInit = $true
    }

    # ------------------------------------------------------------------
    # 仓库（git 自更新 / 迁移）
    # ------------------------------------------------------------------
    Repository = @{
        Url = 'https://github.com/xiamu33/windots'
    }

    # ------------------------------------------------------------------
    # 路径（相对仓库根）
    # ------------------------------------------------------------------
    Paths      = @{
        Dotfiles = './dotfiles'
        Backup   = './backup'
        Logs     = './logs'
        State    = './.windots-state.psd1'
    }
}
