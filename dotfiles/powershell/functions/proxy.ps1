function global:proxy {
  param(
    [ValidateSet('socks', 'http')]
    [string]$Type = 'socks'
  )
  $url = if ($Type -eq 'http') { 'http://127.0.0.1:10809' } else { 'socks5://127.0.0.1:10808' }
  $env:ALL_PROXY = $url
  $env:HTTP_PROXY = $url
  $env:HTTPS_PROXY = $url
}

function global:unproxy {
  Remove-Item Env:ALL_PROXY -ErrorAction SilentlyContinue
  Remove-Item Env:HTTP_PROXY -ErrorAction SilentlyContinue
  Remove-Item Env:HTTPS_PROXY -ErrorAction SilentlyContinue
}
