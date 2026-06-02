# =====================================================================
# lib.ps1 — 兼容性转发（已重构）
#
# 此文件已重构为 lib/ 目录下的多个模块文件。
# 保留此文件仅为向后兼容，它会自动加载新的模块目录。
#
# 实际实现请参阅：
#   lib/_load.ps1        — 加载器
#   lib/logging.ps1      — 日志
#   lib/i18n.ps1         — 多语言
#   lib/config.ps1       — 配置/状态文件
#   lib/context.ps1      — 上下文
#   lib/detect.ps1       — 环境检测
#   lib/proxy.ps1        — 代理
#   lib/ui.ps1           — 交互 UI
#   lib/shim.ps1         — windots 注册
#   lib/scoop.ps1        — Scoop
#   lib/backup.ps1       — 备份
#   lib/links.ps1        — 配置链接
#   lib/doctor.ps1       — 健康检查
#   lib/summary.ps1      — 运行总结
# =====================================================================

. (Join-Path $PSScriptRoot 'lib\_load.ps1')
