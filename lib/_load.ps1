# =====================================================================
# Windots 库加载器 (lib/_load.ps1)
# 由 setup.ps1 通过 dot-source 加载，按依赖顺序导入所有模块
# =====================================================================

$_libDir = $PSScriptRoot

. "$_libDir\logging.ps1"
. "$_libDir\i18n.ps1"
. "$_libDir\config.ps1"
. "$_libDir\context.ps1"
. "$_libDir\detect.ps1"
. "$_libDir\proxy.ps1"
. "$_libDir\ui.ps1"
. "$_libDir\shim.ps1"
. "$_libDir\scoop.ps1"
. "$_libDir\backup.ps1"
. "$_libDir\links.ps1"
. "$_libDir\doctor.ps1"
. "$_libDir\summary.ps1"
. "$_libDir\packages-apply.ps1"
. "$_libDir\commands\interactive.ps1"
. "$_libDir\commands\init.ps1"
. "$_libDir\commands\install.ps1"
. "$_libDir\commands\update.ps1"
. "$_libDir\commands\link.ps1"
. "$_libDir\commands\cd.ps1"
