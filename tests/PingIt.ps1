Set-Location -Path $PSScriptRoot
try {
    # during debug sessions, we want make sure it's not resident in the session
    Remove-Module PingIt -ErrorAction SilentlyContinue
}
catch {
    # do nothing, we don't care
}
Import-Module .\..\PingIt.psm1

Invoke-PingIt @args

