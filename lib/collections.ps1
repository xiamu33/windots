# =====================================================================
# Windots 集合辅助 (lib/collections.ps1)
# StrictMode Latest 下 PowerShell 会把 return @() / 单元素数组展开成
# $null / 标量；对结果直接 .Count / 当 [string[]] 绑定会反复踩坑。
# 约定：
#   - 返回集合：return , [string[]]@(...) 或 ConvertTo-WindotsStringArray
#   - 计数：Get-WindotsCount $x（勿对可能为 $null 的值直接 .Count）
#   - 遍历：foreach ($i in (ConvertTo-WindotsStringArray $x))
#     切勿写成 foreach ($i in @(ConvertTo-WindotsStringArray $x))
#     （外层 @() 会把整个 string[] 当成一个元素）
# =====================================================================

function ConvertTo-WindotsArray {
    param([AllowNull()] $InputObject)
    if ($null -eq $InputObject) { return , @() }
    return , @($InputObject)
}

function ConvertTo-WindotsStringArray {
    param([AllowNull()] $InputObject)
    if ($null -eq $InputObject) { return , [string[]]@() }
    $arr = [string[]]@(
        @($InputObject) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    return , $arr
}

function Get-WindotsCount {
    param([AllowNull()] $InputObject)
    if ($null -eq $InputObject) { return 0 }
    return @($InputObject).Count
}
