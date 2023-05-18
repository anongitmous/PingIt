Set-Location -Path $PSScriptRoot
try {
    # during debug sessions, we want make sure it's not resident in the session
    Remove-Module PingIt -ErrorAction SilentlyContinue
}
catch {
    # do nothing, we don't care
}
# in order for this to work, ResolveDestination needs to be added to the functions exported via Export-ModuleMember in PingIt.psm1
Import-Module .\..\PingIt.psm1


while ($true) {
    [Microsoft.Powershell.Commands.TestConnectionCommand+PingStatus]$result = $null
    $result = ResolveDestination @args # it is assumed that args is being populated by the debugger from launch.json
    Start-Sleep -Seconds 1
}