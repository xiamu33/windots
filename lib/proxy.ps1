# =====================================================================
# Windots 代理 (lib/proxy.ps1)
# =====================================================================

function Set-SessionProxy {
    param([string] $Url)
    if ([string]::IsNullOrWhiteSpace($Url)) {
        Remove-Item Env:HTTP_PROXY  -ErrorAction SilentlyContinue
        Remove-Item Env:HTTPS_PROXY -ErrorAction SilentlyContinue
        Remove-Item Env:ALL_PROXY   -ErrorAction SilentlyContinue
        return
    }
    $env:HTTP_PROXY = $Url
    $env:HTTPS_PROXY = $Url
    $env:ALL_PROXY = $Url
    Write-Info (msg 'proxy.set' $Url)
}
